'use strict';

const fs = require('fs');
const path = require('path');

const configDir = path.join(__dirname, '..', 'config');

function readJsonIfExists(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    if (err.code === 'ENOENT') return {};
    throw new Error(`Failed to parse ${file}: ${err.message}`);
  }
}

// default.json is required; local.json (gitignored) optionally overrides it.
const defaults = readJsonIfExists(path.join(configDir, 'default.json'));
const local = readJsonIfExists(path.join(configDir, 'local.json'));

const config = Object.assign({}, defaults, local);

// Allow a couple of env overrides for convenience.
if (process.env.PORT) config.port = parseInt(process.env.PORT, 10);
if (process.env.HOST) config.host = process.env.HOST;

module.exports = config;
