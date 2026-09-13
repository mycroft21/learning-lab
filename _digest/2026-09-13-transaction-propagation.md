---
title: "트랜잭션 전파(Propagation)"
date: 2026-09-13
domain: spring
slots: 1
parts_done: 1
tags: [spring, transaction, propagation, jpa]
---

## 전파 옵션 7개를 외우는 방식으로는 아무것도 안 풀린다

결제는 롤백되고 실패 로그는 남아야 한다. `saveFailLog()`에 `@Transactional(propagation = REQUIRES_NEW)`를 붙였는데 정작 결제가 터진 케이스에서 로그도 같이 사라진다 — 여기서 보통 "옵션을 잘못 골랐나" 하고 표를 다시 들여다보게 되는데, 표를 몇 번 더 봐도 답이 안 나온다. 표에는 답이 없기 때문이다.

옵션 이름이 아니라 **DB 입장에서 트랜잭션이 몇 개 시작됐는지**를 먼저 봐야 한다. 확인은 로그 한 줄이면 된다.

```properties
logging.level.org.springframework.transaction=DEBUG
```

`REQUIRES_NEW`가 제대로 걸렸으면 안쪽 메서드에 진입할 때 이 두 줄이 나란히 찍힌다.

```
DEBUG o.s.o.j.JpaTransactionManager : Suspending current transaction
DEBUG o.s.o.j.JpaTransactionManager : Creating new transaction with name [com.x.LogService.saveFailLog]
```

대신 이 줄이 나오면 옵션이 무시된 것이다.

```
DEBUG o.s.o.j.JpaTransactionManager : Participating in existing transaction
```

`Participating`이 찍혔다면 원인은 전파 설정이 아니라 그 호출이 프록시를 안 거쳤다는 쪽일 가능성이 높다. 그건 [AOP 프록시 편](/learning-lab/digest/2026-09-11-aop-proxy-self-invocation/)에서 다뤘으니 여기서는 프록시를 제대로 거친 뒤의 이야기만 한다.

> 전파 옵션이 실제로 정하는 건 하나다 — **이 호출로 물리 트랜잭션이 몇 개가 되는가.** `REQUIRED`는 1개, `REQUIRES_NEW`는 2개, `NESTED`는 1개 + 세이브포인트. 나머지는 전부 여기서 연역된다.

여기서 용어를 정확히 갈라둘 필요가 있다. `@Transactional`이 붙은 메서드 하나가 **논리 트랜잭션** 하나다. 반면 **물리 트랜잭션**은 실제 커넥션 위에서 `setAutoCommit(false)`부터 `commit()`까지 이어지는 진짜 구간이다. 전파는 논리 여러 개를 물리 몇 개에 어떻게 얹을지를 정하는 규칙이고, 실무의 사고는 전부 이 매핑에서 나온다.

## 물리 1개의 대가 — 안쪽 예외를 삼켜도 바깥이 죽는다

`REQUIRED`(기본값)에서 논리는 둘인데 물리는 하나다. 커넥션이 하나이므로 **안쪽 메서드는 커밋할 권한이 없다.** 물리 트랜잭션을 시작한 건 바깥이고, 끝낼 사람도 바깥이다.

그래서 안쪽이 예외로 끝나면 Spring이 할 수 있는 일은 공용 트랜잭션에 "이건 롤백해야 함" 표시(rollback-only)를 세워두는 것뿐이다. 이 표시는 지워지지 않는다. 바깥에서 예외를 잡아 삼키고 정상 종료해도, 커밋을 시도하는 순간 이렇게 된다.

```java
@Transactional
public void placeOrder() {
    try {
        couponService.use(...);   // REQUIRED, 안에서 예외 발생
    } catch (Exception e) {
        log.warn("쿠폰 실패, 주문은 계속", e);  // 삼켰다고 생각하지만
    }
    orderRepository.save(order);
}   // ← 여기서 터진다
```

```
UnexpectedRollbackException: Transaction rolled back because it has been
marked as rollback-only
```

`try-catch`가 안 통한다는 게 이 예외의 본질이다. 예외는 자바 코드 흐름의 문제고 rollback-only는 트랜잭션 상태의 문제라서, 층이 다르다. "안쪽 실패를 무시하고 진행"을 하려면 **물리 트랜잭션을 갈라야** 한다 — 즉 안쪽을 `REQUIRES_NEW`로 바꿔야 한다. 옵션을 바꾸는 게 아니라 물리 개수를 바꾸는 것이다.

