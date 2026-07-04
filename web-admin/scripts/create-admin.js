'use strict';

// One-time bootstrap: create the first admin account (or add another admin).
// Usage:  npm run create-admin
// Prompts for username and password on the console (password input is hidden).

const readline = require('readline');
const users = require('../server/users');

function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (answer) => { rl.close(); resolve(answer.trim()); }));
}

// Hidden password prompt (no echo).
function askHidden(question) {
  return new Promise((resolve) => {
    const stdin = process.stdin;
    process.stdout.write(question);
    const wasRaw = !!stdin.isRaw;
    if (stdin.isTTY) stdin.setRawMode(true);
    stdin.resume();
    let value = '';
    function finish() {
      if (stdin.isTTY) stdin.setRawMode(wasRaw);
      stdin.removeListener('data', onData);
      stdin.pause();
      process.stdout.write('\n');
    }
    function onData(char) {
      const code = char[0];
      if (code === 0x0a || code === 0x0d) { finish(); resolve(value); return; }   // Enter
      if (code === 0x03) { finish(); process.exit(1); return; }                    // Ctrl+C
      if (code === 0x08 || code === 0x7f) { value = value.slice(0, -1); return; }  // Backspace / DEL
      value += char.toString('utf8');
    }
    stdin.on('data', onData);
  });
}

(async function main() {
  console.log('Create an admin account for the Dune Awakening web-admin panel.\n');
  try {
    const username = await ask('Username: ');
    users.validateUsername(username);
    if (users.findByName(username)) {
      console.error(`\nUser "${username}" already exists. Aborting.`);
      process.exit(1);
    }
    const password = await askHidden('Password (min 8 chars): ');
    const confirm = await askHidden('Confirm password: ');
    if (password !== confirm) {
      console.error('\nPasswords do not match. Aborting.');
      process.exit(1);
    }
    users.validatePassword(password);
    const created = users.create({ username, password, role: 'admin' });
    console.log(`\nAdmin account "${created.username}" created. You can now start the server and sign in.`);
    process.exit(0);
  } catch (err) {
    console.error('\nError: ' + err.message);
    process.exit(1);
  }
})();
