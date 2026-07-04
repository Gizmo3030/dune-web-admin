# Dune Awakening — Web Admin Panel

A small web app that lets you hand out accounts so trusted people can **start / stop / reset** the battlegroup and **monitor** its status from a browser — without giving them the host machine or the PowerShell menu.

It reuses the exact same mechanism as `battlegroup-management/battlegroup.ps1`: it queries Hyper-V for the VM state/IP and runs `battlegroup <command>` over SSH using the SSH key created during initial setup.

> **Scope:** Served over HTTPS at a public domain (e.g. `https://admin.example.com`) behind a **reverse proxy** that forwards to the Node app on `localhost:8477` — see [Running behind a reverse proxy](#running-behind-a-reverse-proxy). Exposed actions are battlegroup **start / stop / restart** plus **status & monitoring**. VM power on/off is intentionally *not* exposed here — see [VM must be running](#vm-must-be-running).

## Requirements

- **Node.js 18+** installed and on PATH (`node --version`).
- **Windows OpenSSH client** (`ssh`) available — same one the PowerShell tooling uses.
- The battlegroup must already be set up via `battlegroup.bat` (so the SSH key exists and is authorized on the VM).
- Must run **as Administrator** — Hyper-V's `Get-VM` requires it.

## First-time setup

From this `web-admin` folder:

```
npm install
npm run create-admin      # prompts for the first admin username + password
```

## Running

Double-click **`start-web-admin.bat`** (it self-elevates to Administrator and runs `npm install` on first run), or from an **elevated** terminal:

```
npm start
```

Users reach it at **https://admin.example.com** (through the reverse proxy). On the host you can also hit **http://localhost:8477** directly — but note that with `cookieSecure: true` a login over plain HTTP won't persist a session, so for real use go through the HTTPS domain.

## Running behind a reverse proxy

The app listens on `127.0.0.1:8477` (loopback only) and expects a reverse proxy to terminate TLS for `admin.example.com` and forward to it. The proxy **must** pass `X-Forwarded-Proto` so the app knows the connection is HTTPS (that drives the `Secure` session cookie).

nginx:

```nginx
server {
    server_name admin.example.com;
    listen 443 ssl;
    # ssl_certificate / ssl_certificate_key ...
    location / {
        proxy_pass http://127.0.0.1:8477;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;
    }
}
```

Caddy:

```
admin.example.com {
    reverse_proxy 127.0.0.1:8477
}
```

Relevant config keys (`config/default.json`): `host` (`127.0.0.1`), `trustProxy` (`1`), `cookieSecure` (`true`), `publicOrigin` (`https://admin.example.com`). The app validates the incoming `Host` and, for state-changing requests, the `Origin`/`Referer` against `publicOrigin` (localhost is always allowed for host-side use). If your proxy runs on a **different** machine, set `host` to the interface it can reach instead of `127.0.0.1`.

## Accounts & roles

- **Admin** — everything, plus manage accounts on the *Accounts* page.
- **Operator** — start / stop / restart and view status; cannot manage accounts.

Admins add more accounts in the UI. The last remaining admin cannot be deleted or demoted (prevents lockout). Passwords are hashed with bcrypt; only hashes are stored, in `data/users.json`.

## VM must be running

Battlegroup actions require the Hyper-V VM (`dune-awakening`) to be **Running**. The dashboard shows the VM state read-only; if it's off, the action buttons are disabled with a note. Start the VM from the host's `battlegroup.bat` menu (option `b`). Adding an admin-only "Start VM" button to this panel later is a small change if you want it.

## Configuration

Edit `config/default.json`, or create `config/local.json` (gitignored) to override:

| Key | Default | Meaning |
|-----|---------|---------|
| `port` | `8477` | Port the Node app listens on (proxy forwards here) |
| `host` | `127.0.0.1` | Bind address. Loopback = only the local proxy can reach it |
| `trustProxy` | `1` | Proxy hops to trust for `X-Forwarded-Proto`/`-For` |
| `cookieSecure` | `true` | Send the session cookie only over HTTPS |
| `publicOrigin` | `https://admin.example.com` | Canonical origin; Host/Origin are validated against it |
| `vmName` | `dune-awakening` | Hyper-V VM name |
| `actionTimeoutSeconds` | `240` | Max time for start/stop/restart |
| `statusTimeoutSeconds` | `45` | Max time for a status check |
| `loginRateLimit` | 10 / 15 min | Login attempt throttle |

`PORT` and `HOST` environment variables also override these.

`DUNE_SSH_KEY_PATH` can be set to override the SSH key file path used by the host scripts and web action backend.

## Firewall

Only the **proxy's** public port (443) needs to be open at the perimeter. The Node app on `127.0.0.1:8477` is loopback-only and should **not** be exposed directly — no inbound firewall rule for 8477 is needed when the proxy is on the same host.

## Security notes

- Session cookies are `httpOnly` + `SameSite=strict` + `Secure` (HTTPS-only); a random session secret is generated once into `data/session-secret`.
- Runs behind a TLS-terminating reverse proxy; `trust proxy` makes `req.secure` reflect `X-Forwarded-Proto`. HSTS is sent on secure requests.
- Incoming `Host` is checked against `publicOrigin`; for state-changing requests the `Origin`/`Referer` is checked too (defense in depth alongside the CSRF token).
- CSRF protection (synchronizer token) on all state-changing requests.
- Login is rate-limited.
- The action name is validated against a fixed whitelist (`status|start|stop|restart`) **before** anything is passed to PowerShell — no arbitrary commands can flow through from the web.
- Every login and action is written to `data/audit.log` (one JSON object per line).

## Monitoring links caveat

The dashboard's **Director** and **File browser** links point at the VM's **private LAN IP** (`http://<vm-ip>:18888` and the director NodePort). Those are reachable from admins on the same LAN, but **not** from remote users coming in over the domain. Proxying those dashboards is out of scope here.

## Files

```
server/
  index.js            Express app bootstrap + static page gating
  config.js           loads config/default.json (+ optional local.json)
  paths.js            resolves data/ files and the PS script path
  auth.js             session secret, CSRF, requireAuth/requireAdmin
  users.js            bcrypt user store over data/users.json
  actions.js          action whitelist -> runs ps/bg-control.ps1
  audit.js            append-only audit log
  routes/             auth, actions, users route modules
  ps/bg-control.ps1   non-interactive VM/SSH backend, emits JSON
public/               login / dashboard / users pages + app.js + styles.css
scripts/create-admin.js   first-admin bootstrap CLI
data/                 (gitignored) users.json, session-secret, audit.log
```

## Troubleshooting

- **"Could not query Hyper-V … running as administrator?"** — start via `start-web-admin.bat` or an elevated terminal.
- **Battlegroup shows "unreachable" / status errors** — the SSH key may not be authorized on the VM. Fix it from the host `battlegroup.bat` menu with option `d` (rotate-ssh-key). The backend uses `BatchMode=yes`, so a bad key fails fast instead of hanging.
- **Buttons are disabled** — the VM isn't Running. Start it from the host menu (option `b`).

