---
title: "Bean 생명주기 & BeanPostProcessor"
date: 2026-09-11
domain: spring
slots: 1
parts_done: 1
tags: [spring, bean-lifecycle, beanpostprocessor, dependency-injection]
---

## 순서표를 외운 사람과 이 코드를 돌려본 사람의 답이 갈린다

"인스턴스화 → 의존성 주입 → Aware → BeforeInit → 초기화 콜백 → AfterInit"까지는 대부분 왼다. 그 순서표가 맞는지 한 번만 직접 찍어보면 두 군데가 예상과 다르다.

```java
@Component
public class Probe implements BeanFactoryAware, ApplicationContextAware, InitializingBean {
    public Probe() { System.out.println("1 생성자"); }
    public void setBeanFactory(BeanFactory bf) { System.out.println("2 BeanFactoryAware"); }
    public void setApplicationContext(ApplicationContext ctx) { System.out.println("3 ApplicationContextAware"); }
    @PostConstruct void post() { System.out.println("4 @PostConstruct"); }
    public void afterPropertiesSet() { System.out.println("5 afterPropertiesSet"); }
}
```

```
1 생성자
2 BeanFactoryAware
3 ApplicationContextAware
4 @PostConstruct
5 afterPropertiesSet
```

`@PostConstruct`가 `afterPropertiesSet()`보다 **먼저** 나온다. 둘 다 "초기화 콜백"이라고 묶어 외운 것치고는 이상하다. 그리고 `BeanFactoryAware`와 `ApplicationContextAware`는 같은 "Aware 단계"에 있는 것처럼 배웠는데 실제로는 서로 다른 메커니즘으로 호출된다. 순서표가 왜 이 모양인지는 `AbstractAutowireCapableBeanFactory.initializeBean()` 다섯 줄을 보면 끝난다.

## 들어간 객체와 나온 객체가 다르다

```java
invokeAwareMethods(beanName, bean);                                  // BeanName·BeanClassLoader·BeanFactoryAware만
Object wrappedBean = bean;
wrappedBean = applyBeanPostProcessorsBeforeInitialization(wrappedBean, beanName);
invokeInitMethods(beanName, wrappedBean, mbd);                       // afterPropertiesSet() → init-method
wrappedBean = applyBeanPostProcessorsAfterInitialization(wrappedBean, beanName);
return wrappedBean;                                                  // ← 컨테이너에 등록되는 건 이것
```

> 인자로 들어간 `bean`과 반환되는 `wrappedBean`은 같은 객체가 아닐 수 있다. 그 사이를 채우는 단계가 거의 전부 `BeanPostProcessor`이고, 생명주기 순서표는 "언제 어떤 `BeanPostProcessor`가 끼어드는가"의 다른 이름이다.

위 출력이 이 다섯 줄에서 그대로 연역된다.

- 컨테이너가 손으로 직접 부르는 Aware는 `BeanNameAware`·`BeanClassLoaderAware`·`BeanFactoryAware` **셋뿐이다.** `ApplicationContextAware`를 비롯해 `EnvironmentAware`, `ResourceLoaderAware`, `ApplicationEventPublisherAware`, `MessageSourceAware`는 `ApplicationContextAwareProcessor`라는 `BeanPostProcessor`가 `postProcessBeforeInitialization`에서 호출한다. 그래서 2번과 3번 사이에 단계 경계가 하나 있다.
- `@PostConstruct`도 콜백이 아니라 `BeanPostProcessor`다. `CommonAnnotationBeanPostProcessor`(상위 `InitDestroyAnnotationBeanPostProcessor`)가 역시 `postProcessBeforeInitialization`에서 리플렉션으로 호출한다. 반면 `afterPropertiesSet()`과 `init-method`는 3번째 줄 `invokeInitMethods()`가 부른다. 4번이 5번보다 먼저인 건 그래서다.
- 생성자는 이 다섯 줄보다도 앞, 의존성 주입(`populateBean`)보다도 앞이다. 생성자에서 `@Autowired` 필드를 읽으면 NPE가 나는 게 당연하고, 생성자 주입이 권장되는 이유도 "스타일"이 아니라 **이 다섯 줄이 시작될 시점에 이미 의존성이 다 채워져 있도록 강제**하기 때문이다.

<details markdown="1">
<summary>종료 쪽 순서와 프로토타입 빈이라는 예외</summary>

소멸은 `@PreDestroy` → `DisposableBean.destroy()` → 커스텀 `destroy-method` 순으로, 초기화와 대칭이다(`@PreDestroy`도 `InitDestroyAnnotationBeanPostProcessor`가 처리한다).

다만 **프로토타입 빈은 소멸 콜백이 전혀 호출되지 않는다.** 컨테이너가 프로토타입 인스턴스를 만들어 넘겨준 뒤로는 그 참조를 들고 있지 않기 때문이다. 프로토타입 빈이 커넥션이나 스레드를 물고 있다면 정리는 호출한 쪽 책임이다.

</details>

## 마지막 줄에서 객체가 통째로 바뀐다

`applyBeanPostProcessorsAfterInitialization`이 반환한 객체가 컨테이너에 등록된다. `AbstractAutoProxyCreator` 계열 `BeanPostProcessor`가 여기서 원본 대신 프록시를 반환하면, 이후 아무도 원본을 볼 수 없다. 한 줄로 확인된다.

```java
System.out.println(userService.getClass());
// class com.example.UserService$$SpringCGLIB$$0
```

