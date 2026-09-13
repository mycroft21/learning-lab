---
title: "AOP 프록시 메커니즘과 self-invocation 함정"
date: 2026-09-11
domain: spring
slots: 2
parts_done: 2
tags: [spring, aop, proxy]
---

## `@Transactional`이 붙어 있다는 것과 트랜잭션이 열렸다는 것은 다른 사실이다

`OrderService.save()`가 같은 클래스의 `internalSave()`를 부르고, `internalSave()`에는 `@Transactional`이 붙어 있다. 애노테이션이 붙어 있으니 그 메서드는 트랜잭션 안에서 돈다 — 지금 이렇게 읽고 있을 텐데, 이 두 문장 사이에는 아무 관계가 없다.

말로 반박하는 것보다 지금 프로젝트에서 확인하는 게 빠르다. 설정 한 줄이면 된다.

```properties
logging.level.org.springframework.transaction.interceptor=TRACE
```

다른 빈에서 `orderService.internalSave()`로 부르면 로그에 이 줄이 찍힌다.

```
TRACE o.s.t.i.TransactionInterceptor : Getting transaction for [com.x.OrderService.internalSave]
```

같은 클래스 안에서 `this.internalSave()`로 부르면 **그 줄이 아예 안 찍힌다.** 롤백이 실패한 게 아니라 트랜잭션이 시작된 적이 없다. 실패한 기록이 없으니 장애 분석 때도 안 보인다.

코드 안에서 직접 보고 싶으면 한 줄 더 짧다.

```java
@Transactional
public void internalSave() {
    // 외부 호출: true / 같은 클래스 내부 호출: false
    System.out.println(TransactionSynchronizationManager.isActualTransactionActive());
}
```

## 컨테이너가 들고 있는 건 당신이 만든 그 객체가 아니다

`OrderService`에 `@Transactional`이 하나라도 붙으면, 컨테이너에 등록된 `OrderService` 빈은 당신이 작성한 클래스의 인스턴스가 **아니다.** 그 인스턴스를 안에 품은 별도의 객체다. 주입받아서 찍어보면 바로 나온다.

```java
@Autowired OrderService orderService;

System.out.println(orderService.getClass());
// class com.x.OrderService$$SpringCGLIB$$0
```

이 프록시를 언제, 누가 만들어 원본 자리에 끼워 넣는지는 [Bean 생명주기 편](/learning-lab/digest/2026-09-11-bean-lifecycle-beanpostprocessor/)에서 다뤘다. 여기서 필요한 건 결과 하나다 — **객체가 두 개 있다.**

- **프록시** — 컨테이너에 등록돼 있고, 다른 빈들이 주입받는 쪽. 트랜잭션 시작·커밋 코드는 오직 여기에만 있다.
- **원본(target)** — 프록시가 안에 들고 있는, 당신이 쓴 코드 그대로의 인스턴스. 어드바이스에 대해 아무것도 모른다.

프록시가 하는 일을 펼치면 이렇다.

```java
// CGLIB 프록시가 실제로 하는 일 (개념적으로)
class OrderService$$SpringCGLIB$$0 extends OrderService {
    private final OrderService target; // 진짜 당신의 객체

    @Override public void internalSave() {
        TransactionStatus tx = tm.getTransaction(...);
        try { target.internalSave(); tm.commit(tx); }
        catch (RuntimeException e) { tm.rollback(tx); throw e; }
    }
}
```

어드바이스는 클래스에 발라진 게 아니라 **프록시를 통과하는 길목에 놓여 있다.** 그리고 원본 코드 안의 `this`는 언제나 `target`이지 프록시가 아니다. `this.internalSave()`는 길목 옆으로 비켜 간다. `@Transactional`이든 `@Cacheable`이든 `@Async`든 `@Retryable`이든, 걸리는 자리가 같으니 비켜 가는 방식도 같다.

## 프록시 종류를 바꿔도 이건 안 풀린다

