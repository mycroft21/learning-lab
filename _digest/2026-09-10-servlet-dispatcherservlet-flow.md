---
title: "서블릿 & DispatcherServlet 요청 흐름"
date: 2026-09-10
domain: spring
slots: 1
parts_done: 1
tags: [spring, servlet, dispatcherservlet, spring-mvc]
---

## 면접에서 "요청 하나가 컨트롤러까지 오는 동안 뭘 거치나요?" 받으면 몇 초 안에 답 나오나요?

9년차인데 이 질문에 "DispatcherServlet이 받아서 컨트롤러로 보내요" 정도로 뭉개고 넘어간 적 있다면 이번 파트가 딱 필요한 파트다. 실무에서는 프레임워크가 다 해주니까 이 흐름을 굳이 뜯어볼 일이 없는데, 면접관은 정확히 그 지점 — Filter, DispatcherServlet, Interceptor, HandlerAdapter가 각각 왜 다른 계층에 있는지 — 을 파고든다. 오늘은 이미 아는 "Front Controller 패턴이다" 수준은 건너뛰고, 실무에서 사고로 이어지는 경계선들만 짚는다.

## DispatcherServlet은 그냥 서블릿 하나다 — 근데 이게 왜 중요하냐면

DispatcherServlet은 HttpServlet을 상속한 진짜 서블릿이라서, Tomcat 같은 서블릿 컨테이너 입장에서는 그냥 web.xml(혹은 Boot의 자동 등록)에 매핑된 서블릿 하나일 뿐이다. 요청이 오면 컨테이너가 service() → doGet/doPost를 부르고, DispatcherServlet은 이걸 오버라이드한 doService()에서 자기 내부 흐름(doDispatch)으로 넘긴다. 여기서 흔히 놓치는 포인트: DispatcherServlet은 한 애플리케이션에 하나만 있어야 한다는 생각은 틀렸다 — URL 패턴별로 여러 개 등록해서 각기 다른 Spring ApplicationContext(=서블릿별 WebApplicationContext)를 물릴 수 있다. 레거시 멀티모듈 웹앱에서 관리자 콘솔과 API 서버를 서블릿 매핑만 다르게 해서 한 WAR에 공존시키는 구조가 이 원리를 쓴 것이다.

## Filter vs Interceptor, "순서만 다르지 같은 거 아니야?" — 실제로는 아예 다른 계층

이 둘을 그냥 "실행 순서 차이" 정도로 알고 있으면 인터뷰에서 바로 티가 난다. Filter(javax/jakarta.servlet.Filter)는 서블릿 스펙 자체의 개념이라 DispatcherServlet보다 바깥, 즉 서블릿 컨테이너 레벨에서 동작한다 — 그래서 Spring이 뜨기 전에도 실행되고, 정적 리소스 요청에도 걸리고, 아직 어떤 컨트롤러가 처리할지(HandlerMethod) 전혀 모른다. 반면 HandlerInterceptor는 순수 Spring MVC 개념으로, DispatcherServlet이 HandlerMapping으로 핸들러를 이미 찾아낸 뒤에 끼어든다 — 그래서 preHandle 시점에 이미 "이 요청을 처리할 컨트롤러 메서드가 정확히 뭔지" 알고 있고, postHandle에서는 ModelAndView까지 만질 수 있다. 실전 함정: 인증 실패를 처리하겠다고 Interceptor에 넣었다가 정적 리소스나 에러 페이지 요청에는 아예 안 걸려서 구멍이 생기는 사고가 흔하다.

## 그럼 Spring Security는 왜 Interceptor가 아니라 Filter로 만들었을까

이게 자주 나오는 응용 질문이다. Security는 DelegatingFilterProxy라는 서블릿 필터 하나를 컨테이너 필터 체인에 끼워넣고, 그 안에서 Spring 빈으로 관리되는 FilterChainProxy(실제 보안 필터들의 체인)에 위임하는 구조다. 왜 Interceptor가 아니라 Filter냐면, 인증/인가는 DispatcherServlet이 handler를 찾기도 전에, 그리고 정적 리소스 요청에도 무조건 적용돼야 하는 관심사이기 때문이다 — Interceptor는 애초에 "핸들러가 정해진 이후"에만 동작하므로 이 요구를 만족 못 한다. 여기서 또 하나 실전 사고: 컨트롤러에서 발생한 예외는 DispatcherServlet 내부의 HandlerExceptionResolver(@ExceptionHandler, @ControllerAdvice)가 잡아주지만, Filter 단계(즉 Security 필터 체인이나 커스텀 인증 필터)에서 던진 예외는 이 흐름 바깥이라 못 잡힌다. 그래서 필터 안에서 발생한 예외 때문에 @ControllerAdvice가 무용지물이 되고 스택트레이스가 그대로 응답에 노출되는 장애가 실무에서 종종 터진다 — 필터 자체에 try-catch를 두거나 별도 EntryPoint로 처리해야 하는 이유다.

## 한 줄 요약

Filter는 "서블릿 컨테이너가 스프링을 모르던 시절의 관문"이고 Interceptor는 "스프링이 핸들러를 이미 알고 난 뒤의 관문"이라는 계층 차이를 기억하면, Security가 왜 Filter 기반인지·왜 필터 예외는 @ControllerAdvice로 안 잡히는지가 한 번에 풀린다.
