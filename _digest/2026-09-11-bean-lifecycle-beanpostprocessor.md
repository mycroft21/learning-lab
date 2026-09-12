---
title: "Bean 생명주기 & BeanPostProcessor"
date: 2026-09-11
domain: spring
slots: 1
parts_done: 1
tags: [spring, bean-lifecycle, beanpostprocessor, dependency-injection]
---

## 생성자에서 그 필드 쓰다가 NPE 터진 적 있다면, 범인은 Bean 생명주기다

9년차쯤 되면 이런 버그를 한 번쯤 만난다 — 생성자 안에서 @Autowired 필드를 참조했는데 NullPointerException이 난다. "분명 스프링이 다 주입해줬을 텐데?" 싶지만, 사실 생성자가 실행되는 시점에는 필드 주입이 아직 시작도 안 됐다. Bean 생명주기를 순서대로 모르면 이런 사고를 반복하게 되고, 면접에서도 '생성자 주입을 권장하는 이유가 뭔가요?'라는 질문에 '그냥 관례라서요' 이상의 답을 못 하게 된다. 오늘은 이미 아는 '스프링이 빈을 만들고 관리해준다' 수준은 건너뛰고, 실무 사고와 인터뷰 둘 다에서 진짜 걸리는 지점만 짚는다.

## 생명주기, 그냥 순서가 아니라 '무엇이 언제 준비되는가'의 문제

표준 순서는 인스턴스화 → 프로퍼티(의존성) 주입 → Aware 콜백(BeanNameAware, BeanFactoryAware, ApplicationContextAware 등) → BeanPostProcessor.postProcessBeforeInitialization → 초기화 콜백(@PostConstruct, InitializingBean.afterPropertiesSet(), 커스텀 init-method 순) → BeanPostProcessor.postProcessAfterInitialization → 실사용 → 종료 콜백(@PreDestroy, DisposableBean.destroy())이다.

자문자답 하나: '그럼 생성자 시점에는 뭐가 준비돼 있나?' 답은 '아무 의존성도 없다'다. 인스턴스화는 말 그대로 new 호출이라 필드 주입도, Aware도, 초기화 콜백도 전부 그 뒤에 일어난다. 그래서 필드/세터 주입을 쓰면 생성자 실행 시점과 실제로 의존성이 다 채워진 시점 사이에 '반쯤 완성된 객체'가 존재하는 시간이 생기고, 그 사이에 실수로 의존성을 참조하면 NPE가 난다. 생성자 주입이 권장되는 진짜 이유는 '스타일'이 아니라, 생성자 호출 자체가 이미 모든 의존성이 채워진 뒤에 일어나도록 강제해서 이 반쯤 완성된 상태를 아예 없애기 때문이다.

## BeanPostProcessor의 진짜 정체는 'AOP 프록시 공장'이다

@Transactional, @Async, @Cacheable을 붙이면 마법처럼 동작하는 것처럼 보이지만, 그 마법이 실제로 일어나는 지점이 바로 BeanPostProcessor.postProcessAfterInitialization이다. AnnotationAwareAspectJAutoProxyCreator라는 BeanPostProcessor 구현체가 초기화가 끝난 원본 빈을 가로채서, 어드바이스가 필요하다고 판단되면 원본을 감싼 프록시 객체로 바꿔치기해 컨테이너에 등록한다. 즉 우리가 @Autowired로 주입받는 건 대부분의 경우 원본 클래스가 아니라 이 프록시다.

이걸 알면 그 유명한 self-invocation 함정이 왜 생기는지 한 번에 이해된다 — 같은 클래스 안에서 this.transactionalMethod()처럼 자기 메서드를 직접 호출하면, 그 호출은 프록시를 거치지 않고 원본 인스턴스 안에서 바로 일어나기 때문에 트랜잭션도 캐시도 비동기도 전부 조용히 무시된다. '왜 로그도 에러도 없이 트랜잭션이 안 걸리지?'라는 질문의 답은 대부분 여기 있다.

## 인터뷰에서 진짜 뼈 때리는 질문 3개

Q1. '@PostConstruct 메서드에서 예외가 나면 어떻게 되나요?' — 그 빈 하나만 실패하고 넘어가는 게 아니라 ApplicationContext 전체 초기화가 실패하며 애플리케이션이 아예 뜨지 않는다. 스프링은 반쯤 초기화된 빈을 그대로 방치하지 않고 fail-fast로 죽여버린다.

Q2. '커스텀 BeanPostProcessor 안에서 @Autowired로 일반 빈을 주입받으면 무슨 문제가 있나요?' — BeanPostProcessor는 다른 모든 일반 빈보다 먼저 등록·동작해야 하는 특수한 존재인데, 여기서 일반 빈에 의존하면 그 빈의 생성을 억지로 앞당기게 된다(조기 초기화). 이러면 원래 순서대로였다면 안 생겼을 순환 참조나, 그 빈이 아직 다른 BeanPostProcessor를 거치기 전 '덜 완성된' 상태로 주입되는 문제가 생길 수 있다. 스프링 공식 문서도 이 패턴을 명시적으로 경고한다.

Q3. 'ApplicationContextAware로 받은 컨텍스트를 초기화 시점에 바로 써도 되나요?' — Aware 콜백은 프로퍼티 주입 직후, BeanPostProcessor보다도 먼저 호출되기 때문에 이 시점에는 다른 빈들이 전부 준비돼 있다고 보장할 수 없다. 안전하게 다른 빈을 꺼내 쓰려면 @PostConstruct 이후로 미뤄야 한다.

## 한 줄 요약

Bean 생명주기는 '인스턴스화 → 의존성 주입 → Aware → BeforeInit → 초기화 콜백 → AfterInit' 순서로 촘촘하게 진행되고, @Transactional·@Async 같은 AOP 마법은 전부 이 AfterInit 단계에서 BeanPostProcessor가 원본을 프록시로 바꿔치기하면서 일어난다 — 그래서 self-invocation이 트랜잭션·캐시·비동기를 조용히 무력화시킨다는 것 하나만 확실히 기억해도 인터뷰 절반은 먹고 들어간다.
