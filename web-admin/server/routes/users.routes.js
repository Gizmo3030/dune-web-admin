'use strict';

const express = require('express');
const users = require('../users');
const audit = require('../audit');
const { requireAuth, requireAdmin, verifyCsrf } = require('../auth');

const router = express.Router();

// Every user-management route requires an authenticated admin. Guards are
// attached per-route (not via router.use) so this root-mounted router does not
// intercept unrelated requests like static pages.
const adminGuards = [requireAuth, requireAdmin];

router.get('/api/users', adminGuards, (req, res) => {
  res.json({ users: users.list() });
});

router.post('/api/users', adminGuards, verifyCsrf, (req, res) => {
  const { username, password, role } = req.body || {};
  try {
    const created = users.create({ username, password, role });
    audit.record({ event: 'user_create', by: req.session.user.username, username: created.username, role: created.role });
    return res.status(201).json({ ok: true, user: created });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

router.post('/api/users/:username/password', adminGuards, verifyCsrf, (req, res) => {
  const { password } = req.body || {};
  try {
    users.setPassword(req.params.username, password);
    audit.record({ event: 'user_reset_password', by: req.session.user.username, username: req.params.username });
    return res.json({ ok: true });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

router.post('/api/users/:username/role', adminGuards, verifyCsrf, (req, res) => {
  const { role } = req.body || {};
  const target = users.findByName(req.params.username);
  if (!target) return res.status(404).json({ error: 'User not found.' });
  // Don't allow demoting the last remaining admin (would lock everyone out of user management).
  if (target.role === 'admin' && role !== 'admin' && users.adminCount() <= 1) {
    return res.status(400).json({ error: 'Cannot demote the last admin.' });
  }
  try {
    users.setRole(req.params.username, role);
    audit.record({ event: 'user_set_role', by: req.session.user.username, username: req.params.username, role });
    return res.json({ ok: true });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

router.delete('/api/users/:username', adminGuards, verifyCsrf, (req, res) => {
  const target = users.findByName(req.params.username);
  if (!target) return res.status(404).json({ error: 'User not found.' });
  if (target.role === 'admin' && users.adminCount() <= 1) {
    return res.status(400).json({ error: 'Cannot delete the last admin.' });
  }
  try {
    users.remove(req.params.username);
    audit.record({ event: 'user_delete', by: req.session.user.username, username: req.params.username });
    return res.json({ ok: true });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

module.exports = router;
