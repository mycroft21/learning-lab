---
layout: default
title: 홈
---

<div class="hero">
  <h1>mycroft의 학습 기록</h1>
  <p class="tagline">
    실무와 스터디에서 익힌 개념·패턴·트러블슈팅을 정리합니다.
    회사 식별 정보는 모두 제거하고 일반화한 형태로 씁니다.
  </p>
</div>

## 최근 글

<ul class="post-list">
{% for post in site.posts limit:5 %}
  <li>
    <span class="post-meta">{{ post.date | date: "%Y.%m.%d" }}</span>
    <span class="post-tag post-tag-{{ post.type }}">{{ post.type }}</span>
    <h3><a class="post-link" href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
  </li>
{% endfor %}
</ul>

<p><a href="{{ '/posts/' | relative_url }}">전체 글 보기 →</a></p>
