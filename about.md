---
layout: page
title: About
permalink: /about/
---

<div class="profile">
  <h1>{{ site.data.profile.profile.name }}</h1>
  <p class="role">{{ site.data.profile.profile.role }} · {{ site.data.profile.profile.experience }}</p>
</div>

<div class="profile-summary">
{{ site.data.profile.profile.summary }}
</div>

<div class="profile-section">
  <h2>일하는 방식</h2>
  <ul>
  {% for item in site.data.profile.working_style %}
    <li>{{ item }}</li>
  {% endfor %}
  </ul>
</div>

<div class="profile-section">
  <h2>연혁</h2>
  <ul class="timeline">
  {% for job in site.data.profile.experience %}
    <li><strong>{{ job.company }}</strong> <span class="period">{{ job.period }}</span> — {{ job.summary }}</li>
  {% endfor %}
  </ul>
</div>

<div class="profile-section">
  <h2>요즘 눈이 가는 것들</h2>
  <ul>
  {% for item in site.data.profile.interests %}
    <li><strong>{{ item.title }}</strong> — {{ item.body }}</li>
  {% endfor %}
  </ul>
</div>

<div class="profile-section">
  <h2>기술 스택</h2>
  <div class="skill-tags">
  {% for s in site.data.profile.skills %}
    <span class="skill-tag">{{ s }}</span>
  {% endfor %}
  </div>
</div>

<div class="profile-section">
  <h2>learning-lab</h2>
  <p>
    이 사이트는 실무와 스터디에서 익힌 개념·패턴·트러블슈팅을 기록하는 개인 학습 아카이브입니다.
  </p>
  <ul>
    <li><strong>concept</strong> 태그 글: 공부해서 알게 된 개념·지식·비교</li>
    <li><strong>insight</strong> 태그 글: 직접 겪으며 판단하고 얻은 실무 경험</li>
  </ul>
  <p>모든 글은 회사·프로젝트 식별 정보를 제거하고 일반화한 형태로 작성합니다.</p>
  <p><a href="{{ '/resume/' | relative_url }}">자세한 이력 보기 →</a></p>
</div>
