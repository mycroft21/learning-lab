# learning-lab

기술 학습 아카이브. 실무와 스터디에서 익힌 개념·패턴·트러블슈팅을 기록한다.
Jekyll + GitHub Pages로 발행되어 `_posts/`의 글이 그대로 블로그로 보인다.

> 모든 글은 회사/프로젝트 식별 정보를 제거하고 일반화한 형태로 작성한다.

## 사이트

GitHub Pages 활성화 후: `https://{username}.github.io/learning-lab/`

## 로컬에서 미리보기

```bash
bundle install
bundle exec jekyll serve
# http://localhost:4000
```

## 구조

```
learning-lab/
├── _posts/            # 발행되는 글 (YYYY-MM-DD-slug.md)
├── _config.yml        # Jekyll 설정
├── Gemfile             # 의존성 (jekyll, minima 테마)
└── README.md
```

## 글 분류

각 글의 frontmatter에 `type`(concept | insight)과 `source`(study | work)를 표시한다.

- **concept** — 공부해서 안 것 (지식·이해·비교)
- **insight** — 겪어서 안 것 (실무 판단·통찰·트러블슈팅)

## 작성 원칙

- 회사명·프로젝트명·테이블·컬럼·도메인 코드 등 식별 정보 금지
- 직접 만든 예제 코드 또는 공개 문서로 설명 가능한 수준만
- 새 글은 `_posts/YYYY-MM-DD-kebab-title.md` 형식, frontmatter에 `layout: post`, `title`, `date`, `categories`, `tags`, `type`, `source` 포함
