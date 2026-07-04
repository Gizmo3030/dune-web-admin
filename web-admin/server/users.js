'use strict';

const fs = require('fs');
const bcrypt = require('bcryptjs');
const { usersFile } = require('./paths');

const ROLES = ['admin', 'operator'];
const BCRYPT_ROUNDS = 12;
const USERNAME_RE = /^[A-Za-z0-9_.-]{3,32}$/;

function load() {
  try {
    const parsed = JSON.parse(fs.readFileSync(usersFile, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
}

function save(users) {
  const tmp = `${usersFile}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(users, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, usersFile);
}

function findByName(name) {
  if (!name) return null;
  const lower = String(name).toLowerCase();
  return load().find((u) => u.username.toLowerCase() === lower) || null;
}

function list() {
  // Never leak password hashes to callers.
  return load().map(({ username, role, createdAt }) => ({ username, role, createdAt }));
}

function count() {
  return load().length;
}

function validateUsername(name) {
  if (!USERNAME_RE.test(String(name || ''))) {
    throw new Error('Username must be 3-32 chars: letters, numbers, _ . - only.');
  }
}

function validatePassword(pw) {
  if (typeof pw !== 'string' || pw.length < 8) {
    throw new Error('Password must be at least 8 characters.');
  }
}

function validateRole(role) {
  if (!ROLES.includes(role)) {
    throw new Error(`Role must be one of: ${ROLES.join(', ')}.`);
  }
}

function create({ username, password, role }) {
  validateUsername(username);
  validatePassword(password);
  validateRole(role);
  const users = load();
  if (users.some((u) => u.username.toLowerCase() === username.toLowerCase())) {
    throw new Error(`User "${username}" already exists.`);
  }
  const user = {
    username,
    role,
    passwordHash: bcrypt.hashSync(password, BCRYPT_ROUNDS),
    createdAt: new Date().toISOString(),
  };
  users.push(user);
  save(users);
  return { username: user.username, role: user.role, createdAt: user.createdAt };
}

function remove(username) {
  const users = load();
  const idx = users.findIndex((u) => u.username.toLowerCase() === String(username).toLowerCase());
  if (idx === -1) throw new Error(`User "${username}" not found.`);
  users.splice(idx, 1);
  save(users);
}

function setPassword(username, password) {
  validatePassword(password);
  const users = load();
  const user = users.find((u) => u.username.toLowerCase() === String(username).toLowerCase());
  if (!user) throw new Error(`User "${username}" not found.`);
  user.passwordHash = bcrypt.hashSync(password, BCRYPT_ROUNDS);
  save(users);
}

function setRole(username, role) {
  validateRole(role);
  const users = load();
  const user = users.find((u) => u.username.toLowerCase() === String(username).toLowerCase());
  if (!user) throw new Error(`User "${username}" not found.`);
  user.role = role;
  save(users);
}

function verify(username, password) {
  const user = findByName(username);
  if (!user) {
    // Compare against a dummy hash to keep timing roughly constant.
    bcrypt.compareSync(String(password || ''), '$2a$12$0000000000000000000000000000000000000000000000000000');
    return null;
  }
  if (!bcrypt.compareSync(String(password || ''), user.passwordHash)) return null;
  return { username: user.username, role: user.role };
}

function adminCount() {
  return load().filter((u) => u.role === 'admin').length;
}

module.exports = {
  ROLES,
  list,
  count,
  create,
  remove,
  setPassword,
  setRole,
  verify,
  findByName,
  adminCount,
  validateUsername,
  validatePassword,
  validateRole,
};
