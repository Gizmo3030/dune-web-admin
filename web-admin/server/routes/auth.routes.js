'use strict';

const express = require('express');
const rateLimit = require('express-rate-limit');
const users = require('../users');
const audit = require('../audit');
const config = require('../config');
const { ensureCsrfToken } = require('../auth');

const router = express.Router();

const rl = config.loginRateLimit || {};
const loginLimiter = rateLimit({
  windowMs: (rl.windowMinutes || 15) * 60 * 1000,
  max: rl.maxAttempts || 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts. Please wait a few minutes and try again.' },
});

// Who am I / bootstrap info for the frontend. Also seeds a CSRF token.
router.get('/api/me', (req, res) => {
  const csrfToken = ensureCsrfToken(req);
  if (req.session && req.session.user) {
    return res.json({ authenticated: true, user: req.session.user, csrfToken });
  }
  return res.json({ authenticated: false, csrfToken, needsSetup: users.count() === 0 });
});

router.post('/api/login', loginLimiter, (req, res) => {
  const { username, password } = req.body || {};
  const result = users.verify(username, password);
  if (!result) {
    audit.record({ event: 'login_failed', username: String(username || '').slice(0, 64), ip: req.ip });
    return res.status(401).json({ error: 'Invalid username or password.' });
  }
  // Prevent session fixation: regenerate the session on privilege change.
  req.session.regenerate((err) => {
    if (err) return res.status(500).json({ error: 'Could not start a session.' });
    req.session.user = result;
    ensureCsrfToken(req);
    audit.record({ event: 'login', username: result.username, role: result.role, ip: req.ip });
    return res.json({ ok: true, user: result, csrfToken: req.session.csrfToken });
  });
});

router.post('/api/logout', (req, res) => {
  const who = req.session && req.session.user ? req.session.user.username : null;
  req.session.destroy(() => {
    if (who) audit.record({ event: 'logout', username: who });
    res.clearCookie(config.sessionCookieName || 'dune_admin_sid');
    return res.json({ ok: true });
  });
});

module.exports = router;
