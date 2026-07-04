'use strict';

const path = require('path');
const express = require('express');
const session = require('express-session');

const config = require('./config');
const { publicDir } = require('./paths');
const { getSessionSecret, requireAuth } = require('./auth');
const users = require('./users');

const authRoutes = require('./routes/auth.routes');
const actionRoutes = require('./routes/actions.routes');
const userRoutes = require('./routes/users.routes');

const app = express();
// Trust the reverse proxy (nginx/Caddy/IIS/Cloudflare) so req.secure / req.ip
// come from X-Forwarded-Proto / X-Forwarded-For. Number = hops to trust, or true
// to trust the whole chain (safe here because the app is firewalled to the proxy).
app.set('trust proxy', config.trustProxy != null ? config.trustProxy : 1);
app.disable('x-powered-by');

// When the app is only ever reached through an HTTPS-terminating proxy chain
// (e.g. Cloudflare -> reverse proxy -> app) that may not reliably forward
// X-Forwarded-Proto, treat every request as HTTPS. This makes req.secure true so
// the Secure session cookie is actually issued. Only enable behind such a proxy.
if (config.behindHttpsProxy) {
  app.use((req, res, next) => {
    req.headers['x-forwarded-proto'] = 'https';
    next();
  });
}

// Canonical public origin (e.g. https://admin.example.com) used to validate
// incoming Host/Origin. localhost is always allowed for host-side use.
const publicOrigin = config.publicOrigin ? String(config.publicOrigin).replace(/\/$/, '') : null;
const expectedHost = publicOrigin ? new URL(publicOrigin).host.split(':')[0] : null;
const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);

// Private/LAN IPv4 literals are allowed as Host: a reverse proxy on another
// machine may forward the upstream IP as the Host header. Public hostnames still
// must match the configured domain.
function isPrivateHost(host) {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return false;
  const a = +m[1], b = +m[2];
  return a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31);
}

// Reject requests arriving with an unexpected Host header (host-header abuse).
app.use((req, res, next) => {
  if (!expectedHost) return next();
  const host = (req.hostname || '').toLowerCase();
  if (host === expectedHost.toLowerCase() || LOCAL_HOSTS.has(host) || isPrivateHost(host)) return next();
  return res.status(400).json({ error: 'Bad host.' });
});

// HSTS once we know the connection is secure (proxy may also set this).
app.use((req, res, next) => {
  if (req.secure) res.setHeader('Strict-Transport-Security', 'max-age=15552000; includeSubDomains');
  next();
});

app.use(express.json({ limit: '64kb' }));
app.use(express.urlencoded({ extended: false, limit: '64kb' }));

app.use(
  session({
    name: config.sessionCookieName || 'dune_admin_sid',
    secret: getSessionSecret(),
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: 'strict',
      // HTTPS-only when served behind the proxy. Requires trust proxy so
      // req.secure reflects X-Forwarded-Proto.
      secure: config.cookieSecure !== false,
      maxAge: (config.sessionMaxAgeMinutes || 480) * 60 * 1000,
    },
  })
);

// Origin check for state-changing requests: layered defense on top of the CSRF
// token. If an Origin/Referer is present it must match the public origin (or be
// local). Requests without either header (e.g. curl) fall through to the CSRF
// token requirement enforced per-route.
app.use((req, res, next) => {
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') return next();
  const source = req.get('origin') || req.get('referer');
  if (!source) return next();
  let originHost;
  try { originHost = new URL(source).host.split(':')[0].toLowerCase(); } catch { return next(); }
  if ((expectedHost && originHost === expectedHost.toLowerCase()) || LOCAL_HOSTS.has(originHost)) return next();
  return res.status(403).json({ error: 'Cross-origin request blocked.' });
});

// --- API routes ---
app.use(authRoutes);
app.use(actionRoutes);
app.use(userRoutes);

// --- Static pages ---
// The dashboard and users pages require a session; login is public.
// Gate the protected HTML explicitly before the static handler serves them.
app.get(['/', '/index.html'], requireAuth, (req, res) => {
  res.sendFile(path.join(publicDir, 'dashboard.html'));
});
app.get('/dashboard.html', requireAuth, (req, res) => {
  res.sendFile(path.join(publicDir, 'dashboard.html'));
});
app.get('/users.html', requireAuth, (req, res) => {
  if (req.session.user.role !== 'admin') return res.redirect('/dashboard.html');
  res.sendFile(path.join(publicDir, 'users.html'));
});

app.use(express.static(publicDir));

// Fallback: unknown API path -> 404 json; anything else -> login.
app.use((req, res) => {
  if (req.path.startsWith('/api/')) return res.status(404).json({ error: 'Not found.' });
  return res.redirect('/login.html');
});

const port = config.port || 8477;
const host = config.host || '127.0.0.1';

app.listen(port, host, () => {
  const where = host === '0.0.0.0' ? 'all interfaces' : host;
  console.log(`Dune Awakening web-admin listening on ${where}:${port}`);
  if (publicOrigin) console.log(`Public origin: ${publicOrigin}`);
  if (users.count() === 0) {
    console.log('No accounts yet. Create the first admin with:  npm run create-admin');
  }
});

