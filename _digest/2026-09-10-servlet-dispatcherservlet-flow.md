---
title: "서블릿 & DispatcherServlet 요청 흐름"
date: 2026-09-10
domain: spring
slots: 1
parts_done: 1
tags: [spring, servlet, dispatcherservlet, spring-mvc]
---

## "Filter가 먼저 돌고 Interceptor가 나중에 돈다"로 외워뒀다면 절반만 안 것이다

실행 순서만 외운 상태에서는 "그럼 인증을 Filter에 넣든 Interceptor에 넣든 순서만 맞추면 되는 거 아닌가"가 자연스러운 결론이 된다. 실무에서 인증 구멍이 나는 지점이 정확히 여기다.

두 인터페이스의 시그니처를 나란히 놓으면 순서가 아니라 **가진 정보의 양**이 다르다는 게 바로 보인다.

```java
// jakarta.servlet.Filter — 서블릿 스펙
void doFilter(ServletRequest req, ServletResponse res, FilterChain chain);

// org.springframework.web.servlet.HandlerInterceptor — Spring MVC
boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler);
```

`Filter`는 이 요청이 HTTP인지조차 타입으로 보장받지 못한다(`ServletRequest`다). 반대로 `preHandle`에는 `handler`가 이미 인자로 들어와 있다. 이 한 칸의 차이가 오늘 글 전체다.

## 선은 하나뿐이다 — 이 요청을 처리할 핸들러가 정해졌는가

> 요청 처리 경로를 가르는 선은 딱 하나, "이 요청을 처리할 핸들러가 이미 정해졌는가"다. 그 선 앞쪽은 서블릿 컨테이너의 영역이라 핸들러를 모르고, 뒤쪽은 `DispatcherServlet`의 영역이라 핸들러를 안다.

`DispatcherServlet.doDispatch()`가 하는 일을 순서대로 늘어놓으면 선이 어디에 그어져 있는지 눈으로 확인된다.

1. `getHandler(request)` — `HandlerMapping`들을 순회해 `HandlerExecutionChain`(핸들러 + 그 핸들러에 적용될 인터셉터 목록)을 얻는다. **선은 여기다.**
2. `getHandlerAdapter(handler)` — 그 핸들러를 실행할 줄 아는 어댑터를 고른다.
3. `applyPreHandle()` — 인터셉터의 `preHandle`.
4. `ha.handle()` — 컨트롤러 메서드 실행.
5. `applyPostHandle()` — `ModelAndView`를 넘겨받는다.
6. `processDispatchResult()` — 여기서 예외가 잡히면 `HandlerExceptionResolver`로 간다.

인터셉터 목록 자체가 1번의 **결과물**이다. 핸들러가 정해지기 전에는 "어떤 인터셉터를 태울지"조차 알 수 없으니, 인터셉터가 1번보다 앞에 존재하는 건 구조적으로 불가능하다. 필터는 반대로 `doDispatch()`가 호출되기도 전, 컨테이너가 서블릿을 고르기 전 단계에 있다.

## 이 선 하나에서 나머지가 전부 연역된다

**Spring Security가 Interceptor가 아니라 Filter인 이유.** 인증·인가는 어떤 컨트롤러가 처리할지와 무관하게 걸려야 하고, `DispatcherServlet`까지 가지도 않는 요청(다른 서블릿으로 가는 요청, 컨테이너가 직접 서빙하는 정적 파일, 에러 디스패치)에도 걸려야 하며, 통과 못 한 요청은 MVC 인프라를 건드리기 전에 끊어야 한다. 인터셉터는 정의상 이 셋 중 어느 것도 만족할 수 없다.

Security가 컨테이너에 실제로 꽂는 건 `DelegatingFilterProxy`라는 얇은 껍데기 하나이고, 이게 요청마다 `springSecurityFilterChain`이라는 이름의 스프링 빈(`FilterChainProxy`)을 찾아 위임한다. 껍데기가 한 겹 필요한 건 서블릿 컨테이너가 스프링 빈을 모르기 때문이다 — 컨테이너가 직접 `new`한 필터에는 DI도 프록시도 붙지 않는다. 스프링 빈이 되는 것과 안 되는 것의 차이는 [Bean 생명주기 편](/learning-lab/digest/2026-09-11-bean-lifecycle-beanpostprocessor/)에서 본다. 등록 순서는 `spring.security.filter.order`이고 기본값은 `-100`이다.

**필터에서 던진 예외가 `@ControllerAdvice`에 안 잡히는 이유.** `HandlerExceptionResolver`는 위 6번, 즉 `doDispatch()` **안**에 있다. 필터 예외는 `doDispatch()`가 시작되기도 전에 컨테이너로 튀어 올라가므로 사정권 밖이다. 컨테이너는 이걸 받아 `/error`로 ERROR 디스패치를 일으키고, Boot에서는 `BasicErrorController`가 응답한다. 확인은 간단하다 — 커스텀 인증 필터에서 예외를 하나 던져보면, `@RestControllerAdvice`가 만들어주던 에러 포맷 대신 `timestamp`/`status`/`error`만 있는 Boot 기본 응답이 돌아온다.

