# learning-lab

기술 학습 아카이브. 실무와 스터디에서 익힌 개념·패턴·트러블슈팅을 기록한다.
Jekyll(Chirpy 테마) + GitHub Pages(Actions 빌드)로 발행되며, 자기소개/이력서 페이지도 함께 있다.

> 모든 글은 회사/프로젝트 식별 정보를 제거하고 일반화한 형태로 작성한다.

## 사이트

<https://mycroft21.github.io/learning-lab/>

- `/` — 홈 (하이라이트 + 최근 글)
- `/categories/` — concept / insight 등 카테고리별 글
- `/tags/` — 태그별 글
- `/archives/` — 날짜순 전체 글
- `/about/` — learning-lab 소개 + 프로필 요약
- `/resume/` — 이력서 상세 (네비게이션에는 안 뜨는 숨김 페이지, `/about/`과 홈에서 링크로 접근)

## 테마

[Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) 7.x 를 theme gem으로 사용한다.
디자인 커스텀(폰트·색·파비콘)은 `assets/css/jekyll-theme-chirpy.scss` 한 파일에 모여 있다.

- 폰트: Noto Serif KR (본문·제목 명조)
- 색: 그린 팔레트(세이지 `#6b8f71` / 민트 계열), 라이트 위주 + 다크 톤다운
- 파비콘: 이니셜 "m" (라이트/다크 테마 대응 SVG)

## 로컬에서 미리보기

Chirpy 7.x 는 Ruby 3.x 가 필요하다(4.x 불가). brew `ruby@3.4` 기준:

```bash
export PATH="/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"
bundle install
bundle exec jekyll serve
# baseurl 때문에 접속 주소는 http://localhost:4000/learning-lab/
```

(위 PATH는 `~/.zshrc` 하단에 등록돼 있어 새 터미널에서는 자동 적용된다.)

## 구조

```text
learning-lab/
├── _posts/            # 발행되는 글 (YYYY-MM-DD-kebab-title.md)
├── _tabs/             # 사이드바 네비 페이지 (about / categories / tags / archives)
├── _data/
│   └── profile.yml    # 자기소개/경력/기술스택 등 이력 데이터
│                       # _tabs/about.md 와 resume.md 가 여기서 렌더링 → 항상 동기화됨
├── _plugins/          # Chirpy 보조 플러그인 (posts-lastmod 등)
├── assets/
│   ├── css/jekyll-theme-chirpy.scss  # Chirpy 위 커스텀(폰트·색·프로필 스타일)
│   └── img/favicons/                 # 파비콘 세트 (테마 대응 SVG + PNG)
├── index.html         # 홈 (Chirpy home 레이아웃)
├── resume.md          # 이력서 상세 (숨김 페이지, permalink /resume/)
├── _config.yml        # Jekyll/Chirpy 설정 (baseurl=/learning-lab)
├── .github/workflows/pages-deploy.yml  # GitHub Actions 배포
├── Gemfile             # 의존성 (jekyll-theme-chirpy)
└── README.md
```

## 글 분류

각 글의 frontmatter에 `categories`(concept | insight), `tags`, `type`, `source`(study | work)를 표시한다.
`/categories/`·`/tags/` 페이지가 이 필드를 읽어 자동으로 분류해 보여준다.

- **concept** — 공부해서 안 것 (지식·이해·비교)
- **insight** — 겪어서 안 것 (실무 판단·통찰·트러블슈팅)

특히 서사가 뚜렷하거나 여러 개념을 하나로 꿰는 글은 frontmatter에 `pin: true`를 붙여
홈 상단에 고정 노출한다.

## 이력서 데이터

`_data/profile.yml` 하나에 프로필/일하는 방식/경력/학력/자격증/기술스택을 구조화해서 담아둔다.
이력이 바뀌면 이 파일만 고치면 `/about/`(요약)과 `/resume/`(상세) 둘 다 자동으로 갱신된다.

## 작성 원칙

- 회사명·프로젝트명·테이블·컬럼·도메인 코드 등 식별 정보 금지
- 재직 중인 회사의 내부 시스템 구조 세부(시스템명, 기술 구현 세부)는 이력서에서도 한 단계 더 일반화
- 직접 만든 예제 코드 또는 공개 문서로 설명 가능한 수준만
- 새 글은 `_posts/YYYY-MM-DD-kebab-title.md` 형식, frontmatter에 `layout: post`, `title`, `date`,
  `categories`, `tags`, `type`, `source` 포함 (필요 시 `pin: true`)

## 자동 발행

private 학습 아카이브(`learning-lab-private`)에서 월 1회 배치로 정제해 이 repo에 커밋된다.
절차는 `study-log` 스킬 참고.
