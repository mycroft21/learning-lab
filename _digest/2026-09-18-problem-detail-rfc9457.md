---
title: "ProblemDetail(RFC 9457)로 에러 응답 표준화"
date: 2026-09-18
domain: spring
slots: 1
parts_done: 1
tags: [spring, problemdetail, error-handling]
---

## 프로퍼티 하나 켜면 우리 예외도 다 이 포맷으로 나갈 거라는 착각

`spring.mvc.problemdetails.enabled=true`를 켜고 나서, 서비스 코드에서 던지는 커스텀 예외(`PaymentDeclinedException` 같은)를 그대로 던져보면 어떻게 될까. 확인해보면 여전히 기본 화이트라벨 에러 페이지나 예전 포맷 그대로 나온다. 이 프로퍼티가 자동 변환해주는 건 **Spring MVC가 이미 알고 있는 예외**(`MethodArgumentNotValidException`, `MissingServletRequestParameterException` 등 프레임워크가 던지는 것들)뿐이고, 내 도메인 예외는 대상이 아니다.

## 표준화되는 건 포맷이지 예외 처리 책임이 아니다

이 기능이 표준화하는 건 정확히 **"에러를 어떤 JSON 모양으로 내보낼 것인가"**이지, "누가 그 예외를 잡아서 응답으로 바꿀 것인가"가 아니다. 커스텀 예외는 여전히 `@ExceptionHandler`를 직접 써서 `ProblemDetail`을 만들어 반환해야 한다.

```java
@ExceptionHandler(PaymentDeclinedException.class)
ProblemDetail handle(PaymentDeclinedException ex) {
    ProblemDetail pd = ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY, ex.getMessage());
    pd.setProperty("declineCode", ex.getDeclineCode());
    return pd;
}
```

프레임워크가 대신 해주는 건 "이 형태로 변환하는 법"을 이미 안다는 것뿐이다. `ResponseEntityExceptionHandler`를 상속해서 여러 예외를 한 곳에서 처리하게 만들 수는 있지만, 그 안에 내 예외를 위한 핸들러 메서드를 추가하는 건 여전히 내 몫이다.

## Content-Type이 조용히 바뀐다는 걸 모르면 테스트가 깨진다

`ProblemDetail`을 반환하면 응답의 `Content-Type`이 `application/json`이 아니라 **`application/problem+json`**으로 자동 설정된다. RFC 9457 스펙에 정의된 미디어 타입을 그대로 따르는 것인데, 기존에 `MockMvc`로 `content().contentType(MediaType.APPLICATION_JSON)`을 검증하던 테스트가 있다면 이 전환 이후 그 단언이 깨진다. 프런트엔드/모바일 쪽에서 응답을 `Content-Type` 기준으로 분기하는 코드가 있었다면 그쪽도 같이 확인해야 한다.

## 인터뷰에서 이렇게 나온다

**"spring.mvc.problemdetails.enabled를 켰는데 우리 팀 커스텀 예외는 왜 여전히 예전 포맷으로 나가나요?"**

<details markdown="1">
<summary>답 확인</summary>

이 프로퍼티는 Spring MVC가 이미 알고 있는 프레임워크 예외만 `ProblemDetail`로 자동 변환한다. 도메인 고유의 커스텀 예외는 여전히 `@ExceptionHandler`에서 `ProblemDetail`을 직접 만들어 반환해야 하고, 그래야 응답 `Content-Type`도 `application/problem+json`으로 함께 바뀐다.

</details>

## 한 줄 요약

> `spring.mvc.problemdetails.enabled`가 표준화하는 건 "에러를 어떤 JSON 모양으로 내보낼 것인가"이지 "누가 내 예외를 잡아줄 것인가"가 아니다 — 커스텀 예외는 여전히 `@ExceptionHandler`가 `ProblemDetail`을 반환해야 하고, 그 순간 응답 `Content-Type`도 `application/problem+json`으로 조용히 바뀐다.
