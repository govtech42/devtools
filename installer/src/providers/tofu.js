// Shared OpenTofu helpers for the EC2 and Vultr providers: a local SSH keypair,
// the operator's public IP, and init/apply/output wrappers.
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { REPO_ROOT } from '../config.js';
import { run, ok } from '../exec.js';

// One ed25519 keypair reused by the OpenTofu providers (gitignored).
const KEY_BASE = 'infra/scripts/devtools-tofu';

export async function ensureTofu() {
  if (!(await ok('tofu', ['version']))) {
    throw new Error('OpenTofu (`tofu`) não encontrado. Instale: https://opentofu.org/docs/intro/install/');
  }
}

export async function ensureKeypair() {
  const priv = resolve(REPO_ROOT, KEY_BASE);
  const pub = `${priv}.pub`;
  if (!existsSync(priv)) {
    await run('ssh-keygen', ['-t', 'ed25519', '-N', '', '-f', priv, '-C', 'devtools-tofu'], { capture: true });
  }
  return { privPath: priv, publicKey: readFileSync(pub, 'utf8').trim() };
}

export async function ownerIp() {
  const { stdout } = await run('curl', ['-fsS', 'https://checkip.amazonaws.com'], { capture: true });
  return stdout.trim();
}

function chdir(dir) {
  return `-chdir=${resolve(REPO_ROOT, dir)}`;
}

// vars: { key: value } -> -var key=value (spawn passes each as one argv, spaces ok)
function varArgs(vars) {
  return Object.entries(vars).flatMap(([k, v]) => ['-var', `${k}=${v}`]);
}

export async function tofuApply(dir, vars, { env } = {}) {
  await run('tofu', [chdir(dir), 'init', '-input=false'], { env });
  await run('tofu', [chdir(dir), 'apply', '-auto-approve', '-input=false', ...varArgs(vars)], { env });
}

export async function tofuOutput(dir, { env } = {}) {
  const { stdout } = await run('tofu', [chdir(dir), 'output', '-json'], { capture: true, env });
  const raw = JSON.parse(stdout);
  return Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, v.value]));
}
