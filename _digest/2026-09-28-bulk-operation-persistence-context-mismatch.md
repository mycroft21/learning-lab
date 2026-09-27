---
title: "벌크 연산과 영속성 컨텍스트 불일치"
date: 2026-09-28
domain: jpa
slots: 1
parts_done: 1
tags: [jpa, bulk-operation, persistence-context]
---

## 방금 바꾼 값을 바로 읽었는데 옛날 값이 나온다

재고를 일괄로 0으로 만드는 벌크 쿼리를 실행하고, 같은 트랜잭션에서 그 상품을 조회해보면 이런 일이 벌어진다.

```java
@Transactional
void closeOut(Long productId) {
    em.createQuery("update Product p set p.stock = 0 where p.id = :id")
      .setParameter("id", productId)
      .executeUpdate();

    Product p = em.find(Product.class, productId);
    System.out.println(p.getStock());   // 0이 아니라 바꾸기 전 값
}
```

로그를 보면 더 이상하다. `find` 자리에서 `SELECT`조차 나가지 않는다. DB에는 분명 `0`이 들어갔는데, 애플리케이션은 그걸 읽으러 가지도 않고 예전 값을 답으로 내놓는다.

## 벌크 연산은 영속성 컨텍스트를 건너뛴다

일반적인 쓰기 경로는 엔티티를 영속성 컨텍스트에 올려두고 변경 감지로 SQL을 만들어 내보낸다. 벌크 연산(JPQL `update`/`delete`)은 그 경로를 타지 않는다. **작성한 쿼리가 곧바로 SQL이 되어 DB로 간다.** 영속성 컨텍스트는 그런 일이 있었는지조차 모른다.

그래서 벌크 연산이 실행되는 순간, 컨텍스트가 들고 있던 엔티티들은 전부 **과거의 스냅샷**이 된다. 위 코드에서 `find`가 `SELECT`를 보내지 않은 건 1차 캐시에 이미 그 식별자의 인스턴스가 있었기 때문이고, 1차 캐시는 자기가 낡았다는 사실을 알 방법이 없다. 같은 식별자면 같은 인스턴스를 돌려주는 보장이 1차 캐시의 본질이라는 점은 [영속성 컨텍스트와 1차 캐시 편](/learning-lab/digest/2026-09-21-persistence-context-first-level-cache/)에서 다뤘다.

## 같은 이유로 함께 동작하지 않는 것들

영속성 컨텍스트를 거치지 않는다는 성질 하나로, 평소 당연하게 기대하던 기능들이 한꺼번에 빠진다.

- **변경 감지** — 벌크로 바꾼 값은 스냅샷 비교를 거친 적이 없다. 반대로 벌크 실행 전에 엔티티를 수정해뒀다면, 그 변경은 아직 컨텍스트 안에만 있다.
- **`cascade`와 `orphanRemoval`** — 연산 전파도 고아 감지도 컨텍스트가 하는 일이라 벌크 `delete`에는 적용되지 않는다. 자식 행이 그대로 남아 FK 제약에 걸릴 수 있다. 각 기능 자체의 동작은 [Cascade와 orphanRemoval 편](/learning-lab/digest/2026-09-25-cascade-orphan-removal/)에서 다뤘다.
- **`@Version`** — 낙관적 락의 버전 증가도 자동으로 일어나지 않는다. 버전 컬럼을 쿼리에서 직접 올리지 않으면 다른 트랜잭션이 충돌을 감지할 근거가 사라진다.

## `@Modifying`의 두 옵션은 앞뒤를 각각 막는다

Spring Data JPA에서 벌크 연산 메서드에 `@Modifying`을 붙이는 건 알려져 있지만, 같이 주는 두 옵션이 서로 다른 방향의 사고를 막는다는 건 덜 알려져 있다.

```java
@Modifying(flushAutomatically = true, clearAutomatically = true)
@Query("update Product p set p.stock = 0 where p.category = :category")
int closeOutCategory(@Param("category") String category);
```

- **`flushAutomatically`는 앞을 막는다.** 컨텍스트에 쌓여 있던 변경을 벌크 실행 **전에** 먼저 내보낸다. 이게 없으면 아직 안 나간 변경 감지 `UPDATE`가 벌크 뒤에 실행되면서 방금 벌크로 바꾼 값을 덮어쓸 수 있다.
- **`clearAutomatically`는 뒤를 막는다.** 벌크 실행 **후에** 컨텍스트를 비워서, 이후 조회가 1차 캐시가 아니라 DB를 보게 만든다. 맨 위에서 본 "옛날 값" 문제가 이걸로 사라진다.

> 둘 다 기본값이 `false`다. 벌크 연산을 쓰면서 아무 옵션도 주지 않았다면 두 방향 모두 열려 있는 상태다.

직접 `EntityManager`를 다루는 코드라면 같은 일을 `em.flush()`와 `em.clear()`로 손수 해주면 된다. 다만 `clear()`는 컨텍스트 전체를 비우므로, 그 시점에 들고 있던 다른 엔티티들도 전부 준영속이 된다는 점은 감안해야 한다.

## 인터뷰에서 이렇게 나온다

**"벌크 업데이트 직후 같은 트랜잭션에서 조회하면 왜 예전 값이 나오나요?"**

<details markdown="1">
<summary>답 확인</summary>

벌크 연산은 영속성 컨텍스트를 거치지 않고 SQL이 바로 DB로 나가기 때문에, 컨텍스트가 들고 있던 엔티티는 갱신 사실을 모른 채 남는다. 이후 같은 식별자로 조회하면 1차 캐시가 먼저 응답하므로 DB를 읽지도 않고 예전 값이 나온다. `clearAutomatically`나 `em.clear()`로 컨텍스트를 비워야 이후 조회가 DB를 본다.

</details>

**"벌크 삭제에 cascade가 동작하지 않는 이유는?"**

<details markdown="1">
<summary>답 확인</summary>

`cascade`는 영속성 컨텍스트가 생명주기 연산을 자식에게 전파하면서 동작하는데, 벌크 `delete`는 그 경로를 타지 않고 SQL이 직접 실행된다. 자식 행은 그대로 남아 FK 제약 위반으로 이어질 수 있으므로, 자식을 먼저 지우거나 DB 레벨의 `ON DELETE CASCADE`를 쓰는 식으로 따로 처리해야 한다.

</details>

## 한 줄 요약

> 벌크 연산은 영속성 컨텍스트를 건너뛰고 DB로 직행하므로 실행되는 순간 메모리의 엔티티는 전부 과거가 되고, 변경 감지·`cascade`·`@Version`이 함께 빠지는 것도 조회가 옛날 값을 내놓는 것도 전부 이 한 가지에서 나온다.
