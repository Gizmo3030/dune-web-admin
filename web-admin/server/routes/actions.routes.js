'use strict';

const express = require('express');
const actions = require('../actions');
const audit = require('../audit');
const { requireAuth, verifyCsrf } = require('../auth');

const router = express.Router();

// Read-only status: safe for any logged-in user, no CSRF needed (GET).
router.get('/api/status', requireAuth, async (req, res) => {
  try {
    const result = await actions.run('status');
    return res.json(result);
  } catch (err) {
    return res.status(502).json({ ok: false, error: err.message });
  }
});

// Poll the current/last background action so the client doesn't hold a request
// open long enough to hit a proxy timeout.
router.get('/api/job', requireAuth, (req, res) => {
  const job = actions.getJob();
  if (!job) return res.json({ job: null });
  return res.json({
    job: {
      action: job.action,
      state: job.state,
      ok: job.ok,
      output: job.output,
      error: job.error,
      startedAt: job.startedAt,
      finishedAt: job.finishedAt,
    },
  });
});

// State-changing actions: start | stop | restart. Requires CSRF token.
// Fire-and-forget: kicks off the action and returns immediately (202). The
// client polls GET /api/job for completion.
router.post('/api/action/:name', requireAuth, verifyCsrf, (req, res) => {
  const name = req.params.name;
  if (name === 'status' || !actions.isAllowed(name)) {
    return res.status(400).json({ error: `Action "${name}" is not allowed.` });
  }
  const running = actions.getJob();
  if (running && running.state === 'running') {
    return res.status(409).json({ error: `An action ("${running.action}") is already running.`, action: running.action });
  }
  const who = req.session.user.username;
  audit.record({ event: 'action_start', action: name, username: who, ip: req.ip });
  actions.startAction(name, { by: who });
  return res.status(202).json({ started: true, action: name });
});

module.exports = router;
