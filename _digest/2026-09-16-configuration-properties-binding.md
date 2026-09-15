---
title: "@ConfigurationProperties와 설정 바인딩 계약"
date: 2026-09-16
domain: spring
slots: 1
parts_done: 1
tags: [spring, configuration-properties, boot]
---

## record에 기본값을 넣으려다 막힌 적이 있다면

`@ConfigurationProperties`를 record로 선언하면서 `int timeoutSeconds = 30`처럼 필드에 기본값을 주려고 해본 적이 있을 것이다. 컴파일부터 안 된다 — 자바 record는 애초에 필드 기본값이라는 문법을 지원하지 않는다. 그럼 이 프로퍼티가 설정 파일에 없을 때 `timeoutSeconds`는 뭐가 되는가? 직접 찍어보면 답이 나온다. 아무 처리도 안 해두면 `0`(int의 자바 기본값)이 아니라, 그 필드가 바인딩 대상에서 아예 빠졌다는 뜻의 **바인딩 실패 혹은 null**이다.

## 값이 없을 때 무엇이 채워지는가, 이 질문 하나로 설계가 갈린다

`@ConfigurationProperties`를 쓸 때 진짜 결정해야 하는 건 "타입을 뭘로 할까"가 아니라 **프로퍼티가 없을 때 무엇이 채워지는가**다. 여기엔 자동으로 생기는 기본값이란 게 없다 — 명시하지 않으면 `null`이고, 명시하려면 `@DefaultValue`를 constructor 파라미터에 직접 붙여야 한다.

```java
@ConfigurationProperties(prefix = "payment.gateway")
@Validated
public record GatewayProperties(
    @NotBlank String baseUrl,
    @DefaultValue("30") @Min(1) int timeoutSeconds
) {}
```

`@DefaultValue("30")`이 있는 `timeoutSeconds`는 프로퍼티가 없으면 문자열 `"30"`을 타입 변환기가 `int`로 바꿔서 채운다. `@DefaultValue`가 없는 필드는 프로퍼티가 없으면 그냥 `null`(참조 타입) 또는 바인딩 자체가 실패한다. `@Value("${payment.gateway.timeout:30}")`에 익숙한 사람이 `@ConfigurationProperties`로 넘어오면서 `:30` 같은 인라인 기본값 문법이 통할 거라 기대하는 게 가장 흔한 착각이다 — 그런 문법은 여기 없다.

## 중첩 레코드는 한 단계 더 깊이 함정이 있다

```java
public record GatewayProperties(
    String baseUrl,
    RetryPolicy retry
) {
    public record RetryPolicy(@DefaultValue("3") int maxAttempts, Duration backoff) {}
}
```

`payment.gateway.retry.*` 아래 프로퍼티가 **하나도 없으면** `retry` 필드 자체가 `null`이 된다. `retry.max-attempts`만 설정하고 `retry.backoff`는 안 줬다면, 그 경우엔 `retry` 객체는 만들어지고 `maxAttempts`는 `@DefaultValue`대로 채워지지만 `backoff`는 `null`이다. 즉 **"중첩 객체가 아예 없는 것"과 "중첩 객체는 있는데 그 안의 값이 없는 것"이 다르게 처리된다** — 후자만 `@DefaultValue`가 개입한다. 널 체크를 `retry == null`로만 하고 `retry.backoff() == null`을 안 보면, 그 사이 어딘가에서 `NullPointerException`이 난다.

## 표기가 달라도 같은 필드로 묶이는 조건

relaxed binding 덕분에 아래 세 표기는 전부 `timeoutSeconds` 하나로 모인다.

- 프로퍼티 파일: `payment.gateway.timeout-seconds`(kebab-case)
- 환경변수: `PAYMENT_GATEWAY_TIMEOUTSECONDS`(대문자 스네이크, 언더스코어 없이 이어붙임)
- 시스템 프로퍼티: `payment.gateway.timeoutSeconds`(camelCase)

이 변환은 프로퍼티 파일과 커맨드라인/시스템 프로퍼티에서는 관대하게 동작하지만, **환경변수는 대소문자와 구분자 규칙이 더 엄격**하다. 여러 단어로 된 필드명을 환경변수로 넘길 때 언더스코어 위치를 착각해서 바인딩이 안 되는 경우가 실무에서 흔하다 — 안 될 때는 필드명을 그대로 대문자+언더스코어로 바꾼 형태(`TIMEOUT_SECONDS`가 아니라 단어 하나로 취급된 `TIMEOUTSECONDS`)인지부터 확인한다.

## 검증은 채워진 결과에 대해 기동 시점 한 번뿐이다

`@Validated`를 얹으면 `@NotBlank`, `@Min` 같은 제약이 걸리는데, 이건 **`@DefaultValue`까지 다 적용되고 난 최종 값**에 대해 기동 시점에 딱 한 번 평가된다. 즉 필수값이 비어 있으면 이 시점에 애플리케이션이 뜨지 않고 어떤 필드가 위반됐는지 메시지로 나온다. `@Value` 방식에는 이 시점 자체가 없어서, 빈 값이 서비스 로직 깊숙한 곳까지 흘러들어가서야 문제가 드러난다는 차이가 여기서 나온다.

## 인터뷰에서 이렇게 나온다

**"record로 만든 @ConfigurationProperties에서 기본값은 어떻게 주나요?"**

<details markdown="1">
<summary>답 확인</summary>

record는 필드 기본값 문법이 없으므로 생성자 파라미터에 `@DefaultValue("값")`을 붙인다. 프로퍼티가 없으면 이 문자열이 타입 변환기를 거쳐 채워지고, 붙이지 않은 필드는 프로퍼티가 없을 때 `null`이 된다.

</details>

## 한 줄 요약

> `@ConfigurationProperties`에서 진짜 설계 포인트는 타입 선택이 아니라 프로퍼티가 없을 때 무엇이 채워지는가다 — record는 기본값이 자동으로 생기지 않고 `@DefaultValue`로 명시한 것만 채워지며, 중첩 객체는 "아예 없음"과 "안의 값만 없음"이 다르게 처리된다.