## 물리 2개의 대가 — 커넥션 두 개와, 서로 안 보이는 데이터

`REQUIRES_NEW`는 바깥 트랜잭션을 보류(suspend)하고 **새 커넥션을 하나 더 얻어** 독립된 물리 트랜잭션을 연다. 바깥이 죽어도 안쪽은 이미 커밋돼 살아남는다는 원하던 성질이 여기서 나오는데, 대가가 둘 따라온다.

**한 스레드가 커넥션을 두 개 동시에 점유한다.** HikariCP 기본 풀 크기가 10인데 동시 요청 6개가 각각 `REQUIRES_NEW`에 진입하면 12개를 요구하게 되고, 서로가 남의 두 번째 커넥션을 기다리며 아무도 풀려나지 않는다. 애플리케이션 코드에는 락이 한 줄도 없는데 데드락이 나는 전형적인 모양이다. 커넥션을 좁게 잡아둔 배치 서버에서 특히 잘 터진다.

**두 트랜잭션은 서로의 미커밋 데이터를 못 본다.** 이게 더 자주 물린다. 바깥에서 방금 저장한 행을 안쪽 `REQUIRES_NEW`에서 조회하면, 격리 수준이 `READ_COMMITTED`(MySQL InnoDB는 `REPEATABLE_READ`)인 이상 **아직 커밋 안 된 남의 변경**이므로 안 보인다. 같은 스레드, 같은 요청인데 데이터가 없다. 한술 더 떠 그 행을 안쪽에서 `UPDATE`하려 하면 바깥이 쥔 락을 기다리는데, 바깥은 안쪽이 끝나기를 기다리고 있으니 **자기 자신과 데드락**이 난다.

`REQUIRES_NEW`를 "안전하게 분리해주는 옵션"으로 기억하고 있으면 이 둘이 안 보인다. 물리 트랜잭션이 둘이라는 사실에서 전부 바로 따라 나온다.

## `NESTED` — 1개 + 세이브포인트라서, 절반만 되돌아간다

`NESTED`를 "가벼운 `REQUIRES_NEW`"로 알고 있으면 가장 크게 헷갈린다. 물리 트랜잭션은 **하나**다. 커넥션도 하나다. 안쪽 진입 시점에 JDBC `Savepoint`를 하나 찍어두고, 안쪽이 실패하면 그 지점까지만 되감는 것이다.

여기서 두 개의 경계가 갈린다.

**첫째, 그 기능이 켜져 있느냐.** `nestedTransactionAllowed` 플래그가 트랜잭션 매니저마다 기본값이 다르다.

| 트랜잭션 매니저 | `nestedTransactionAllowed` 기본값 | `NESTED` 선언 시 |
|---|---|---|
| `DataSourceTransactionManager` | `true` | 세이브포인트로 동작 |
| `JpaTransactionManager` | `false` | `NestedTransactionNotSupportedException` |

JPA 매니저가 기본값을 `false`로 둔 이유가 Javadoc에 그대로 적혀 있다 — 중첩 트랜잭션은 JDBC 커넥션에만 적용되고 `EntityManager`와 그 캐시된 엔티티에는 적용되지 않기 때문이다.

**둘째, 켜도 절반만 돌아간다.** 세이브포인트는 커넥션 레벨 개념이라 이미 DB로 날아간 SQL은 되감지만, **JPA 영속성 컨텍스트는 그 사실을 모른다.** 1차 캐시에 올라온 엔티티, 변경 감지로 더티 마킹된 상태는 그대로 남는다. DB는 되돌아갔는데 자바 객체는 안 돌아간 상태로 남고, 이후 플러시가 그 엔티티를 다시 밀어 넣을 수도 있다. 그래서 JPA 엔티티를 다루는 코드에서는 영속성 컨텍스트까지 새로 시작하는 `REQUIRES_NEW`가 훨씬 예측 가능하다.

"부분 롤백이 필요하면 `NESTED`"라는 지식은 순수 JDBC(`JdbcTemplate`, MyBatis) 기준이다. JPA 프로젝트에서 그 문장을 그대로 말하면 후속 질문에서 갈린다.

<details markdown="1">
<summary>나머지 네 옵션 — 물리 개수 축에 얹어서</summary>

`SUPPORTS`, `NOT_SUPPORTED`, `MANDATORY`, `NEVER`는 물리 트랜잭션을 새로 만들지 않는다. 같은 축 위에서 "물리 0개"를 다루거나, 바깥 상태를 검사만 하는 쪽이다.

