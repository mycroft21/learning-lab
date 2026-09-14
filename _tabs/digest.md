---
icon: fas fa-mug-hot
order: 0
title: Digest
---

출퇴근길에 읽는 딥다이브. 주제 하나를 골라 원리 하나로 정리한 글이 아래에 쌓인다.
그날의 뉴스는 [홈](/learning-lab/)에 모아둔 소스에서 직접 읽는다.

## 딥다이브

{% assign entries = site.digest | sort: "date" | reverse %}
{% if entries.size > 0 %}
<ul>
{% for entry in entries %}
  <li>
    <a href="{{ entry.url | relative_url }}">{{ entry.title }}</a>
    <br>
    <small class="text-muted">
      {{ entry.date | date: "%Y-%m-%d" }}
      {% if entry.domain %}· {{ entry.domain }}{% endif %}
      {% if entry.slots and entry.slots > 1 %}· {{ entry.parts_done | default: 0 }}/{{ entry.slots }} 파트{% endif %}
    </small>
  </li>
{% endfor %}
</ul>
{% else %}
<p class="text-muted">아직 발행된 딥다이브가 없다.</p>
{% endif %}
