---
layout: page
title: Posts
permalink: /posts/
---

{% assign featured = site.posts | where: "featured", true %}
{% assign concepts = site.posts | where: "type", "concept" %}
{% assign insights = site.posts | where: "type", "insight" %}

{% if featured.size > 0 %}
<h2 class="post-list-heading">하이라이트</h2>
<ul class="post-list">
{% for post in featured %}
  <li>
    <span class="post-meta">{{ post.date | date: "%Y.%m.%d" }}</span>
    <span class="post-tag post-tag-{{ post.type }}">{{ post.type }}</span>
    <h3><a class="post-link" href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
  </li>
{% endfor %}
</ul>
{% endif %}

<h2 class="post-list-heading">Concept — 공부해서 안 것</h2>
<ul class="post-list">
{% for post in concepts %}
  <li>
    <span class="post-meta">{{ post.date | date: "%Y.%m.%d" }}</span>
    <h3><a class="post-link" href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
  </li>
{% endfor %}
</ul>

<h2 class="post-list-heading">Insight — 겪어서 안 것</h2>
<ul class="post-list">
{% for post in insights %}
  <li>
    <span class="post-meta">{{ post.date | date: "%Y.%m.%d" }}</span>
    <h3><a class="post-link" href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
  </li>
{% endfor %}
</ul>