"인터페이스를 빼면", "CGLIB으로 바꾸면" 해결되지 않을까 하는 기대가 흔한데 축이 다르다. JDK 동적 프록시든 CGLIB이든 **원본 앞에 객체를 하나 더 세우는 방식**이라는 점은 같고, 원본 안의 `this`는 어느 쪽에서도 그 객체가 아니다.

Spring Boot는 2.0부터 `spring.aop.proxy-target-class` 기본값이 `true`라 인터페이스가 있어도 CGLIB을 쓴다. 이건 프록시 **타입**이 갈리는 조건이지, self-invocation이 걸리느냐를 가르는 조건이 아니다. 둘은 자주 같이 외워지지만 서로 무관하다.

진짜 경계선은 프록시 종류가 아니라 **프록시를 쓰느냐 안 쓰느냐**다. AspectJ의 컴파일·로드타임 위빙은 객체를 하나 더 세우지 않고 `internalSave()`의 바이트코드 자체에 어드바이스를 심는다. 심는 자리가 "호출 경로"가 아니라 "메서드 본문"이라서 `this.internalSave()`도 걸린다.

그러니까 Spring AOP에서 self-invocation이 안 먹는 건 버그도 미완성도 아니라 **프록시 방식의 정의에서 바로 따라 나오는 결과**다.

## 인터뷰에서 이렇게 나온다

**"`@Transactional`을 붙였는데 롤백이 안 됩니다. 무엇부터 확인하시겠어요?"**

<details markdown="1">
<summary>답 확인</summary>

예외 타입(checked 예외는 기본 롤백 대상이 아니다)을 먼저 말하고 싶어지지만, 그건 트랜잭션이 열린 뒤의 문제다. 그 앞을 먼저 본다 — `TransactionInterceptor` 로그를 TRACE로 켜서 `Getting transaction for ...` 줄이 찍히는지 확인한다. 안 찍히면 트랜잭션이 시작조차 안 된 것이고, 그렇다면 그 메서드가 같은 클래스 안에서 `this`로 호출되고 있는지를 의심한다.

</details>

**"프록시를 CGLIB으로 바꾸면 self-invocation이 해결되나요?"**

<details markdown="1">
<summary>답 확인</summary>

안 된다. JDK 동적 프록시와 CGLIB은 프록시 객체를 어떻게 만드느냐(인터페이스 구현 vs 서브클래싱)만 다를 뿐, 둘 다 원본 앞에 별도 객체를 세우는 구조라서 원본 안의 `this` 호출은 어느 쪽도 가로채지 못한다. 이 문제 자체를 없애려면 프록시를 안 쓰는 방식, 즉 AspectJ 위빙으로 가야 한다. 위빙은 메서드 본문에 어드바이스를 직접 심기 때문에 호출 경로와 무관하게 걸린다.

</details>

## 한 줄 요약

> 어드바이스는 클래스에 붙는 게 아니라 프록시를 통과하는 호출 경로에 놓인다 — 그래서 `@Transactional`이 도느냐는 "어디에 붙였는가"가 아니라 "어떻게 호출했는가"로 정해진다.

---

## 나머지 넷은 `this.`로 시작하지도 않는다

앞 파트의 self-invocation은 프록시가 안 걸리는 다섯 경우 중 가장 흔한 하나일 뿐이다. 나머지 넷은 호출부에 `this`가 보이지도 않아서 코드 리뷰에서 더 안 잡힌다.

