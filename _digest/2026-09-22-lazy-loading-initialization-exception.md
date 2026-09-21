---
title: "지연 로딩과 LazyInitializationException"
date: 2026-09-22
domain: jpa
slots: 1
parts_done: 1
tags: [jpa, lazy-loading, hibernate]
---

## 예외가 안 난다고 지연 로딩을 이해한 건 아니다

컨트롤러에서 엔티티를 반환하고 그 안의 LAZY 연관을 직렬화하는데도 아무 문제 없이 돌아가는 코드를 오래 써왔다면, 지연 로딩이 원래 그렇게 동작한다고 알고 있을 가능성이 높다. 기동 로그를 다시 보면 그 이유가 적혀 있다.

```
WARN ... : spring.jpa.open-in-view is enabled by default. Therefore, database
queries may be performed during view rendering. Explicitly configure
spring.jpa.open-in-view to disable this warning
```

Spring Boot는 OSIV(Open Session In View)를 **기본값 `true`**로 켜둔다. 트랜잭션이 끝난 뒤에도 HTTP 요청이 끝날 때까지 영속성 컨텍스트를 열어두기 때문에, 서비스 계층 밖에서 LAZY 연관을 건드려도 조용히 쿼리가 나간다. 예외가 안 난 게 아니라, 예외가 날 조건이 아직 안 온 것이다.

## 프록시는 약속이고, 그 약속에는 유효기간이 있다

LAZY 연관에 들어 있는 건 엔티티가 아니라 **"아직 안 읽었다. 필요해지면 그때 읽어주겠다"는 약속**, 즉 프록시다. 찍어보면 정체가 드러난다.

```java
Order order = em.find(Order.class, 1L);
System.out.println(order.getMember().getClass());
// class com.example.Member$HibernateProxy$Xy3kQ1aB
System.out.println(Hibernate.isInitialized(order.getMember())); // false
```

그리고 이 약속을 이행할 수 있는 주체는 영속성 컨텍스트뿐이다. 프록시는 자기를 만들어준 컨텍스트를 붙들고 있다가, 값이 필요해지는 순간 그쪽에 쿼리를 요청한다. 컨텍스트가 닫혀 있으면 요청할 곳이 없고, 그 자리에서 `LazyInitializationException`이 난다. 예외는 지연 로딩의 결함이 아니라 **약속의 유효기간이 끝난 지점을 알려주는 신호**다.

여기서 유효기간이 언제까지인지가 전부 갈린다.

- **트랜잭션 안** — 당연히 살아 있다.
- **트랜잭션은 끝났지만 HTTP 요청은 진행 중** — OSIV가 켜져 있으면 살아 있고, 꺼져 있으면 죽어 있다. 같은 코드가 설정 한 줄에 따라 되기도 하고 안 되기도 하는 구간이 정확히 여기다.
- **요청 스레드를 벗어난 곳**(`@Async`, 배치, 이벤트 리스너의 별도 스레드) — OSIV와 무관하게 죽어 있다. 스레드 경계를 넘을 때 영속성 컨텍스트가 따라가지 않는 문제는 [비동기/캐시 함정 편](/learning-lab/digest/2026-09-19-async-cache-pitfalls/)에서 다뤘다. 여기서는 같은 스레드 안에서도 유효기간이 갈리는 지점만 본다.

## OSIV는 해결이 아니라 거래다

> 영속성 컨텍스트를 요청이 끝날 때까지 열어두면 DB 커넥션도 그만큼 오래 붙들고 있게 된다 — 예외를 없애는 대가로 커넥션 점유 시간을 뷰 렌더링까지 늘린 것이다.

트래픽이 적을 땐 티가 안 나다가 커넥션 풀이 마르는 형태로 뒤늦게 드러난다. 그래서 OSIV를 끄고 필요한 데이터를 트랜잭션 안에서 확정 짓는 쪽이 정석으로 통한다. 방법은 상황에 따라 갈린다.

- **`fetch join`이나 `@EntityGraph`로 미리 읽기** — 그 연관을 반드시 쓸 게 확실할 때.
- **DTO로 투영해서 반환** — 엔티티를 계층 밖으로 내보내지 않으면 약속을 들고 나갈 일 자체가 없다.
- **`Hibernate.initialize()`로 명시적 초기화** — 조건부로 필요할 때.

`FetchType.EAGER`로 바꾸는 건 이 목록에 없다. 연관마다 항상 읽게 되어 쓰지도 않을 조인이 따라붙고, 어떤 쿼리가 나갈지 호출 지점에서 예측할 수 없게 된다.

## 프록시라서 생기는 부수 효과

- **`getReference()`는 쿼리를 안 보낸다.** 식별자만 필요한 연관 설정(예: `order.setMember(em.getReference(Member.class, 1L))`)에서는 `SELECT` 없이 프록시만 받아 쓰는 게 정상 동작이다.
- **`instanceof`와 `getClass()` 비교가 어긋난다.** 프록시는 원본을 상속한 별개 클래스라 `getClass() == Member.class`가 `false`다. `equals`를 `getClass()` 비교로 구현해두면 프록시가 섞이는 순간 같은 엔티티인데도 다르다고 나온다.

## 인터뷰에서 이렇게 나온다

**"LazyInitializationException은 왜 나고, OSIV를 켜는 게 해법이 아닌 이유는?"**

<details markdown="1">
<summary>답 확인</summary>

LAZY 연관에 들어 있는 프록시가 값을 읽으려면 자기를 만든 영속성 컨텍스트가 살아 있어야 하는데, 그게 닫힌 뒤에 접근해서 나는 예외다. OSIV는 컨텍스트를 HTTP 요청이 끝날 때까지 열어두어 예외를 없애지만 DB 커넥션 점유 시간이 뷰 렌더링까지 늘어나므로, 트래픽이 오르면 커넥션 풀 고갈로 되돌아온다. 정석은 fetch join·`@EntityGraph`·DTO 투영으로 필요한 데이터를 트랜잭션 안에서 확정하는 것이다.

</details>

**"엔티티의 equals를 getClass() 비교로 구현하면 어떤 문제가 생기나요?"**

<details markdown="1">
<summary>답 확인</summary>

지연 로딩된 연관은 원본 클래스를 상속한 프록시 인스턴스라 `getClass()`가 원본과 다르다. 같은 식별자의 엔티티인데도 `equals`가 `false`를 반환하게 되므로, `instanceof`를 쓰거나 Hibernate가 제공하는 방식으로 실제 타입을 풀어서 비교해야 한다.

</details>

## 한 줄 요약

> LAZY 연관에 들어 있는 프록시는 "필요할 때 읽어주겠다"는 약속이고 그 약속을 이행할 수 있는 건 영속성 컨텍스트가 살아 있는 동안뿐이라서, 예외가 나는 자리도 OSIV가 그 예외를 없애는 방식도 커넥션을 오래 쥐는 대가도 전부 이 유효기간 하나로 설명된다.
