---
title: "URL의 숫자 하나로 남의 주문이 열리는 이유"
date: 2026-10-31
domain: security
slots: 1
parts_done: 1
tags: [security, authorization, idor]
---

## 로그인은 했는데, 그게 이 주문을 봐도 된다는 뜻은 아니다

주문 상세 API가 이렇게 생겼다고 하자.

```java
@GetMapping("/api/orders/{id}")
public OrderResponse getOrder(@PathVariable Long id) {
    Order order = orderRepository.findById(id)
        .orElseThrow(() -> new NotFoundException());
    return OrderResponse.from(order);
}
```

`SecurityFilterChain`에 `/api/orders/**`를 `authenticated()`로 걸어뒀으니 로그인 안 한 요청은 막힌다. 그런데 로그인한 **아무 사용자나** `id`를 1씩 바꿔가며 호출하면 남의 주문 내역이 그대로 열린다. 토큰은 유효하고, 경로도 허용된 경로다. 시스템은 "이 요청을 처리해도 되는가"를 분명히 확인했다 — 다만 **"이 사용자가 이 주문을 봐도 되는가"는 아무도 묻지 않았다.**

## 인증과 인가는 같은 질문이 아니다

`authenticated()`, `hasRole("USER")` 같은 설정이 확인하는 건 **"누구인지"**와 **"이 경로에 들어올 자격이 있는 역할인지"**다. 이건 경로 단위로 끝나는 질문이다. 반면 `/api/orders/{id}`처럼 URL에 리소스의 식별자가 박혀 있는 엔드포인트는 **"이 특정 인스턴스에 대한 권한이 있는가"**라는 다른 질문을 추가로 요구한다. 경로 기반 인가는 이 질문에 답할 방법이 없다 — 애초에 "어느 주문인지"를 모르고 "어느 경로인지"만 보기 때문이다.

> 클라이언트가 보낸 식별자는 "무엇을 원하는지"를 말할 뿐 "그럴 자격이 있는지"는 말하지 않는다. 그 간극을 메우는 코드가 없으면 인증된 사용자 전원이 전체 데이터에 접근할 수 있는 것과 같아진다.

이게 OWASP가 API 취약점 1순위로 꼽는 IDOR(Insecure Direct Object Reference), 더 정확히는 BOLA(Broken Object Level Authorization)다. `authorizeHttpRequests`의 경로 매칭 규칙 자체를 어떻게 구성하는지는 [Spring Security 필터체인 편](/learning-lab/digest/2026-09-15-spring-security-filter-chain-dsl/)에서 다뤘다 — 거기서 다룬 설정이 아무리 정교해도, 그건 "이 경로에 누가 들어올 수 있는가"를 정할 뿐 "이 경로 안의 어떤 객체를 건드려도 되는가"는 정하지 못한다는 게 이 편의 출발점이다.

## 확인은 1분이면 끝난다

계정 두 개를 만들고, 계정 A로 로그인해 자기 주문의 상세 API를 호출한 뒤 응답받은 ID를 계정 B의 토큰으로 다시 호출해본다.

```bash
curl -H "Authorization: Bearer $TOKEN_B" https://api.example.com/api/orders/1042
```

`1042`가 A의 주문인데 B의 토큰으로 조회가 성공하면, 그 엔드포인트는 객체 수준 인가가 빠진 것이다. 조회뿐 아니라 수정·삭제 엔드포인트도 같은 방법으로 확인해야 한다 — 읽기만 막고 쓰기를 빼먹는 경우가 흔하다.

## 고치는 법: 가져온 다음, 반드시 소유권을 비교한다

레포지토리가 리소스를 가져오는 조건 자체에 소유자를 넣거나, 가져온 다음 비교하는 단계를 명시적으로 추가해야 한다.

```java
@GetMapping("/api/orders/{id}")
public OrderResponse getOrder(@PathVariable Long id, @AuthenticationPrincipal User me) {
    Order order = orderRepository.findByIdAndOwnerId(id, me.getId())
        .orElseThrow(() -> new NotFoundException());
    return OrderResponse.from(order);
}
```

`findByIdAndOwnerId`처럼 쿼리 조건에 소유자를 포함시키면, 남의 주문 ID를 넣었을 때 "찾을 수 없음"으로 응답한다 — "권한 없음"이 아니라 "존재하지 않음"으로 답하는 편이 낫다. 이 ID가 존재한다는 사실 자체를 노출하지 않기 때문이다. 관리자처럼 예외적으로 전체를 봐야 하는 역할이 있다면, 소유권 검사를 역할에 따라 분기하는 게 아니라 **그 분기 자체를 서비스 계층 한 곳에 모아** 모든 엔드포인트가 같은 규칙을 통과하게 만들어야 한다. 컨트롤러마다 따로 검사를 끼워 넣으면 하나만 빼먹어도 그 엔드포인트가 구멍이 된다.

## "UUID를 쓰면 안전하다"는 착각

식별자를 순차 정수 대신 UUID로 바꾸면 추측이 어려워지니 안전하다고 생각하기 쉽다. 틀렸다. UUID는 **무작위 대입으로 다른 사용자의 ID를 맞히기 어렵게** 만들 뿐이다. 공격자가 자기 화면에서 받은 응답, 공유 링크, 또는 다른 API 응답에 포함된 UUID를 **그대로** 가져다 쓰는 경우 — 추측이 전혀 필요 없는 경우 — 에는 아무 효과가 없다. 소유권 확인 코드 자체가 없다는 문제는 식별자를 바꿔도 사라지지 않는다.

## 인터뷰에서 이렇게 나온다

**"Spring Security에 authenticated()를 걸어뒀는데 왜 다른 사용자의 데이터가 보이나요?"**

<details markdown="1">
<summary>답 확인</summary>

`authenticated()`는 로그인 여부와 경로 접근 자격만 확인하는 경로 단위 인가다. URL에 리소스 ID가 포함된 엔드포인트는 그 특정 인스턴스에 대한 소유권을 추가로 확인해야 하는데, 필터체인 설정만으로는 이 질문에 답할 수 없다. 리포지토리 조회 조건에 소유자를 포함하거나 조회 후 소유권을 비교하는 코드가 각 엔드포인트에 있어야 한다.

</details>

**"ID를 UUID로 바꾸면 이 문제가 해결되나요?"**

<details markdown="1">
<summary>답 확인</summary>

아니다. UUID는 다른 사용자의 ID를 무작위로 추측하기 어렵게 만들 뿐이고, 소유권을 확인하는 코드 자체가 없다는 근본 문제는 그대로 남는다. 공격자가 추측이 아니라 다른 경로로 유출된 실제 UUID를 입력하면 순차 ID와 똑같이 뚫린다.

</details>

## 한 줄 요약

> 경로 기반 인가는 "이 경로에 들어올 자격이 있는가"만 확인할 뿐 "이 객체를 봐도 되는가"는 확인하지 못하므로, URL에 리소스 식별자가 들어가는 모든 엔드포인트는 조회·수정·삭제마다 소유권을 명시적으로 비교하는 코드가 따로 필요하다.
