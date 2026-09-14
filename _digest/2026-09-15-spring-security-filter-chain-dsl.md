---
title: "Spring Security 필터체인 최신 람다 DSL"
date: 2026-09-15
domain: spring
slots: 1
parts_done: 1
tags: [spring, spring-security, authorization]
---

## "람다로 문법만 바뀐 거다"라는 전제부터 틀렸다

`http.authorizeRequests()`를 `http.authorizeHttpRequests()`로, `antMatchers`를 `requestMatchers`로 기계적으로 바꿔치기만 하면 마이그레이션이 끝난다고 생각하기 쉽다. 그런데 이 둘은 내부에서 **다른 필터가 동작한다** — `authorizeRequests`는 `FilterSecurityInterceptor`, `authorizeHttpRequests`는 `AuthorizationFilter`. 문법이 아니라 판단 엔진 자체가 바뀐 것이다.

"그래도 신버전이니 더 안전하겠지"라고 생각했다면 CVE-2022-31692가 그 생각을 바로 깬다. 터진 쪽은 구버전이 아니라 **신버전**이다. `authorizeHttpRequests()`가 도입한 `AuthorizationFilter`를 `shouldFilterAllDispatcherTypes(true)`로 forward/include까지 필터체인에 태우도록 설정한 앱에서, forward된 요청이 원래 요청의 인가 판단을 그대로 물려받아 **다시 평가되지 않는** 경우가 있었다. `/admin/**`을 막아뒀어도 그 경로로 forward된 요청은 인가를 다시 안 거칠 수 있었다는 뜻이다. 구버전 `authorizeRequests`는 애초에 이 CVE의 대상도 아니다 — 대신 필터가 요청당 한 번만 도는지를 제어하는 별개의 스위치(`filterSecurityInterceptorOncePerRequest`)를 썼을 뿐이다.

확인하려면 `logging.level.org.springframework.security=DEBUG`를 켜고 forward 대상 경로에 대한 요청 로그에 `AuthorizationFilter` 판단 라인이 실제로 찍히는지 보면 된다 — 안 찍히면 그 요청엔 규칙이 아예 안 걸린 것이다.

## 인가 규칙이 실제로 걸리는 조건은 두 가지뿐이다

`requestMatchers(...)`를 아무리 정확히 써도 아래 두 조건 중 하나라도 안 맞으면 그 규칙은 존재하지 않는 것과 같다.

- **선언 순서에서 이 요청과 먼저 매칭되는가.** 인가 규칙은 위에서부터 첫 매칭이 적용되고 끝난다. `/admin/**`을 `/admin/login`보다 먼저 적으면, `/admin/login`용 `permitAll()`은 영원히 실행되지 않는 죽은 규칙이 된다.
- **이 요청의 디스패처 타입이 필터 체인을 통과하는가.** `REQUEST`(브라우저가 직접 친 요청)만 항상 통과가 보장되고, `FORWARD`/`ERROR`/`INCLUDE`는 명시적으로 처리하지 않으면 걸릴 수도 안 걸릴 수도 있다.

`authorizeHttpRequests`가 구버전보다 나은 지점은 이 두 번째 조건을 **개발자가 선언할 수 있게** 만들었다는 것이다 — 위 CVE의 재발 방지책으로 들어간 기능이 바로 이것이다.

```java
.authorizeHttpRequests(auth -> auth
    .dispatcherTypeMatchers(DispatcherType.FORWARD, DispatcherType.ERROR).permitAll()
    .requestMatchers("/admin/login").permitAll()
    .requestMatchers("/admin/**").hasRole("ADMIN")
    .anyRequest().authenticated())
```

## `authorizeRequests` vs `authorizeHttpRequests`, 축 세 개로 비교

| 축 | `authorizeRequests` (구) | `authorizeHttpRequests` (신) |
|---|---|---|
| 실제로 도는 필터 | `FilterSecurityInterceptor` | `AuthorizationFilter` |
| 판단 방식 | 메타데이터 소스 + `AccessDecisionManager` + voter 조합 | 단순화된 `AuthorizationManager` |
| 디스패처 타입 처리 | 요청당 한 번만 도는지를 제어하는 스위치(`filterSecurityInterceptorOncePerRequest`)만 있음 | `dispatcherTypeMatchers(...)`로 타입별 선언 가능 — 명시하지 않으면 CVE-2022-31692처럼 forward가 재평가 없이 통과할 수 있다 |

경로 매처가 `antMatchers`/`mvcMatchers`/`regexMatchers`로 나뉘어 있던 것도 `requestMatchers()` 하나로 통일됐는데, 이건 표에 넣을 만큼 독립적인 축이라기보다는 위 판단 엔진 교체에 딸려온 정리에 가깝다.

## 경계 조건: 이건 스타일 선택이 아니라 강제 전환이다

`WebSecurityConfigurerAdapter`를 상속하는 방식은 Spring Security 5.7에서 사용 지양 예고가 됐고, 6.0에서 **클래스 자체가 삭제됐다.** "새 프로젝트는 람다 DSL로, 기존 프로젝트는 그대로"가 성립하지 않는다는 뜻이다 — Boot 3(Spring Security 6) 이상으로 올리는 순간 컴파일이 깨진다.

## 인터뷰에서 이렇게 나온다

**"authorizeRequests에서 authorizeHttpRequests로 바뀌면서 실질적으로 뭐가 달라졌나요?"**

<details markdown="1">
<summary>답 확인</summary>

문법이 아니라 내부 필터가 `FilterSecurityInterceptor`에서 `AuthorizationFilter`로 바뀌었고, 판단 방식도 voter 조합에서 `AuthorizationManager`로 단순화됐다는 걸 먼저 짚는다. `dispatcherTypeMatchers`로 디스패처 타입별 인가를 명시할 수 있게 된 것도 실무 임팩트인데, 이 기능 자체가 CVE-2022-31692의 재발 방지책으로 들어간 것이라는 점도 짚으면 좋다 — 새 API가 이 문제를 원천 차단한 게 아니라, 잘못 설정하면 새 API에서도 같은 종류의 우회가 실제로 났었다는 뜻이다.

</details>

**"requestMatchers 규칙 두 개가 겹치면 어떻게 되나요?"**

<details markdown="1">
<summary>답 확인</summary>

먼저 선언된 규칙이 적용되고 뒤는 평가되지 않는다. 좁은 패턴을 넓은 패턴보다 먼저 선언해야 하고, 순서를 반대로 두면 좁은 규칙은 죽은 코드가 된다.

</details>

## 한 줄 요약

> 인가 규칙은 선언만으로 걸리지 않는다 — 그 요청과 먼저 매칭되는 규칙이 있는가, 그리고 그 요청의 디스패처 타입이 필터 체인을 통과하는가, 이 두 조건이 실제로 걸리는지를 결정하고, `authorizeHttpRequests`는 두 번째 조건을 처음으로 개발자가 통제 가능하게 만들었다 — 다만 그 통제를 직접 선언하지 않으면 신버전도 CVE-2022-31692처럼 뚫릴 수 있다.
