# learning-lab

기술 학습 아카이브. 실무와 스터디에서 익힌 개념·패턴·트러블슈팅을 기록한다.
Jekyll + GitHub Pages로 발행되며, 자기소개/이력서 페이지도 함께 있다.

> 모든 글은 회사/프로젝트 식별 정보를 제거하고 일반화한 형태로 작성한다.

## 사이트

<https://mycroft21.github.io/learning-lab/>

- `/` — 홈 (자기소개 요약 + 하이라이트 + 최근 글)
- `/posts/` — 전체 글 목록 (하이라이트 → concept → insight 순)
- `/about/` — learning-lab 소개 + 연혁 요약
- `/resume/` — 이력서 상세 (네비게이션에는 안 뜨는 숨김 페이지, `/about/`과 홈에서 링크로 접근)

## 로컬에서 미리보기

```bash
bundle install
bundle exec jekyll serve
# http://localhost:4000
```

## 구조

```
learning-lab/
├── _posts/            # 발행되는 글 (YYYY-MM-DD-kebab-title.md)
├── _data/
│   └── profile.yml    # 자기소개/경력/기술스택 등 이력 데이터
│                       # about.md와 resume.md가 여기서 렌더링 → 항상 동기화됨
├── assets/
│   └── main.scss      # minima 테마 위 커스텀 스타일
├── index.md           # 홈
├── about.md           # learning-lab 소개 (짧은 연혁 요약)
├── posts.md           # 전체 글 목록
├── resume.md          # 이력서 상세 (숨김 페이지)
├── _config.yml        # Jekyll 설정
├── Gemfile             # 의존성 (jekyll, minima 테마)
└── README.md
```

## 글 분류

각 글의 frontmatter에 `type`(concept | insight)과 `source`(study | work)를 표시한다.
`/posts/` 페이지가 이 필드를 읽어 실시간으로 섹션을 나눠 보여주므로, 목차를 수동으로 관리하지 않는다.

- **concept** — 공부해서 안 것 (지식·이해·비교)
- **insight** — 겪어서 안 것 (실무 판단·통찰·트러블슈팅)

특히 서사가 뚜렷하거나 여러 개념을 하나로 꿰는 글은 frontmatter에 `featured: true`를 붙여
홈/Posts 상단 하이라이트에 노출한다 (최대 5개 유지, 초과 시 가장 오래된 것부터 제외).

## 이력서 데이터

`_data/profile.yml` 하나에 프로필/일하는 방식/경력/학력/자격증/기술스택을 구조화해서 담아둔다.
이력이 바뀌면 이 파일만 고치면 `/about/`(요약)과 `/resume/`(상세) 둘 다 자동으로 갱신된다.

## 작성 원칙

- 회사명·프로젝트명·테이블·컬럼·도메인 코드 등 식별 정보 금지
- 재직 중인 회사의 내부 시스템 구조 세부(시스템명, 기술 구현 세부)는 이력서에서도 한 단계 더 일반화
- 직접 만든 예제 코드 또는 공개 문서로 설명 가능한 수준만
- 새 글은 `_posts/YYYY-MM-DD-kebab-title.md` 형식, frontmatter에 `layout: post`, `title`, `date`,
  `categories`, `tags`, `type`, `source` 포함 (필요 시 `featured: true`)

## 자동 발행

private 학습 아카이브(`learning-lab-private`)에서 월 1회 배치로 정제해 이 repo에 커밋된다.
절차는 `study-log` 스킬 참고.