**`postHandle`에서 `ModelAndView`를 만질 수 있는 이유.** 5번이 4번 뒤이기 때문이다. 필터는 이 객체의 존재 자체를 모른다. 대신 필터는 `HttpServletResponseWrapper`로 응답 전체를 감쌀 수 있고, 인터셉터는 감싸는 게 아니라 끼어드는 것이라 그걸 못 한다.

## 통념이 깨지는 경계 세 곳

**"인터셉터는 정적 리소스에 안 걸린다"** — Spring MVC가 서빙하는 정적 리소스라면 걸린다. `WebMvcConfigurationSupport.resourceHandlerMapping()`은 자기가 만든 핸들러 매핑에도 `setInterceptors(getInterceptors(...))`를 그대로 호출한다. `ResourceHttpRequestHandler`도 엄연히 1번에서 선택된 핸들러이기 때문이다. 1분 확인법은 이렇다.

```java
public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) {
    log.info("[{}] handler = {}", req.getRequestURI(), handler.getClass().getSimpleName());
    return true;
}
```

`/index.html`을 때리면 아무것도 안 찍힐 것 같지만 `ResourceHttpRequestHandler`가 찍힌다. `handler`를 `HandlerMethod`로 무조건 캐스팅하는 코드가 정적 리소스 요청에서 `ClassCastException`으로 죽는 사고가 여기서 나온다. 진짜로 안 걸리는 건 컨테이너의 default servlet이 직접 서빙하는 파일(WAR의 `src/main/webapp` 아래 같은)이다.

**"필터는 모든 요청에 다 걸린다"** — 디스패처 타입에 따라 갈린다. Boot 3.x가 필터를 등록할 때 디스패처 타입을 지정하지 않으면, `OncePerRequestFilter`를 상속한 필터는 전 타입(`REQUEST`, `FORWARD`, `INCLUDE`, `ERROR`, `ASYNC`)에, 그냥 `Filter`만 구현한 필터는 `REQUEST` 하나에만 등록된다. 그래서 평범한 `Filter`로 짠 로깅 필터는 `/error`로 가는 ERROR 디스패치에서 조용히 안 돈다. Security는 별도로 `spring.security.filter.dispatcher-types`를 쓰고 기본값이 `request, async, error`라서, 에러 디스패치에도 보안이 살아 있다.

**"DispatcherServlet은 앱당 하나다"** — 서블릿이니까 URL 패턴별로 여러 개 등록할 수 있고, 각자 자기 `WebApplicationContext`를 갖는다. 그래서 필터는 앱 전역이고 인터셉터는 그 `DispatcherServlet` 안에서만 유효하다. 이것도 같은 선의 결과다 — 선 뒤쪽은 여러 개일 수 있지만 선 앞쪽은 컨테이너 하나다.

## 인터뷰에서 이렇게 나온다

**"Filter와 Interceptor 중에 인증을 어디에 넣으시겠어요? 왜죠?"**

<details markdown="1">
<summary>답 확인</summary>

Filter다. 인터셉터는 `HandlerMapping`이 핸들러를 결정한 **이후**에만 존재할 수 있는데, 인증은 어떤 핸들러가 처리할지와 무관하게, 그리고 `DispatcherServlet`에 도달하지 않는 요청에도 적용돼야 한다. `preHandle`의 세 번째 인자가 `Object handler`라는 사실 자체가 "핸들러가 이미 정해진 뒤"라는 증거다. Security도 같은 이유로 `DelegatingFilterProxy` → `FilterChainProxy` 구조를 쓴다.

</details>

**"커스텀 JWT 필터에서 던진 예외가 `@RestControllerAdvice`에 안 잡힙니다. 왜인가요?"**

<details markdown="1">
<summary>답 확인</summary>

`HandlerExceptionResolver`는 `DispatcherServlet.doDispatch()` 내부에서 동작한다. 필터 예외는 `doDispatch()`에 진입하기 전에 컨테이너로 올라가므로 그 경로를 아예 타지 않고, 컨테이너가 `/error`로 ERROR 디스패치를 일으켜 Boot 기본 에러 응답이 나간다. 필터 안에서 직접 `try-catch`로 응답을 쓰거나, `HandlerExceptionResolver`를 주입받아 `resolveException()`을 호출하거나, Security라면 `AuthenticationEntryPoint`로 처리한다.

</details>

**"인터셉터를 전체 경로에 걸었더니 `handler`를 `HandlerMethod`로 캐스팅하는 데서 예외가 납니다."**

<details markdown="1">
<summary>답 확인</summary>

Spring MVC가 서빙하는 정적 리소스도 `ResourceHttpRequestHandler`라는 핸들러로 매핑되고, 그 핸들러 매핑에도 같은 인터셉터가 등록된다. `handler`는 `HandlerMethod`만 오는 게 아니다. `if (!(handler instanceof HandlerMethod)) return true;`로 먼저 걸러내거나 `excludePathPatterns`로 리소스 경로를 빼야 한다.

</details>

## 한 줄 요약

> "이 요청을 처리할 핸들러가 정해졌는가" — 이 선 하나가 Filter와 Interceptor의 계층(선 앞/뒤), Security가 Filter인 이유(핸들러와 무관하게 걸려야 하므로), 필터 예외가 `@ControllerAdvice`에 안 잡히는 이유(`HandlerExceptionResolver`는 선 뒤에 있으므로)를 전부 설명한다.
