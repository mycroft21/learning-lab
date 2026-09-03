---
layout: post
title: "CQRS 데이터 동기화 지연(Eventual Consistency) 해결법"
date: 2026-06-10
categories: [concept]
tags: [architecture, cqrs, database, eventual-consistency]
type: concept
source: study
---

> 한 줄 요약: CQRS에서 쓰기 DB와 읽기 DB의 동기화 지연은 UI 트릭 → 본인 쓰기 보장 → 버전 트래킹 → CDC 인프라 순으로, 정합성 요구 수준에 맞춰 골라 쓴다.

## 배운 맥락

CQRS(Command Query Responsibility Segregation)에서 쓰기 모델(Command)과 읽기 모델(Query)을 분리하면,
두 저장소 사이에 동기화 지연(replication delay, 수백 ms~수 초)이 생긴다.
이 찰나에 사용자가 새로고침하면 "방금 쓴 데이터가 안 보이는" 문제가 발생한다.
이 결과적 일관성(eventual consistency)의 간극을 메우는 4가지 실무 해법.

## 해결책 4가지

### 1. UI/UX 트릭 (가성비 최고)

인프라를 안 건드리고 클라이언트에서 지연을 감춘다.

- **낙관적 업데이트(Optimistic Update)**: 요청 성공을 가정하고 화면을 먼저 갱신. 인스타 '좋아요'가 대표 예시. 즉시 하트 켜지고 뒷단에서 비동기 동기화.
- **인위적 지연**: 등록 후 목록으로 리다이렉트할 때 0.5초 로딩 애니메이션을 의도적으로 띄워, 그 사이 백그라운드 동기화를 완료.

### 2. 본인 쓰기 즉시 반영 (Read-Your-Own-Writes)

내가 쓴 데이터는 나에게만 즉시 보이도록 보장.

- 글 등록 시 쓰기 DB 저장 + Redis에 `user:{id}:recent_post` 임시 키를 짧은 TTL(5~10초)로 캐싱.
- 본인 목록 조회 시, 읽기 DB 결과 + Redis 임시 데이터를 머지해서 응답.
- 다른 사용자는 지연 있는 읽기 DB를 그대로 봄(정상). TTL 만료 즈음 읽기 DB 동기화가 끝나 자연스럽게 정합성 회복.

### 3. 버전 트래킹 + 폴링 (엄격한 정합성)

금융/정산처럼 정밀한 도메인용.

- 쓰기 성공 시 서버가 최신 버전(`version=45`)을 응답에 실어줌.
- 클라이언트는 읽기 API 호출 시 `X-Expected-Version: 45`를 함께 전송.
- 조회 서버는 읽기 DB 버전이 기대 버전보다 낮으면 "아직 지연 중"으로 판단 → 클라이언트에 알림.
- 클라이언트는 스피너 돌리며 짧게 폴링(재조회)하며 대기.

### 4. CDC + Kafka 파이프라인 (지연 시간 자체 최소화)

지연을 초 단위 → 수십 ms로 줄이는 정공법.

- **CDC(Change Data Capture)**: Debezium이 쓰기 DB의 커밋 로그(MySQL Binlog 등)를 실시간 감시, 커밋 순간 이벤트를 Kafka로 발행.
- **Kafka 최적화**: 컨슈머 파티션 수 증가 + 병렬 처리로 소비 병목 제거.

```text
[RDBMS] --(Binlog)--> [Debezium/CDC] --> [Kafka] --> [Query DB (ES)]
```

## 정리

- 대부분의 서비스: **1(낙관적 업데이트) + 2(Redis 본인쓰기 보장)** 조합이 가성비 최적. 사용자엔 즉시 반응, 뒷단은 차분히 동기화.
- 결제/정산 등 정합성이 칼같아야 하는 도메인: **3(버전 트래킹)**으로 보장.
- 지연 자체를 줄여야 하면 **4(CDC/Kafka)**로 인프라 튜닝.
- 핵심: 동기화 지연은 없앨 수 없으니 "어디까지 사용자에게 감출지 / 어디는 정합성을 강제할지"를 도메인별로 결정하는 문제다.
