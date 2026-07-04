# Dune Awakening Self-Hosted Server

Tooling to run and administer a self-hosted **Dune Awakening** ("battlegroup") server on Hyper-V, plus a web panel so trusted players can start/stop/monitor it without shell access to the host.

## Components

### `battlegroup-management/`
PowerShell scripts that manage the Hyper-V VM lifecycle:

- `initial-setup.ps1` — first-time host/VM setup (Hyper-V checks, VM import, SSH key provisioning).
- `battlegroup.ps1` — start / stop / reset the battlegroup VM.
- `vm-ip.ps1`, `vm-utilities.ps1` — VM state and networking helpers.
- `web-admin.ps1` — bridges the web admin panel to the same VM controls.

See `battlegroup.bat` at the repo root for the quick-launch entry point.

### `web-admin/`
A Node.js web app that exposes battlegroup start/stop/restart and status/monitoring over HTTPS, so admins don't need direct host or PowerShell access. Full setup and reverse-proxy instructions are in [`web-admin/README.md`](web-admin/README.md).

## Requirements

- Windows with **Hyper-V** enabled.
- **Node.js 18+** for the web admin panel.
- Windows **OpenSSH client** (`ssh`) for VM communication.
- Administrator privileges (Hyper-V's `Get-VM` requires it).

## Getting Started

1. Run `battlegroup-management/initial-setup.ps1` as Administrator to provision the VM and SSH access.
2. Use `battlegroup.bat` / `battlegroup-management/battlegroup.ps1` for direct start/stop/reset control.
3. Optionally set up [`web-admin`](web-admin/README.md) to give others browser-based control without host access.

## Contributor Note

The GitHub user **`shubh2294`** has at no point contributed to this project. That account was previously (and incorrectly) associated with commit authorship on this repository due to a historical git metadata mismatch — commit author/email fields are user-declared and not verified by GitHub, so attribution can end up pointing at the wrong account. This has since been corrected; `shubh2294` has no affiliation with, access to, or contribution history in this project.
