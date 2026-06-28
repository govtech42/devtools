# installer/ — devtools TUI installer

Node.js (ESM) TUI for installing the stack locally or on a remote VPS. Run it via the
repo shim:

```bash
./bin/install        # installs deps on first run, then launches the TUI
```

Stack: [`@clack/prompts`](https://www.npmjs.com/package/@clack/prompts) + `picocolors`.
It **drives the existing tooling** (Makefile, compose, `infra/` scripts, `infra/tofu/`
modules) — no deploy logic is duplicated here.

## Modes

- **Local** — generate `deploy/<group>/.env` (auto-generated secrets; prompts only for
  domains/email/GHCR) and run `make up GROUP=<group>`, then optional smoke.
- **Remoto** — pick a provider, provision (or connect), then run the shared deploy over
  SSH: bootstrap → rsync repo → ship `.env` → `docker compose up -d --build` → smoke.

## Layout

```
index.js              entry + Local|Remoto menu
src/ui.js             clack/picocolors helpers (cancel-safe prompts, spinner)
src/exec.js           spawn wrapper (stream | capture, stdin)
src/ssh.js            SSH interface (shell-out to ssh/scp/rsync) — swap point for ssh2
src/groups.js         per-group metadata (compose args, bundle, GHCR, profiles)
src/env.js            .env generator (secret | prompt | fixed classification)
src/local.js          local flow
src/remote.js         remote flow (group -> provider -> deploy)
src/deploy.js         shared "install on a host" steps over SSH
src/providers/        existing · lightsail · ec2 · vultr (+ tofu.js helpers)
```

Every provider implements `provision({ group }) -> { host, user, keyPath, cloudInit? }`;
`deploy.js` is identical for all of them.

## Notes

- SSH is shell-out behind `src/ssh.js`; migrating to `node-ssh`/`ssh2` means changing
  only that module.
- The OpenTofu providers reuse one SSH keypair at `infra/scripts/devtools-tofu`
  (gitignored). EC2/Vultr require `tofu`; see `../infra/tofu/README.md`.
