---
title: "스코프를 통과했다고 권한이 있는 것은 아니다"
date: 2026-11-21
domain: oidc
slots: 1
parts_done: 1
tags: [oauth2, scope, authorization]
---

## 스코프 검사를 붙였는데 남의 주문이 열린다

리소스 서버에 이런 검사를 붙여뒀다고 하자.

```java
@PreAuthorize("hasAuthority('SCOPE_orders:read')")
@GetMapping("/api/orders/{id}")
public OrderResponse getOrder(@PathVariable Long id) {
    return OrderResponse.from(orderRepository.findById(id).orElseThrow());
}
```

토큰에 `orders:read` 스코프가 있는지 확인하고 있으니 안전해 보인다. 그런데 사용자 A의 토큰으로 사용자 B의 주문 ID를 넣어 호출해도 **그대로 열린다.** 스코프 검사는 통과했는데, 그 토큰이 **어느 주문까지** 읽어도 되는 토큰인지는 아무도 확인하지 않았다.

## 스코프는 행위의 종류를 말할 뿐 소유를 말하지 않는다

스코프가 답하는 질문은 "이 토큰으로 **어떤 종류의 행위**를 할 수 있는가"다. 사용자가 동의 화면에서 "주문 조회 권한을 허용"했다는 건, 그 앱이 **주문 조회라는 카테고리의 API를 호출해도 된다**는 뜻이지, **어떤 주문이든** 조회해도 된다는 뜻이 아니다.

> 스코프는 "이 토큰으로 할 수 있는 행위의 종류"를 말할 뿐 "이 자원이 이 토큰의 주인의 것인가"는 말하지 않는다. 그래서 스코프 검사만 해두면, 같은 종류의 행위를 다른 사람의 자원에 대해 수행하는 것까지 전부 통과시킨다.

이 둘은 완전히 다른 축이다.

- **스코프 검사** — 정적이고 거친 단위다. "이 토큰이 주문 조회 API 자체를 호출할 자격이 있는가"만 본다. 토큰을 디코드하는 것만으로 끝난다.
- **자원 소유권 검사** — 동적이고 구체적인 단위다. "이 토큰의 주체(`sub`)가 **지금 요청한 바로 그** 주문의 소유자인가"를 본다. DB를 조회해 비교해야 한다.

## 이건 처음 보는 함정이 아니다

[IDOR 편](/learning-lab/digest/2026-10-31-idor-object-level-authorization/)에서 본 것과 구조가 똑같다. 그 글에서는 "경로에 들어올 자격"(`authenticated()`, `hasRole`)과 "그 경로 안의 특정 객체에 대한 자격"이 다른 질문이라고 봤다. 여기서는 그 경로 기반 인가가 OAuth 스코프로 한 겹 바뀌었을 뿐, **똑같은 간극**이 그대로 남아 있다. 스코프 검사는 결국 "이 종류의 엔드포인트에 들어올 자격이 있는가"를 묻는 또 다른 형태의 경로 기반 인가이기 때문이다.

그래서 고치는 법도 같다. 스코프 검사를 지우는 게 아니라, **그 위에 소유권 검사를 반드시 더한다.**

```java
@PreAuthorize("hasAuthority('SCOPE_orders:read')")
@GetMapping("/api/orders/{id}")
public OrderResponse getOrder(@PathVariable Long id, @AuthenticationPrincipal Jwt jwt) {
    String subject = jwt.getSubject();
    Order order = orderRepository.findByIdAndOwnerId(id, subject)
        .orElseThrow(() -> new NotFoundException());
    return OrderResponse.from(order);
}
```

스코프 검사는 "이 요청이 이 종류의 API를 칠 자격이 있는가"를 걸러내는 1차 관문이고, 그다음에 **그 요청이 가리키는 구체적인 자원이 토큰의 주체 것인지**를 확인하는 2차 관문이 따로 있어야 한다. 하나가 다른 하나를 대신하지 못한다.

## 세밀한 스코프 이름도 보장이 되진 않는다

`orders:read:own`처럼 스코프 이름 자체에 "본인 것만"이라는 의미를 넣어두는 경우도 있다. 그런데 이건 **사람이 읽는 이름일 뿐**, 인가 서버가 "이 토큰은 정확히 이 주문에만 쓸 수 있다"는 걸 기술적으로 강제하는 것과는 다르다. 특정 자원 단위로 권한을 묶어 발급하는 확장(RFC 9396, Rich Authorization Requests) 같은 걸 쓰지 않는 한, 스코프 이름이 아무리 세밀해도 리소스 서버 쪽의 소유권 비교는 여전히 필요하다.

## 인터뷰에서 이렇게 나온다

**"OAuth 스코프 검사만으로 접근 제어를 다 했다고 볼 수 있나요?"**

<details markdown="1">
<summary>답 확인</summary>

아니다. 스코프는 토큰이 어떤 종류의 행위를 할 수 있는지를 정의할 뿐, 요청이 가리키는 구체적인 자원이 그 토큰의 주체 소유인지는 확인하지 않는다. 스코프 검사를 통과한 뒤에도 요청한 자원의 소유자와 토큰의 `sub`를 직접 비교하는 코드가 따로 있어야 다른 사용자의 자원에 접근하는 것을 막을 수 있다.

</details>

**"이게 IDOR과 같은 문제인가요?"**

<details markdown="1">
<summary>답 확인</summary>

같은 구조의 문제다. IDOR은 경로 기반 인가가 "이 경로에 들어올 자격"만 확인하고 "이 객체를 봐도 되는가"는 확인하지 못해서 생기는데, 스코프 검사도 "이 종류의 API를 호출할 자격"만 확인하고 구체적인 자원에 대한 소유권은 확인하지 못한다는 점에서 동일한 간극을 가진다. OAuth 계층으로 올라갔을 뿐 해법도 똑같이 명시적인 소유권 비교다.

</details>

## 한 줄 요약

> 스코프는 "이 토큰으로 할 수 있는 행위의 종류"를 말할 뿐 "이 자원이 그의 것인가"는 말하지 않으므로, 스코프 검사를 통과한 요청에도 요청이 가리키는 구체적인 자원의 소유권을 별도로 비교하는 검사가 반드시 더해져야 한다.
