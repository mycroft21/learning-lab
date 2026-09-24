---
title: "Cascade와 orphanRemoval"
date: 2026-09-25
domain: jpa
slots: 1
parts_done: 1
tags: [jpa, cascade, orphan-removal]
---

## 컬렉션에서 자식을 빼봤을 때 뭐가 나가는지

`cascade = CascadeType.ALL`과 `orphanRemoval = true`를 "둘 다 자식을 같이 지워주는 옵션"으로 알고 쓰는 경우가 많다. 실제로 갈리는 지점은 부모를 지울 때가 아니라 **부모는 그대로 둔 채 자식을 관계에서 빼낼 때**다.

```java
@Transactional
void removeFirstItem(Long orderId) {
    Order order = em.find(Order.class, orderId);
    order.getItems().remove(0);   // 컬렉션에서 빼기만 한다
}
```

`cascade = REMOVE`만 걸려 있으면 이 코드에서 `DELETE`는 나가지 않는다. FK가 `not null`이면 오히려 제약 위반으로 실패한다. `orphanRemoval = true`면 같은 코드에서 `delete from order_item where id=?`가 나간다. 같아 보이던 두 옵션이 여기서 완전히 갈린다.

## 하나는 연산의 전파, 하나는 관계 변화의 감지

- **`cascade`는 내가 받은 생명주기 연산을 자식에게도 전달한다.** 부모에 `persist`가 일어나면 자식에게도 `persist`, 부모에 `remove`가 일어나면 자식에게도 `remove`를 전달한다. 전달할 연산이 부모에게 일어나지 않으면 아무 일도 하지 않는다.
- **`orphanRemoval`은 부모와의 관계가 끊어진 자식을 감지해서 삭제한다.** 연산을 전달받는 게 아니라 컬렉션에서 빠졌다는 **상태 변화**가 방아쇠다.

이 하나로 나머지가 전부 설명된다.

- 컬렉션에서 `remove`만 했을 때 — 부모에겐 아무 연산도 일어나지 않았으니 `cascade`는 침묵하고, 관계는 끊어졌으니 `orphanRemoval`은 삭제한다.
- 부모를 `remove`했을 때 — `cascade = REMOVE`는 연산을 전달해 자식을 지운다. `orphanRemoval = true`도 부모가 사라지면 모든 자식이 고아가 되므로 결과적으로 같이 지운다. **부모를 지우는 경우만 보면 둘이 똑같아 보이는 이유가 이것이다.**
- 자식을 다른 부모의 컬렉션으로 옮겼을 때 — 원래 부모와의 관계가 끊어졌으므로 `orphanRemoval`은 삭제를 시도한다. 옮기려던 의도와 정반대의 결과가 나오는 자리다.

## `ALL`을 기본으로 깔면 안 되는 이유

`CascadeType.ALL`이 위험해지는 건 **자식이 그 부모만의 것이 아닐 때**다. 주문과 주문항목처럼 항목이 그 주문에만 속하는 단일 소유 관계에서는 안전하지만, 여러 주문이 같은 상품이나 같은 회원을 참조하는 관계에 `REMOVE`가 섞이면 주문 하나를 지울 때 공유 중인 상품·회원까지 지우려 든다.

> `cascade`와 `orphanRemoval`은 "이 자식은 이 부모 없이는 존재할 이유가 없다"가 참인 관계에만 건다. 그 문장이 거짓이면 둘 다 걸지 않는 게 맞다.

## DB의 `ON DELETE CASCADE`와는 다른 물건이다

이름이 겹쳐서 같은 걸로 보이지만 동작 주체가 다르다.

- **JPA `cascade`** — 애플리케이션이 자식마다 `DELETE`를 만들어 보낸다. 자식이 1000건이면 `DELETE`도 1000번 나갈 수 있다.
- **DB `ON DELETE CASCADE`** — DB가 알아서 처리한다. 빠르지만 애플리케이션은 무엇이 지워졌는지 모르고, 영속성 컨텍스트에 남아 있는 자식 엔티티는 이미 없는 행을 가리키게 된다.

그리고 JPQL 벌크 삭제(`delete from Order o where ...`)에는 `cascade`가 적용되지 않는다. 영속성 컨텍스트를 거치지 않고 SQL이 바로 나가기 때문이다.

## 인터뷰에서 이렇게 나온다

**"cascade = REMOVE와 orphanRemoval = true의 차이를 설명해보세요."**

<details markdown="1">
<summary>답 확인</summary>

`cascade`는 부모에게 일어난 생명주기 연산을 자식에게 전달하는 것이고, `orphanRemoval`은 부모와의 관계가 끊어진 자식을 감지해 삭제하는 것이다. 그래서 부모를 삭제하는 경우에는 둘 다 자식을 지워 같아 보이지만, 부모를 그대로 둔 채 컬렉션에서 자식만 빼면 `cascade`는 아무 일도 하지 않고 `orphanRemoval`만 `DELETE`를 낸다.

</details>

**"연관에 CascadeType.ALL을 거는 기준이 뭔가요?"**

<details markdown="1">
<summary>답 확인</summary>

자식이 그 부모에게만 종속되는 단일 소유 관계인지로 판단한다. 다른 엔티티도 참조하는 공유 엔티티에 `REMOVE`가 포함된 cascade를 걸면 부모 하나를 지울 때 공유 중인 엔티티까지 삭제를 시도하게 된다.

</details>

## 한 줄 요약

> `cascade`는 부모에게 일어난 연산을 자식에게 전달하는 것이고 `orphanRemoval`은 관계가 끊어진 자식을 감지해 지우는 것이라, 방아쇠가 연산이냐 상태 변화냐만 잡으면 둘이 같아 보이는 경우와 정반대로 갈리는 경우가 모두 설명된다.
