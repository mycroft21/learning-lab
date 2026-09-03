# Chirpy 테마 이식 TODO

목표: minima → Chirpy 베이스(구조/기능) + Serif 톤(디자인).
방식: `feat/chirpy-theme` 브랜치, Chirpy starter 복사(B), 로컬 확인 후 머지.
사이트: mycroft21.github.io/learning-lab (프로젝트 사이트, baseurl=/learning-lab)

## Phase 0 — 준비

- [x] feat/chirpy-theme 브랜치 생성
- [x] 기존 콘텐츠 백업 위치 확인 (main 그대로 살아있음, /tmp에 tar 백업)

## Phase 1 — Chirpy 골격 (기능)

- [x] Chirpy starter 파일 확보 (기존 _posts/_data/커스텀은 보존)
- [x] _config.yml: baseurl=/learning-lab, title/description/url, 프로필 세팅
- [x] 기존 8개 글 _posts 이동 — front matter 호환 확인
- [x] featured: true → pin: true 마이그레이션
- [x] concept/insight 분류 → Chirpy categories 매핑 확인 (categories 그대로 유지)
- [x] about.md 이식 → _tabs/about.md (_data/profile.yml 렌더링 유지)
- [x] resume.md 이식 (숨김 페이지 유지, permalink /resume/)
- [x] 로컬 `bundle exec jekyll build` 성공 — 전체 페이지 렌더 확인 ✅게이트 통과
- [ ] 로컬 `jekyll serve`로 눈으로 최종 확인 (사용자)

## Phase 2 — 배포 (되돌리기 주의)

- [ ] .github/workflows/ Jekyll(Chirpy) 빌드 액션 추가
- [ ] GitHub Pages 소스를 "Actions"로 전환 (Settings) — ⚠️ 사용자 직접
- [ ] 브랜치 머지 후 실제 배포 확인 ✅게이트

## Phase 3 — Serif 톤 (디자인)

- [ ] _sass 오버라이드: serif 폰트
- [ ] Serif풍 컬러 팔레트 (액센트/배경)
- [ ] 여백/타이포/라인하이트 조정
- [ ] 홈 히어로 섹션 (Serif풍)
- [ ] 다크모드 톤 확인 ✅게이트

## 환경 메모

- Ruby 3.4.10 (brew `ruby@3.4`, Chirpy 7.6은 Ruby ~> 3.1 요구 — 4.0 불가)
- PATH: ~/.zshrc 하단에 ruby@3.4 + gems/3.4.0/bin 추가함
- 로컬 실행: `export PATH="/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"` 후 `bundle exec jekyll serve`
- (정리 대기) 실수로 설치된 ruby 4.0 — 필요시 `brew uninstall ruby`

## 열린 결정

- study/ 빈 디렉토리 처리 (삭제)
- baseurl 때문에 기존 링크(relative_url) 깨지는지 점검
- _data/profile.yml 렌더링을 Chirpy 페이지 레이아웃에 얹는 방식
