'use strict';

// Shared client helpers used by dashboard.html and users.html.
window.DA = (function () {
  let csrfToken = null;
  let currentUser = null;

  async function me() {
    const res = await fetch('/api/me');
    const data = await res.json();
    csrfToken = data.csrfToken || null;
    currentUser = data.user || null;
    if (!data.authenticated) {
      window.location.href = '/login.html';
      throw new Error('not authenticated');
    }
    return data;
  }

  async function apiGet(path) {
    const res = await fetch(path);
    if (res.status === 401) { window.location.href = '/login.html'; throw new Error('unauth'); }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
    return data;
  }

  async function apiSend(path, method, body) {
    const res = await fetch(path, {
      method,
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 401) { window.location.href = '/login.html'; throw new Error('unauth'); }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
    return data;
  }

  async function logout() {
    await fetch('/api/logout', { method: 'POST', headers: { 'X-CSRF-Token': csrfToken || '' } });
    window.location.href = '/login.html';
  }

  function renderTopbar(user) {
    const isAdmin = user.role === 'admin';
    return `
      <div class="brand"><span class="dot"></span> Dune Awakening Admin</div>
      <div class="topbar-right">
        <a href="/dashboard.html">Dashboard</a>
        ${isAdmin ? '<a href="/users.html">Accounts</a>' : ''}
        <span>${user.username}</span>
        <span class="role">${user.role}</span>
        <button id="logoutBtn">Sign out</button>
      </div>`;
  }

  function wireTopbar() {
    const btn = document.getElementById('logoutBtn');
    if (btn) btn.addEventListener('click', logout);
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  return { me, apiGet, apiSend, logout, renderTopbar, wireTopbar, escapeHtml,
           get user() { return currentUser; }, get csrf() { return csrfToken; } };
})();
