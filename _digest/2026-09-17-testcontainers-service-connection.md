---
title: "Testcontainers @ServiceConnection과 통합 테스트 환경 결선"
date: 2026-09-17
domain: spring
slots: 1
parts_done: 1
tags: [spring, testcontainers, testing]
---

## `@Value("${spring.datasource.url}")`가 여전히 비어 있다면

`@ServiceConnection`으로 컨테이너를 붙였는데, 코드 어딘가에서 `@Value("${spring.datasource.url}")`로 그 URL을 직접 읽으려는 부분이 있다면 십중팔구 `null`이 나온다. `DataSource` 빈 자체는 멀쩡히 컨테이너에 연결돼 동작하는데도 그렇다. 원인은 `@ServiceConnection`이 애초에 이 프로퍼티를 채워주는 기능이 아니기 때문이다.

## `@ServiceConnection`은 프로퍼티가 아니라 그보다 우선순위 높은 빈을 만든다

Spring Boot 3.1부터 데이터소스·Redis·Kafka 등의 자동 구성은 `spring.datasource.url` 같은 프로퍼티를 직접 읽는 대신, 먼저 **`ConnectionDetails` 타입의 빈이 있는지 찾고 있으면 그걸 우선 사용**하도록 바뀌었다. `@ServiceConnection`이 하는 일이 정확히 이 `ConnectionDetails` 빈을 컨테이너로부터 만들어서 등록하는 것이다.

```java
@Container
@ServiceConnection
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16");
```

이 코드는 `spring.datasource.url`이라는 프로퍼티 키를 전혀 몰라도 동작한다. `JdbcConnectionDetails` 빈을 직접 등록해버리기 때문에, `DataSource` 자동 구성은 프로퍼티를 볼 필요 자체가 없어진다. 반대로 말하면, **프로퍼티 파일 기반으로 값을 읽는 코드(`@Value`, `Environment.getProperty`)는 이 메커니즘의 영향권 밖**에 있다는 뜻이다. 연결 정보가 필요한 코드는 프로퍼티가 아니라 `ConnectionDetails` 빈(또는 그걸 사용하는 자동 구성이 만든 `DataSource` 등의 빈)에서 가져와야 한다.

## 컨테이너 타입은 어떻게 판별되는가

- **전용 컨테이너 클래스**(`PostgreSQLContainer`, `KafkaContainer` 등)를 쓰면 그 클래스 자체가 타입 판별의 근거가 되고, 어떤 `ConnectionDetails` 팩토리를 쓸지 자동으로 정해진다.
- **`GenericContainer`**를 쓰면 클래스만으로는 판별이 안 되므로, `@ServiceConnection`의 `name` 속성을 명시하거나(`@ServiceConnection(name = "redis")`) 아무것도 안 주면 이미지 이름의 repository 부분(`redis:7`이면 `redis`)을 기준으로 판별한다.
- 둘 다 실패하면(이름도 안 맞고 팩토리도 없으면) `ConnectionDetails` 빈 자체가 안 만들어지고, 결국 프로퍼티 기반 예전 방식(`@DynamicPropertySource`)으로 되돌아가야 한다.

## 인터뷰에서 이렇게 나온다

**"@ServiceConnection을 붙였는데 @Value로 커넥션 URL을 못 읽는 이유는?"**

<details markdown="1">
<summary>답 확인</summary>

`@ServiceConnection`은 `spring.datasource.url` 같은 프로퍼티를 채우는 게 아니라, 그 프로퍼티보다 우선순위가 높은 `ConnectionDetails` 빈을 직접 등록한다. `DataSource` 자동 구성은 이 빈을 먼저 찾아 쓰므로 프로퍼티 없이도 연결되지만, 프로퍼티를 직접 읽는 코드는 애초에 이 메커니즘의 대상이 아니므로 여전히 비어 있다.

</details>

## 한 줄 요약

> `@ServiceConnection`은 컨테이너의 연결 정보를 프로퍼티가 아니라 `ConnectionDetails` 빈으로 등록하고, 이 빈이 있으면 자동 구성이 프로퍼티보다 그걸 우선한다 — 그래서 프로퍼티를 직접 읽는 코드에는 이 메커니즘이 아무 영향을 주지 않는다.
