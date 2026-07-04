'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const dataDir = path.join(root, 'data');

// Ensure the (gitignored) data directory exists for the user store, session
// secret and audit log.
fs.mkdirSync(dataDir, { recursive: true });

module.exports = {
  root,
  dataDir,
  usersFile: path.join(dataDir, 'users.json'),
  sessionSecretFile: path.join(dataDir, 'session-secret'),
  auditFile: path.join(dataDir, 'audit.log'),
  bgControlScript: path.join(__dirname, 'ps', 'bg-control.ps1'),
  publicDir: path.join(root, 'public'),
};
