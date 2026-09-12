---
title: "AOP 프록시 메커니즘과 self-invocation 함정"
date: 2026-09-11
domain: spring
slots: 2
parts_done: 1
tags: [spring, aop, proxy]
---

## 동료가 @Transactional 걸어놓고도 왜 안먹었냐고 물어봤을 때

신규 입사자가 서비스 클래스 안에서 `save()`가 같은 클래스의 `internalSave()`를 `this.internalSave()`로 호출했는데, 거기 붙인 `@Transactional`이 전혀 동작하지 않았다며 버그 리포트를 올렸다. 원인은 코드 오타가 아니라 **AOP 프록시의 구조적 한계**다.

자문자답: "프록시가 다 처리해주는 거 아니었어?" → 프록시는 **외부에서 들어오는 호출**만 가로챌 수 있다. 객체 내부에서 `this`로 자기 자신을 부르면 프록시를 거치지 않고 원본 메서드가 그대로 실행된다.

## Spring AOP는 프록시 기반이지 바이트코드 위빙이 아니다

Spring AOP는 기본적으로 **런타임 프록시** 방식이다. 대상 빈을 감싸는 프록시 객체를 만들어 빈 등록 시점에 원본 대신 컨테이너에 등록한다. AspectJ처럼 컴파일/로드 타임에 바이트코드 자체를 조작하는 위빙 방식과는 다르다.

| 구분 | 생성 조건 | self-invocation 영향 |
| --- | --- | --- |
| JDK 동적 프록시 | 대상이 인터페이스 구현 | 영향 받음 |
| CGLIB 프록시 | 인터페이스 없거나 proxyTargetClass=true | 영향 받음 |
| AspectJ 위빙 | 컴파일/로드타임 바이트코드 조작 | 영향 없음 |

Spring Boot는 2.x부터 `spring.aop.proxy-target-class` 기본값을 `true`로 바꿔서, 인터페이스가 있어도 기본적으로 **CGLIB**(서브클래스 상속 방식) 프록시를 만든다는 점도 인터뷰에서 자주 나온다.

## self-invocation이 실제로 깨뜨리는 기능들

- `@Transactional` - 내부 호출 시 트랜잭션 시작/커밋 안 됨
- `@Cacheable`/`@CacheEvict` - 캐시 저장/무효화 스킵됨
- `@Async` - 별도 쓰레드 실행 안 되고 동기 실행됨
- `@Retryable` - 재시도 로직 미적용

> 프록시가 걸린 애노테이션은 "메서드를 어떻게 호출했는가"에 따라 동작 여부가 갈린다 — 같은 클래스 안이면 무조건 의심하라.

## 그럼 어떻게 피하나

<details markdown="1">
<summary>흔한 해결책들과 트레이드오프</summary>

가장 널리 쓰이는 방법은 자기 자신을 `ApplicationContext`나 `@Lazy` 자기 참조 필드 주입으로 프록시 참조를 얻어 호출하는 것이다. 더 근본적인 방법은 내부 호출용 로직을 별도 빈(클래스)으로 분리해 외부에서 프록시를 거쳐 호출하도록 구조를 바꾸는 것이다. AspectJ 컴파일 타임 위빙을 쓰면 self-invocation 문제 자체가 사라지지만, 빌드 복잡도가 올라간다.
</details>

## 인터뷰 단골 질문

1. "@Transactional이 안 먹는 이유가 뭘 수 있나요?" → self-invocation으로 프록시를 우회했을 가능성을 먼저 의심한다고 답한다
2. "JDK 동적 프록시와 CGLIB의 차이는?" → 인터페이스 기반이냐 서브클래싱이냐, 그리고 Boot는 기본이 CGLIB라는 점을 짚는다

## 한 줄 요약

> Spring AOP는 프록시를 거쳐야만 동작하므로, 같은 클래스 안에서 this로 호출하면 @Transactional/@Cacheable/@Async 같은 애노테이션이 조용히 무시된다.
