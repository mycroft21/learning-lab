---
title: "Spring AOT와 GraalVM 네이티브 이미지"
date: 2026-09-14
domain: spring
slots: 1
parts_done: 1
tags: [spring, aot, graalvm, native-image]
---

## 네이티브 이미지를 만들지 않아도 같은 사고가 난다

AOT를 "시작 시간을 줄여주는 빌드 최적화" 정도로 알고 있을 텐데, 그 설명에는 가장 중요한 게 빠져 있다. 스테이징에 `SPRING_PROFILES_ACTIVE=staging`을 주고 띄웠는데 개발용 빈이 그대로 올라와 있는 상황을 만나면 그때 알게 된다.

확인은 `native-image` 툴체인 없이 1분이면 된다. AOT 모드는 JVM에서도 켤 수 있다.

```bash
./mvnw -Pnative spring-boot:process-aot package
java -Dspring.aot.enabled=true -jar target/app.jar --spring.profiles.active=staging
```

프로필을 뭘로 주든 올라오는 빈 목록이 바뀌지 않는다. 설정을 잘못 읽은 게 아니라, 그 결정이 이미 끝나 있는 것이다.

## 빌드가 컨텍스트를 한 번 조립해본다

AOT는 빌드 시점에 애플리케이션 컨텍스트를 실제로 한 번 조립하고, 그 결과를 자바 소스 코드로 뱉는다. 산출물을 직접 열어보면 논쟁이 끝난다.

```
target/spring-aot/main/sources/com/example/AppApplication__ApplicationContextInitializer.java
target/spring-aot/main/sources/com/example/AppConfiguration__BeanDefinitions.java
```

생성된 초기화 코드에는 `@Conditional`을 판정하는 분기가 없다. 등록될 빈이 그냥 순서대로 나열돼 있을 뿐이다. 조건문이 최적화로 사라진 게 아니라, **빌드할 때 이미 계산돼서 답만 남은** 것이다.

> AOT는 빌드할 때 컨텍스트를 한 번 조립해보고 그 결과를 코드로 굳힌다. 그래서 어떤 빈이 존재하는지는 빌드 시점에 정해지고, 런타임에는 그 결정을 바꿀 수 없다.

## 나머지는 전부 이 한 문장에서 나온다

리플렉션 힌트가 왜 필요한지도 같은 이유다. GraalVM의 closed-world 가정을 따로 외울 필요가 없다 — 빌드할 때 조립해보면서 **본 것만** 등록되고, 못 본 것은 런타임에 존재하지 않는다. Jackson이 문자열로 클래스 이름을 받아 로드하는 경로처럼 코드를 훑어서는 안 보이는 자리가 정확히 `reflect-config.json`에 안 올라가는 자리고, 그래서 `@RegisterReflectionForBinding`이나 `RuntimeHints`로 손으로 알려줘야 한다.

CGLIB 프록시도 마찬가지다. 런타임에 서브클래스를 만들어낼 수 없으니 빌드 시점에 미리 생성해야 하고, 그래서 `@Configuration`의 기본값인 `proxyBeanMethods = true`는 네이티브에서 비용이 된다. 설정 클래스 안에서 `@Bean` 메서드를 서로 호출하지 않는다면 `@Configuration(proxyBeanMethods = false)`로 프록시 생성 자체를 없애는 편이 낫다. 프록시가 무엇을 대신하고 있는지는 [AOP 프록시 편](/learning-lab/digest/2026-09-11-aop-proxy-self-invocation/)에서 다뤘으므로, 여기서는 그게 빌드 산출물로 옮겨간다는 것만 알면 된다.

## 굳는 것과 안 굳는 것의 경계

"AOT를 켜면 설정이 안 먹는다"는 말은 틀렸다. 굳는 것은 **빈의 존재 여부**지 빈이 읽는 값이 아니다. 이 구분이 실무에서 갈리는 자리다.

| 무엇 | 언제 결정되나 | 런타임에 바꿀 수 있나 |
| --- | --- | --- |
| `@ConditionalOnClass` | 빌드 | 못 바꾼다 (클래스패스가 고정이라 애초에 같은 답) |
| `@ConditionalOnProperty`, `@Profile` | 빌드 | **못 바꾼다 — 여기가 사고 지점** |
| `@Value`, `@ConfigurationProperties` | 런타임 | 바꿀 수 있다 |

`@ConditionalOnClass`는 빌드와 런타임의 답이 어차피 같아서 안전하다. 문제는 `@ConditionalOnProperty`처럼 **환경마다 답이 달라지라고 만든** 조건이다. 그래서 처방은 하나로 정리된다 — 환경에 따라 달라져야 하는 건 빈을 만들고 말고로 가르지 말고, 빈은 항상 만들되 그 안에서 값으로 분기시킨다. 프로필을 꼭 써야 한다면 빌드할 때 선택해야 하므로, 프로필 수만큼 아티팩트를 따로 빌드하게 된다.

## 인터뷰에서 이렇게 나온다

**"AOT를 적용했더니 특정 환경에서만 빈이 안 올라옵니다. 어디부터 보겠습니까?"**

<details markdown="1">
<summary>답 확인</summary>

빌드 타임에 조건이 이미 평가됐다는 것부터 짚는다. `@ConditionalOnProperty`나 `@Profile`로 갈리는 빈이라면 런타임 환경변수로는 되돌릴 수 없고, 빌드 시점에 어떤 값으로 처리됐는지를 `target/spring-aot/main/sources/`의 생성 코드에서 확인해야 한다고 답한다. 재현은 네이티브 이미지를 만들 필요 없이 `-Dspring.aot.enabled=true`로 JVM에서 바로 된다는 점까지 말하면 좋다.
</details>

**"네이티브 이미지에서 리플렉션이 왜 문제가 되나요?"**

<details markdown="1">
<summary>답 확인</summary>

빌드 시점에 도달 가능한 코드만 이미지에 포함되기 때문에, 문자열로 클래스를 찾는 경로는 빌드가 볼 수 없어 이미지에서 아예 빠진다고 설명한다. 스프링 AOT가 자기가 관리하는 빈에 대해서는 힌트를 자동 생성해주지만, 애플리케이션이나 미지원 라이브러리가 직접 쓰는 리플렉션은 `RuntimeHints`로 등록해야 한다는 것까지 덧붙인다.
</details>

**"`proxyBeanMethods = false`는 왜 권장되나요?"**

<details markdown="1">
<summary>답 확인</summary>

`@Configuration` 클래스의 CGLIB 서브클래스 프록시를 없애기 위해서다. 프록시는 `@Bean` 메서드끼리 직접 호출할 때 싱글톤을 보장하려고 존재하는데, 그렇게 호출하지 않는 설정 클래스에서는 불필요한 비용이다. 네이티브에서는 그 프록시를 빌드 시점에 생성해야 하므로 비용이 더 커진다.
</details>

## 한 줄 요약

> 네이티브냐 JVM이냐가 아니라 **결정 시점이 빌드로 옮겨갔느냐**가 축이다. 빈의 존재는 빌드에서 굳고 빈이 읽는 값은 런타임에 남는다 — 이 경계만 잡으면 AOT에서 나는 사고는 대부분 같은 사고다.
