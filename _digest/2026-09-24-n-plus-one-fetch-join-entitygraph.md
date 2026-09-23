---
title: "N+1 문제의 근본 원인과 fetch join / @EntityGraph"
date: 2026-09-24
domain: jpa
slots: 1
parts_done: 1
tags: [jpa, n-plus-one, fetch-join]
---

## `EAGER`로 바꿔서 N+1을 고쳤다고 생각했다면

N+1이 나길래 연관을 `FetchType.EAGER`로 바꿨더니 사라지더라는 경험은 꽤 흔하다. 그런데 그건 `em.find()`로 조회하는 경로에서만 벌어진 일이다. 같은 연관을 JPQL로 조회하면서 SQL 로그를 보면 정반대가 나온다.

```java
List<Order> orders = em.createQuery("select o from Order o", Order.class).getResultList();
```

```sql
select ... from orders          -- 1번
select ... from member where id=?   -- 주문 개수만큼
select ... from member where id=?
...
```

JPQL은 적힌 그대로 SQL로 번역된다. 조인하라고 쓰지 않았으니 조인이 없고, `EAGER`라서 "지금 당장 채워야 한다"는 요구만 남으니 행마다 추가 `SELECT`가 나간다. **`EAGER`는 N+1을 막기는커녕 JPQL 경로에서는 N+1을 확정 짓는다.** 게다가 그 연관을 쓰지 않는 쿼리에서도 똑같이 나간다.

## 문제는 로딩 전략이 아니라 결정 주체다

N+1의 원인을 "LAZY라서"로 정리하면 `EAGER`가 해법처럼 보인다. 정확한 원인은 다른 데 있다 — **이 쿼리가 무엇까지 같이 읽을지를 쿼리가 아니라 매핑이 정하고 있다**는 것이다. LAZY든 EAGER든 매핑에 박아둔 결정은 모든 쿼리에 일괄 적용되는데, 정작 필요한 연관은 쿼리마다 다르다.

- `LAZY` + 연관 접근 → 접근 시점마다 1건씩 읽으므로 N번.
- `EAGER` + JPQL → 조인 없이 행마다 채우므로 역시 N번. 심지어 안 쓰는 경우에도.

그래서 해결책은 전부 한 방향이다. **결정을 매핑에서 쿼리로 가져온다.**

```java
// fetch join — 이 쿼리는 member까지 같이 읽는다고 쿼리가 선언한다
select o from Order o join fetch o.member
```

```java
// @EntityGraph — 같은 선언을 메서드 단위로
@EntityGraph(attributePaths = "member")
List<Order> findAll();
```

연관 매핑은 `LAZY`로 두고(기본값을 지키고), 필요한 쿼리에서만 함께 읽겠다고 지정하는 형태가 정석으로 통하는 이유가 이것이다.

## 배치 사이즈는 횟수를 줄이는 다른 축이다

`fetch join`이 "한 번에 조인해서 읽기"라면, 배치 사이즈는 **여전히 나중에 읽되 한 건씩이 아니라 묶어서 읽기**다.

```yaml
spring.jpa.properties.hibernate.default_batch_fetch_size: 100
```

이렇게 두면 지연 로딩이 걸릴 때 식별자를 모아 `where id in (?, ?, ...)` 한 방으로 읽는다. 100건짜리 목록의 N+1이 1+1이 되는 식이다. 쿼리를 고치지 않고 설정 한 줄로 전역 개선이 되기 때문에 실무에서는 이걸 기본으로 깔고, 특정 쿼리만 `fetch join`으로 마저 잡는 조합이 흔하다.

## 컬렉션에서 이 방법이 깨지는 경계

`fetch join`은 대상이 컬렉션(`@OneToMany`, `@ManyToMany`)일 때 두 군데서 깨진다. 단일 연관(`@ManyToOne`, `@OneToOne`)은 행이 늘어나지 않으므로 해당되지 않는다.

- **페이징과 같이 쓸 수 없다.** 컬렉션을 조인하면 행이 곱해져서 DB의 `LIMIT`을 걸 수가 없다. Hibernate는 포기하지 않고 **전부 읽어서 메모리에서 잘라낸다.** 로그에 `HHH90003004: firstResult/maxResults specified with collection fetch; applying in memory` 가 찍히면 그 상황이다. 상품 1만 건에 리뷰 10개씩이면 10만 행이 힙으로 올라온 뒤 한 페이지만 남는다.
- **컬렉션을 둘 이상 fetch join하면 `MultipleBagFetchException`이 난다.** 중복을 구분할 수 없는 `List`(bag) 둘을 동시에 조인할 수 없기 때문이고, `Set`으로 바꾸거나 하나만 조인하고 나머지는 배치 사이즈에 맡기면 피할 수 있다.

> 페이징이 필요한 목록에서는 컬렉션 `fetch join`을 쓰지 않는다 — 페이징은 컬렉션 없이 하고, 컬렉션은 배치 사이즈로 묶어 읽는 쪽이 메모리를 지킨다.

## 인터뷰에서 이렇게 나온다

**"N+1을 FetchType.EAGER로 해결할 수 있나요?"**

<details markdown="1">
<summary>답 확인</summary>

없다. `em.find()` 경로에서는 조인으로 읽지만 JPQL은 적힌 대로 SQL이 되므로 조인이 없고, 행마다 연관을 채우는 추가 `SELECT`가 나가 오히려 N+1이 확정된다. 그 연관을 쓰지 않는 쿼리에서도 똑같이 읽는 부작용까지 있다. 매핑은 `LAZY`로 두고 `fetch join`이나 `@EntityGraph`로 쿼리별로 지정하는 것이 해법이다.

</details>

**"컬렉션 fetch join에 페이징을 걸면 어떻게 되나요?"**

<details markdown="1">
<summary>답 확인</summary>

컬렉션 조인은 행을 곱하므로 DB에서 `LIMIT`을 적용할 수 없고, Hibernate는 전체 결과를 읽어 메모리에서 잘라낸다(`HHH90003004` 경고). 데이터가 커지면 그대로 힙 압박이 되므로, 페이징 쿼리에서는 컬렉션을 조인하지 말고 `default_batch_fetch_size`로 묶어 읽어야 한다.

</details>

## 한 줄 요약

> N+1은 "이 쿼리가 무엇까지 같이 읽을지"를 쿼리가 아니라 매핑이 정해서 생기는 문제이고, `fetch join`·`@EntityGraph`·배치 사이즈는 전부 그 결정을 쿼리 쪽으로 가져오는 방법인 반면 `EAGER`는 결정을 매핑에 더 단단히 묶기 때문에 JPQL에서는 오히려 N+1을 보장한다.
