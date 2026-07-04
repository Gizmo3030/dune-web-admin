'use strict';

const { execFile } = require('child_process');
const config = require('./config');
const { bgControlScript } = require('./paths');
const audit = require('./audit');

// The ONLY actions that may ever be passed to PowerShell. Web input is matched
// against this list before spawning anything, so no arbitrary command can flow
// through to the shell.
const ALLOWED_ACTIONS = ['status', 'start', 'stop', 'restart'];

function isAllowed(action) {
  return ALLOWED_ACTIONS.includes(action);
}

function run(action, { timeoutSeconds } = {}) {
  return new Promise((resolve, reject) => {
    if (!isAllowed(action)) {
      return reject(new Error(`Unknown action: ${action}`));
    }
    const timeout =
      (timeoutSeconds ||
        (action === 'status' ? config.statusTimeoutSeconds : config.actionTimeoutSeconds) ||
        240) * 1000;

    const args = [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy', 'Bypass',
      '-File', bgControlScript,
      '-Action', action,
      '-VmName', config.vmName || 'dune-awakening',
    ];

    execFile(
      'powershell.exe',
      args,
      { timeout, windowsHide: true, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout, stderr) => {
        const raw = (stdout || '').trim();
        // The script always tries to emit one JSON object on stdout.
        if (raw) {
          try {
            return resolve(JSON.parse(raw));
          } catch (parseErr) {
            return reject(
              new Error(
                `Could not parse backend output: ${parseErr.message}. Raw: ${raw.slice(0, 500)}`
              )
            );
          }
        }
        if (err && err.killed) {
          return reject(new Error(`Backend timed out after ${timeout / 1000}s running "${action}".`));
        }
        return reject(
          new Error(
            `Backend produced no output. ${(stderr || '').trim() || (err && err.message) || 'Unknown error.'}`
          )
        );
      }
    );
  });
}

// --- Background job tracking ---------------------------------------------
// start/stop/restart can take longer than a reverse proxy's response timeout,
// so we run them in the background (fire-and-forget) and let the client poll
// this job state instead of holding the HTTP request open.
let currentJob = null;

function getJob() {
  return currentJob;
}

function startAction(name, meta = {}) {
  if (!isAllowed(name) || name === 'status') {
    throw new Error(`Action "${name}" is not allowed.`);
  }
  if (currentJob && currentJob.state === 'running') {
    return currentJob; // one at a time; caller can poll the existing job
  }
  const job = {
    action: name,
    state: 'running',
    by: meta.by || null,
    startedAt: Date.now(),
    finishedAt: null,
    ok: null,
    output: null,
    error: null,
  };
  currentJob = job;
  run(name)
    .then((result) => {
      job.state = result.ok ? 'done' : 'error';
      job.ok = !!result.ok;
      job.output = result.output || result.status || null;
      job.error = result.reason || result.error || null;
      job.finishedAt = Date.now();
      audit.record({ event: 'action_done', action: name, username: job.by, ok: job.ok, reason: job.error });
    })
    .catch((err) => {
      job.state = 'error';
      job.ok = false;
      job.error = err.message;
      job.finishedAt = Date.now();
      audit.record({ event: 'action_error', action: name, username: job.by, error: err.message });
    });
  return job;
}

module.exports = { ALLOWED_ACTIONS, isAllowed, run, startAction, getJob };
