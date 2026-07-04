'use strict';

const fs = require('fs');
const { auditFile } = require('./paths');

// Append-only audit trail: one JSON object per line.
function record(entry) {
  const line = JSON.stringify(Object.assign({ ts: new Date().toISOString() }, entry)) + '\n';
  try {
    fs.appendFileSync(auditFile, line);
  } catch (err) {
    // Never let audit logging break a request.
    console.error('audit write failed:', err.message);
  }
}

module.exports = { record };
