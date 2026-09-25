---
title: "트랜잭션 전파와 영속성 컨텍스트"
date: 2026-09-26
domain: jpa
slots: 1
parts_done: 1
tags: [jpa, transaction, persistence-context]
---

## 트랜잭션이 갈리면 영속성 컨텍스트도 갈린다고 알고 있다면

절반은 맞는다. 다만 그게 규칙이라서 맞는 게 아니라, 기본 설정에서 둘의 수명이 우연히 겹치도록 맞춰져 있어서 맞는다. 확인은 엔티티 동일성으로 한다.

```java
@Transactional
void outer() {
    Member a = em.find(Member.class, 1L);
    inner.loadInNewTransaction(1L);   // REQUIRES_NEW
    Member b = em.find(Member.class, 1L);
    // a == b 는 여전히 true — 바깥 컨텍스트는 그대로다
}
```

안쪽 메서드가 읽어온 인스턴스는 바깥의 `a`와 다른 객체다. 같은 식별자인데 인스턴스가 다르다는 건 **동일성을 보장하는 단위가 트랜잭션이 아니라 영속성 컨텍스트**라는 뜻이고, 여기서 둘이 별개의 개념이라는 게 드러난다. 같은 식별자면 같은 인스턴스라는 보장이 왜 영속성 컨텍스트의 본질인지는 [영속성 컨텍스트와 1차 캐시 편](/learning-lab/digest/2026-09-21-persistence-context-first-level-cache/)에서 다뤘다.

## 영속성 컨텍스트는 트랜잭션이 아니라 EntityManager에 묶인다

영속성 컨텍스트의 수명을 쥐고 있는 건 `EntityManager`다. 트랜잭션은 그 위에 얹히는 별개의 경계고, Spring이 하는 일은 `EntityManager`를 **스레드에 바인딩**해서 트랜잭션과 수명이 맞아떨어지게 만들어주는 것이다. 기본 설정에서는 트랜잭션이 시작될 때 `EntityManager`가 만들어지고 끝날 때 닫히므로 두 경계가 포개져 보인다.

이 구조를 잡으면 전파 옵션별 동작이 따라 나온다.

- **`REQUIRED`로 기존 트랜잭션에 참여** — 스레드에 이미 바인딩된 `EntityManager`를 그대로 쓴다. 같은 영속성 컨텍스트이므로 1차 캐시도 공유하고, 안쪽에서 수정한 엔티티가 바깥에서도 같은 인스턴스로 보인다.
- **`REQUIRES_NEW`로 새 트랜잭션 시작** — 기존 트랜잭션과 그 바인딩을 함께 보류(suspend)하고 새 `EntityManager`를 만든다. 새 영속성 컨텍스트이므로 1차 캐시도 변경 감지 대상도 완전히 따로 논다.

그래서 `REQUIRES_NEW` 안에서 엔티티를 수정하고 커밋하면, 바깥 컨텍스트가 들고 있던 같은 식별자의 인스턴스는 **그 변경을 모르는 낡은 상태로 남는다.** 바깥에서 그 엔티티를 다시 `find`해도 1차 캐시가 먼저 응답하므로 DB의 최신 값이 아니라 원래 읽었던 값이 나온다. 전파 옵션 자체가 물리 트랜잭션을 몇 개 만드는지는 [트랜잭션 전파 편](/learning-lab/digest/2026-09-13-transaction-propagation/)에서 다뤘다. 여기서는 그 위에 얹힌 영속성 컨텍스트 경계만 본다.

## OSIV가 켜지면 두 경계가 어긋난다

Spring Boot는 `spring.jpa.open-in-view`를 기본 `true`로 둔다. 이때는 HTTP 요청이 시작될 때 `EntityManager`가 먼저 바인딩되고, 이후 트랜잭션들이 그 위에 얹힌다. 트랜잭션이 커밋되고 끝나도 **영속성 컨텍스트는 요청이 끝날 때까지 살아 있다.**

여기서 나오는 함정이 하나 있다. 한 요청 안에서 트랜잭션 A가 엔티티를 읽고, 그 사이 다른 곳에서 그 행이 바뀌고, 다시 트랜잭션 B가 같은 엔티티를 읽으면 — B는 DB를 보지 않고 아직 살아 있는 1차 캐시를 본다. "새 트랜잭션이니 최신 값을 읽었겠지"가 깨지는 자리다.

자기 애플리케이션이 어느 쪽인지는 1분이면 확인된다.

```java
// 서로 다른 트랜잭션 경계에서 같은 식별자를 읽고 인스턴스를 비교한다
System.out.println(System.identityHashCode(memberFromTxA));
System.out.println(System.identityHashCode(memberFromTxB));
```

같은 값이면 두 트랜잭션이 하나의 영속성 컨텍스트를 공유하고 있는 것이고, 다르면 트랜잭션마다 새로 만들어지고 있는 것이다. 설정과 호출 경로에 따라 갈리므로, 문서를 믿기보다 직접 찍어보는 편이 빠르다.

## 인터뷰에서 이렇게 나온다

**"REQUIRES_NEW로 호출한 메서드에서 수정한 엔티티가 바깥 트랜잭션에는 왜 반영돼 보이지 않나요?"**

<details markdown="1">
<summary>답 확인</summary>

`REQUIRES_NEW`는 기존 트랜잭션과 함께 바인딩된 `EntityManager`까지 보류하고 새 `EntityManager`를 만들기 때문에 영속성 컨텍스트가 완전히 분리된다. 바깥 컨텍스트는 자기가 처음 읽은 인스턴스를 1차 캐시로 계속 들고 있으므로, 안쪽에서 커밋된 변경을 모른 채 낡은 상태를 유지한다. 다시 읽어도 1차 캐시가 먼저 응답하므로 최신 값을 보려면 컨텍스트를 비우거나(`clear`) 해당 엔티티를 `refresh` 해야 한다.

</details>

**"트랜잭션 경계와 영속성 컨텍스트 경계는 항상 같나요?"**

<details markdown="1">
<summary>답 확인</summary>

같지 않다. 영속성 컨텍스트는 `EntityManager`에 묶여 있고 트랜잭션은 그 위에 얹히는 별개의 경계인데, 기본 설정에서 둘의 수명이 맞춰져 있어 같아 보일 뿐이다. OSIV가 켜져 있으면 `EntityManager`가 요청 단위로 바인딩되어 여러 트랜잭션이 하나의 영속성 컨텍스트를 공유하게 되고, 그 순간 두 경계가 어긋난다.

</details>

## 한 줄 요약

> 영속성 컨텍스트는 트랜잭션이 아니라 `EntityManager`에 묶여 있고 Spring이 둘의 수명을 맞춰줄 뿐이라, `REQUIRES_NEW`가 캐시까지 갈라놓는 것도 OSIV가 여러 트랜잭션에 하나의 캐시를 물리는 것도 전부 "이 코드에서 EntityManager가 언제 만들어지는가" 하나로 결정된다.
