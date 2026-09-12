---
icon: fas fa-mug-hot
order: 0
title: Digest
---

출퇴근길에 읽는 브리핑. 뉴스는 그날 것만 보이고 쌓이지 않으며, 딥다이브는 주제별로 아래에 남는다.

{% assign today = site.data.today %}
{% if today and today.news %}

## 오늘의 뉴스

<p class="text-muted">{{ today.date }}{% if today.note %} · {{ today.note }}{% endif %}</p>

{% for group in today.news %}
<h3>{{ group.category }}</h3>
<ul>
{% for item in group.items %}
  <li>
    {% if item.url %}<a href="{{ item.url }}" target="_blank" rel="noopener">{{ item.text }}</a>{% else %}{{ item.text }}{% endif %}
    {% if item.source %}<br><small class="text-muted">{{ item.source }}</small>{% endif %}
  </li>
{% endfor %}
</ul>
{% endfor %}
{% endif %}

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