| 옵션 | 바깥 트랜잭션 있을 때 | 없을 때 | 물리 개수 |
|---|---|---|---|
| `SUPPORTS` | 참여 | 트랜잭션 없이 실행 | 1 또는 0 |
| `NOT_SUPPORTED` | 보류하고 트랜잭션 없이 실행 | 트랜잭션 없이 실행 | 0 (보류된 1개 유지) |
| `MANDATORY` | 참여 | `IllegalTransactionStateException` | 1 또는 실패 |
| `NEVER` | `IllegalTransactionStateException` | 트랜잭션 없이 실행 | 0 또는 실패 |

`NOT_SUPPORTED`는 `REQUIRES_NEW`와 같은 보류 메커니즘을 쓰되 새 트랜잭션을 열지 않는다 — 긴 조회나 외부 API 호출로 커넥션을 오래 붙잡기 싫을 때 쓴다. `MANDATORY`와 `NEVER`는 실행이 아니라 **계약 검사**다. "이 메서드는 반드시 트랜잭션 안/밖에서만 불려야 한다"를 주석 대신 코드로 강제하는 용도라 사용 빈도는 낮지만 정의는 자주 묻는다.

</details>

## 인터뷰에서 이렇게 나온다

**"`REQUIRED`인 안쪽 메서드에서 예외가 났는데, 바깥에서 `try-catch`로 잡았습니다. 바깥 트랜잭션은 커밋되나요?"**

<details markdown="1">
<summary>답 확인</summary>

커밋되지 않고 `UnexpectedRollbackException`이 난다. `REQUIRED`는 물리 트랜잭션이 하나라서 안쪽 논리 트랜잭션에는 커밋·롤백 권한이 없고, 실패하면 공용 트랜잭션에 rollback-only 표시만 세운다. 자바 예외는 `catch`로 삼켰지만 트랜잭션 상태의 표시는 그대로 남아 있어서, 바깥이 커밋을 시도할 때 거절된다. 안쪽 실패를 무시하고 진행해야 한다면 안쪽을 `REQUIRES_NEW`로 만들어 물리 트랜잭션 자체를 분리해야 한다.

</details>

**"`REQUIRES_NEW`와 `NESTED`의 차이를 설명해보세요."**

<details markdown="1">
<summary>답 확인</summary>

물리 트랜잭션 개수로 답한다. `REQUIRES_NEW`는 바깥을 보류하고 커넥션을 하나 더 얻어 물리 트랜잭션을 2개로 만든다 — 그래서 완전히 독립적이고, 바깥이 롤백돼도 살아남으며, 대신 커넥션을 두 개 물고 서로의 미커밋 데이터를 못 본다. `NESTED`는 물리 트랜잭션이 1개이고 커넥션도 하나이며, 세이브포인트를 찍어 부분 롤백만 흉내 낸다 — 바깥이 롤백되면 안쪽도 같이 사라진다. 덧붙여 `JpaTransactionManager`는 `nestedTransactionAllowed` 기본값이 `false`라 `NESTED` 자체가 예외로 막히고, 켜더라도 세이브포인트가 JDBC 레벨에만 걸려 영속성 컨텍스트는 되돌아가지 않는다.

</details>

**"`REQUIRES_NEW`를 남용하면 어떤 문제가 생기나요?"**

<details markdown="1">
<summary>답 확인</summary>

한 스레드가 커넥션을 두 개 동시에 점유한다는 데서 출발해 두 가지를 말한다. 동시 요청이 풀 크기의 절반을 넘으면 서로의 두 번째 커넥션을 기다리며 풀이 고갈되고, 애플리케이션 락이 없어도 데드락처럼 멈춘다. 그리고 두 트랜잭션은 격리돼 있어 바깥에서 방금 저장한 미커밋 데이터를 안쪽에서 조회할 수 없고, 같은 행을 수정하려 하면 바깥이 쥔 락을 기다리다 서로 물린다.

</details>

## 한 줄 요약

> 전파 옵션은 외우는 목록이 아니라 **물리 트랜잭션 개수를 정하는 다이얼**이다 — `REQUIRED`는 1개라 안쪽 실패가 rollback-only로 바깥까지 오염시키고, `REQUIRES_NEW`는 2개라 독립적인 대신 커넥션을 둘 물고 서로를 못 보며, `NESTED`는 1개+세이브포인트라 JDBC만 되감고 JPA 영속성 컨텍스트는 그대로 남는다.
