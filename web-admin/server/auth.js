'use strict';

const fs = require('fs');
const crypto = require('crypto');
const { sessionSecretFile } = require('./paths');

// --- Session secret: generate once, persist (gitignored), reuse thereafter ---
function getSessionSecret() {
  try {
    const existing = fs.readFileSync(sessionSecretFile, 'utf8').trim();
    if (existing) return existing;
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
  }
  const secret = crypto.randomBytes(48).toString('hex');
  fs.writeFileSync(sessionSecretFile, secret, { mode: 0o600 });
  return secret;
}

// --- CSRF: synchronizer token stored in the session ---
function ensureCsrfToken(req) {
  if (!req.session.csrfToken) {
    req.session.csrfToken = crypto.randomBytes(24).toString('hex');
  }
  return req.session.csrfToken;
}

function verifyCsrf(req, res, next) {
  const sent = req.get('x-csrf-token') || (req.body && req.body._csrf);
  const expected = req.session && req.session.csrfToken;
  if (!expected || !sent || sent !== expected) {
    return res.status(403).json({ error: 'Invalid or missing CSRF token. Reload the page and try again.' });
  }
  return next();
}

// --- Auth middleware ---
function requireAuth(req, res, next) {
  if (req.session && req.session.user) return next();
  // API calls always get a JSON 401; page navigations get redirected to login.
  if (req.path.startsWith('/api/')) {
    return res.status(401).json({ error: 'Not authenticated.' });
  }
  return res.redirect('/login.html');
}

function requireAdmin(req, res, next) {
  if (req.session && req.session.user && req.session.user.role === 'admin') return next();
  return res.status(403).json({ error: 'Admin role required.' });
}

module.exports = {
  getSessionSecret,
  ensureCsrfToken,
  verifyCsrf,
  requireAuth,
  requireAdmin,
};
