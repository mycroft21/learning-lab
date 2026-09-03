---
layout: page
title: Resume
permalink: /resume/
icon: fas fa-id-card
# _tabs/ 밖에 있으므로 네비게이션에는 노출되지 않음 (about/홈에서 링크로 접근)
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
  <h2>경력</h2>

  {% for job in site.data.profile.experience %}
  <div class="job">
    <h3>{{ job.company }}</h3>
    <p class="period">{{ job.period }} · {{ job.employment }}</p>

    {% for role in job.roles %}
    <div class="role">
      <h4>{{ role.title }}</h4>
      {% if role.period %}<p class="period">{{ role.period }}</p>{% endif %}
      <ul>
      {% for bullet in role.bullets %}
        <li>{{ bullet }}</li>
      {% endfor %}
      </ul>
      {% if role.skills %}
      <div class="skill-tags">
        {% for skill in role.skills %}
        <span class="skill-tag">{{ skill }}</span>
        {% endfor %}
      </div>
      {% endif %}
    </div>
    {% endfor %}
  </div>
  {% endfor %}
</div>

<div class="profile-section">
  <h2>학력</h2>
  <ul class="timeline">
  {% for edu in site.data.profile.education %}
    <li><strong>{{ edu.school }}</strong> <span class="period">{{ edu.period }}</span> — {{ edu.detail }}</li>
  {% endfor %}
  </ul>
</div>

<div class="profile-section">
  <h2>자격증 · 어학</h2>
  <ul>
  {% for c in site.data.profile.certifications %}
    <li>{{ c.name }} <span class="period">({{ c.date }})</span></li>
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
  <p><a href="{{ '/about/' | relative_url }}">← About으로</a> &middot; <a href="{{ '/' | relative_url }}">learning-lab 홈으로</a></p>
</div>