- **`private` 메서드** — 외부에서 부를 방법 자체가 없다. `private` 메서드에 도달하는 경로는 같은 객체 안에서 부르는 길뿐이고, 그건 이미 프록시를 지난 뒤다. Spring은 이걸 예외로 알려주지 않고 **조용히 무시한다.**
- **`static` 메서드** — `OrderService.foo()`는 어떤 인스턴스도 거치지 않는다. 주입받은 프록시 참조가 개입할 자리가 없다. (같은 이유로 `new OrderService()`로 직접 만든 객체도 빈이 아니니 감싸줄 사람이 없다.)
- **생성자 안에서의 호출** — 생성자가 도는 시점에는 프록시가 아직 존재하지 않는다. 프록시는 빈이 초기화된 **뒤에** `BeanPostProcessor`가 씌우기 때문이다([Bean 생명주기 편](/learning-lab/digest/2026-09-11-bean-lifecycle-beanpostprocessor/)). 생성자에서 부른 자기 메서드는 시점상 프록시를 거칠 방법이 없다.
- **`final` 메서드** — 여기만 결이 다르다. 호출은 프록시 객체까지 정상적으로 도착하는데, 프록시가 그 메서드를 오버라이드할 수 없어 **프록시가 상속받은 원본 코드가 프록시 인스턴스 위에서 그대로 실행된다.** 어드바이스도 안 걸리고 `target`으로 위임도 안 된다.

> 프록시는 "빈으로 주입받아 호출한 경로"에만 걸린다. 원본 객체 안에서 일어나는 호출은 프록시를 거치지 않는다는 원칙 하나만 정확히 기억하면 위 다섯 가지가 전부 같은 이유로 설명된다.

## `final`이 제일 고약한 이유 — 조용히 무시가 아니라 `NullPointerException`

`final` 메서드는 "어드바이스가 안 걸린다"에서 끝나지 않는다. Spring은 CGLIB 프록시 인스턴스를 Objenesis로 만들기 때문에 **생성자를 호출하지 않는다.** 의존성은 `target`에만 주입돼 있고 프록시 인스턴스의 필드는 전부 `null`이다. 평소엔 모든 메서드가 `target`으로 위임되니 문제가 없지만, `final` 메서드는 위임되지 않고 프록시 인스턴스 위에서 실행된다 — 그 안에서 필드를 건드리는 순간 `NullPointerException`이 난다.

Spring이 기동할 때 이걸 로그로 알려주는데, 대부분 그냥 지나간다. `org.springframework.aop.framework.CglibAopProxy`를 INFO 이상으로 켜두고 찾아보면 된다.

```
INFO o.s.a.f.CglibAopProxy : Final method [public final void com.x.OrderService.save()]
cannot get proxied via CGLIB: Calls to this method will NOT be routed to the target
instance and might lead to NPEs against uninitialized fields in the proxy instance.
```

`final` **클래스**면 이야기가 또 다르다. 상속 자체가 안 되니 프록시를 만들 수 없어서, 조용히 넘어가지 않고 기동이 `AopConfigException`으로 죽는다. Kotlin에서 클래스와 메서드가 기본 `final`이라 `kotlin-spring` 플러그인으로 `open`을 붙여주는 이유가 정확히 이것이다.

| 경우 | 실제로 일어나는 일 | 언제 발견되나 |
|---|---|---|
| `private` / `static` / 생성자 호출 | 어드바이스만 조용히 빠짐 | 운영에서 데이터 불일치로 |
| `final` 메서드 | 어드바이스 빠짐 + 프록시 필드 `null` | 기동 로그(INFO) 또는 첫 호출 NPE |
| `final` 클래스 | 프록시 생성 실패 | 기동 즉시 실패 |

## 어디까지가 되고 어디부터 안 되는지 — 버전이 갈리는 자리

"`@Transactional`은 `public` 메서드에만 걸린다"는 문장은 이제 반만 맞다. **Spring Framework 6.0부터 클래스 기반(CGLIB) 프록시에서는 `protected`와 package-private 메서드도 어드바이스 대상이다.** 인터페이스 기반(JDK 동적 프록시)이면 여전히 인터페이스에 선언된 `public` 메서드만 걸리고, `private`는 어느 버전에서도 안 된다(오버라이드가 불가능하다는 사실은 안 바뀌므로).

