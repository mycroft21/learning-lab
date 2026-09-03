---
layout: page
title: Posts
permalink: /posts/
---

{% assign featured = site.posts | where: "featured", true %}
{% assign rest = site.posts | where_exp: "post", "post.featured != true" %}

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

<h2 class="post-list-heading">전체 글</h2>
{% endif %}

<ul class="post-list">
{% for post in rest %}
  <li>
    <span class="post-meta">{{ post.date | date: "%Y.%m.%d" }}</span>
    <span class="post-tag post-tag-{{ post.type }}">{{ post.type }}</span>
    <h3><a class="post-link" href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
  </li>
{% endfor %}
</ul>
