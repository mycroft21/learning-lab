# learning-lab

기술 학습 아카이브. 실무와 스터디에서 익힌 개념·패턴·트러블슈팅을 주제별로 정리한다.

> 모든 노트는 회사/프로젝트 식별 정보를 제거하고 일반화한 형태로 작성한다.

## 목차

<!-- INDEX:START -->
## 개념 (concept)

- [CQRS 데이터 동기화 지연 해결법](study/architecture/cqrs-sync-delay.md)
- [서버 스케일링 기초 — 왜 수평 확장인가부터 DB 병목까지](study/architecture/server-scaling-fundamentals.md)
- [NAT와 방화벽 기초 — 방화벽 룰 문서를 읽는 관점](study/network/nat-firewall-basics.md)

## 실무 경험 (insight)

- [대규모 아키텍처 설계에서 "성공 경로"보다 "실패 경로"가 본질이다](study/architecture/failure-path-over-success-path.md)
- [웹 취약점 진단(모의해킹) 조치 실무 — 유형별 원리·대책과 관통 교훈](study/security/web-vuln-remediation.md)
- [정보보호 인증(ISMS 계열) 대응 실무 — 개인정보·계정이력·웹취약점](study/security/isms-compliance-experience.md)
<!-- INDEX:END -->

## 구조

```
learning-lab/
├── topics/            # 실무에서 배운 것 (주제별)
│   ├── jpa/
│   ├── architecture/
│   ├── batch/
│   ├── database/
│   └── ...
├── study/             # 스터디/개인 학습 (책, 강의, 사이드)
│   └── ...
└── README.md          # 이 파일 (목차 자동 갱신)
```

## 분류 기준

| 디렉토리 | 용도 |
|----------|------|
| `topics/` | 실무 작업 중 배운 개념·패턴을 일반화한 노트 |
| `study/` | 스터디, 책, 강의 등 별도 학습 세션 정리 |

## 작성 원칙

- 회사명·프로젝트명·테이블·컬럼·도메인 코드 등 식별 정보 금지
- 직접 만든 예제 코드 또는 공개 문서로 설명 가능한 수준만
- 각 노트 상단에 `한 줄 요약` + `배운 맥락(일반화)` 포함