Boot 3.x는 Framework 6.x이고 프록시 기본값이 CGLIB이니, 실무 코드 대부분은 "`public`만"이 아니라 "`private`만 빼고"가 맞다. 5.x에서 올라온 팀이라면 이 지점이 바뀌었다는 걸 모르는 채로 면접에서 옛 답을 말하기 쉽다.

반대 방향 경계도 하나 있다. `spring.aop.proxy-target-class=false`로 JDK 프록시를 강제한 환경에서 인터페이스를 가진 빈을 **구체 클래스 타입으로** 주입받으면 `ClassCastException`이 난다. 프록시가 인터페이스만 구현한 객체라 원본 클래스 타입이 아니기 때문이다. CGLIB 기본값에서는 프록시가 원본의 서브클래스라 이 문제가 안 보인다.

## 그래서 실무에서는 어떻게 빠져나오나

<details markdown="1">
<summary>`AopContext.currentProxy()`와, 그게 권장되지 않는 이유</summary>

`@EnableAspectJAutoProxy(exposeProxy = true)`를 켜면 현재 처리 중인 프록시를 스레드 로컬에 노출시켜준다.

```java
@Transactional
public void outer() {
    ((OrderService) AopContext.currentProxy()).inner();
}
```

동작은 하지만 세 가지가 걸린다.

1. 비즈니스 코드에 Spring AOP API 의존이 그대로 드러난다.
2. `exposeProxy=true`를 안 켜면 `IllegalStateException`이 나는데, 컴파일 타임에 안 잡힌다.
3. 캐스팅 타입이 프록시 종류에 묶여 있어 리팩터링에 취약하다.

자기 자신을 `@Lazy`로 주입받아 부르는 방법도 같은 문제를 피해 가긴 하지만, 결국 "프록시 참조를 어떻게든 손에 넣겠다"는 우회다. 구조적으로 맞는 답은 `inner()`를 별도 빈으로 분리해 **호출이 자연스럽게 프록시를 거치게 만드는 것**이다. 그러면 self-invocation이 발생할 자리 자체가 없어진다.

</details>

## 인터뷰에서 이렇게 나온다

**"AOP 어드바이스가 안 걸리는 경우를 아는 대로 말해보세요."**

<details markdown="1">
<summary>답 확인</summary>

다섯 개를 나열하지 말고 원리 하나로 묶어서 답한다 — 어드바이스는 프록시에만 있고, 프록시는 빈으로 주입받은 참조를 통해 호출할 때만 거치게 된다. 그래서 `private`(외부에서 부를 경로가 없음), `static`(인스턴스를 안 거침), 생성자 안 호출(그 시점엔 프록시가 아직 없음), `final`(프록시가 오버라이드 못 함), self-invocation(`this`는 원본) 다섯 가지가 전부 같은 이유로 설명된다. `final`만은 호출이 프록시까지 도착한다는 점이 다른데, 오버라이드가 안 돼 가로채지 못하고 `target`으로 위임도 안 되기 때문에 프록시의 빈 필드를 건드려 NPE까지 갈 수 있다고 덧붙이면 된다.

</details>

**"`@Transactional`은 `public` 메서드에만 붙일 수 있나요?"**

<details markdown="1">
<summary>답 확인</summary>

Spring 6.0(Boot 3.x)부터 클래스 기반 프록시에서는 `protected`와 package-private 메서드에도 걸린다. 인터페이스 기반 JDK 프록시를 쓰면 인터페이스에 선언된 `public` 메서드만 대상이다. `private`는 어떤 조합에서도 안 되는데, 프록시가 오버라이드할 수 없는 메서드라서 그렇다.

</details>

## 한 줄 요약

> "이 호출이 프록시를 거쳤는가" 한 질문으로 다섯 경우가 전부 갈린다 — `private`·`static`·생성자 호출은 애초에 프록시를 지나는 경로가 아니고, `final`은 프록시까지 가서도 가로채지 못하며, self-invocation은 `this`로 경로를 스스로 건너뛴다.
