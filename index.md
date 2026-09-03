---
layout: default
title: 홈
---

<div class="hero">
  <h1>안녕하세요, mycroft입니다</h1>
  <p class="tagline">
    백엔드 개발자로 8년 넘게 이것저것 만들고 고치고 있습니다.
    새 도메인에 던져지면 일단 적응하고, 적응하고 나면 여기저기 흔들어보는 편입니다.
    여기는 그 과정에서 배운 것과, 배운 척했다가 나중에 아니었던 것들을 정리하는 공간입니다.
  </p>
  <p><a href="{{ '/resume/' | relative_url }}">이력서 둘러보기 →</a></p>
</div>

## 하이라이트

<ul class="post-list">
{% assign featured = site.posts | where: "featured", true %}
{% for post in featured %}
  <li>
    <span class="post-meta">{{ post.date | date: "%Y.%m.%d" }}</span>
    <span class="post-tag post-tag-{{ post.type }}">{{ post.type }}</span>
    <h3><a class="post-link" href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
  </li>
{% endfor %}
</ul>

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