이 사실에서 타이밍 함정 하나가 바로 나온다. **`@PostConstruct` 안의 `this`는 언제나 원본이다.** 프록시 교체는 그보다 한 줄 뒤에서 일어나기 때문이다. 그래서 `@PostConstruct` 메서드에 `@Transactional`을 붙여도, 혹은 그 안에서 자기 트랜잭션 메서드를 호출해도 예외도 경고도 없이 조용히 무시된다. 초기 데이터 적재를 `@PostConstruct`에서 하다가 롤백이 안 되는 사고가 이 자리다. 해결은 `ApplicationRunner`나 `ApplicationReadyEvent`처럼 컨테이너 기동이 끝난 뒤로 미루는 것이다.

프록시를 거치지 않은 호출에 어드바이스가 통째로 무시되는 메커니즘 자체와 self-invocation의 전모는 [AOP 프록시 편](/learning-lab/digest/2026-09-11-aop-proxy-self-invocation/)에서 다룬다. 여기서는 "그 프록시가 언제 끼어드는가"만 알면 된다 — 초기화가 전부 끝난 뒤, 컨테이너에 등록되기 직전이다.

## BeanPostProcessor는 자기 자신에게는 적용되지 않는다

`BeanPostProcessor`가 일반 빈을 손보려면 일반 빈보다 먼저 만들어져 있어야 한다. 그래서 컨테이너는 싱글톤을 미리 만들기 전에 `BeanPostProcessor`들을 먼저 등록한다. 여기서 규칙이 하나 따라 나온다 — **그 시점에 딸려 만들어진 빈은 아직 등록되지 않은 나머지 `BeanPostProcessor`를 못 거친다.**

커스텀 `BeanPostProcessor`가 일반 빈을 `@Autowired`로 받으면 그 빈이 강제로 조기 생성되면서 이 상태가 된다. 스프링은 조용히 넘어가지 않고 기동 로그에 경고를 남긴다.

```
WARN o.s.c.s.PostProcessorRegistrationDelegate$BeanPostProcessorChecker
  Bean 'auditService' of type [com.example.AuditService] is not eligible for getting
  processed by all BeanPostProcessors (for example: not eligible for auto-proxying).
```

괄호 안이 실제 피해다 — `not eligible for auto-proxying`, 즉 그 빈은 프록시 교체 단계를 건너뛰었으므로 `@Transactional`, `@Async`, `@Cacheable`이 **전부 무효**다. 컴파일도 되고 기동도 되고 테스트도 통과하는데 트랜잭션만 사라진다. 기동 로그에서 이 한 줄을 찾는 게 유일한 발견 수단이다.

피하는 방법은 그 의존성을 `ObjectProvider`나 `BeanFactory`로 받아 실제로 쓰는 시점에 꺼내는 것이다. 같은 이유로 `@Bean`으로 선언하는 `BeanPostProcessor`는 `static` 메서드로 만든다 — 아니면 그 `@Configuration` 클래스 자체가 조기 초기화에 끌려 들어간다.

## 인터뷰에서 이렇게 나온다

**"`@PostConstruct`와 `InitializingBean.afterPropertiesSet()` 중 뭐가 먼저 호출되나요?"**

<details markdown="1">
<summary>답 확인</summary>

`@PostConstruct`가 먼저다. `@PostConstruct`는 `CommonAnnotationBeanPostProcessor`가 `postProcessBeforeInitialization` 단계에서 호출하는 반면, `afterPropertiesSet()`은 그 뒤에 오는 `invokeInitMethods()`가 호출하기 때문이다. 둘을 같은 "초기화 콜백"으로 묶어 외우면 이 순서가 안 나온다 — `@PostConstruct`는 콜백이 아니라 `BeanPostProcessor`라고 보는 게 정확하다.

</details>

**"커스텀 `BeanPostProcessor`에서 다른 빈을 `@Autowired`로 주입받으면 무슨 일이 생기나요?"**

<details markdown="1">
<summary>답 확인</summary>

그 빈이 `BeanPostProcessor` 등록 단계에 끌려 들어와 조기 생성되고, 아직 등록되지 않은 나머지 `BeanPostProcessor`를 거치지 못한다. 결과적으로 자동 프록시 생성 대상에서 빠져 `@Transactional`·`@Async`·`@Cacheable`이 조용히 무효가 된다. 기동 로그의 `is not eligible for getting processed by all BeanPostProcessors ... not eligible for auto-proxying` 경고가 증거다. 의존성은 `ObjectProvider`로 늦게 받고, `@Bean` 선언은 `static`으로 한다.

</details>

**"`@PostConstruct`에 `@Transactional`을 붙였는데 왜 롤백이 안 되죠?"**

<details markdown="1">
<summary>답 확인</summary>

프록시 교체는 `applyBeanPostProcessorsAfterInitialization`에서 일어나는데, `@PostConstruct`는 그보다 앞선 `postProcessBeforeInitialization` 단계에서 실행된다. 그 시점의 `this`는 아직 프록시로 감싸이기 전의 원본이라 어드바이스가 걸릴 자리가 없다. 기동 완료 후에 돌아야 하므로 `ApplicationRunner`나 `ApplicationReadyEvent` 리스너로 옮긴다.

</details>

## 한 줄 요약

> `initializeBean()`에 들어간 객체와 나온 객체는 같지 않다 — Aware 두 종류가 갈리는 것도, `@PostConstruct`가 `afterPropertiesSet()`보다 먼저인 것도, 주입받은 게 원본이 아니라 프록시인 것도, 조기 초기화된 빈에서 `@Transactional`이 사라지는 것도 전부 "그 사이는 `BeanPostProcessor`가 채운다"는 한 문장에서 나온다.
