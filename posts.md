---
layout: page
title: Posts
permalink: /posts/
---

<ul class="post-list">
{% for post in site.posts %}
  <li>
    <span class="post-meta">{{ post.date | date: "%Y.%m.%d" }}</span>
    <span class="post-tag post-tag-{{ post.type }}">{{ post.type }}</span>
    <h3><a class="post-link" href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
  </li>
{% endfor %}
</ul>
