// Generate a group's .env from its deploy/<group>/.env.example.
//
// Each KEY=VALUE line in the example is classified:
//   - DATA_ROOT      -> set by the caller (local: <repo>/.data-<g>; remote: /data)
//   - prompt keys    -> ask the operator (domains, ACME email, GHCR creds, admin email)
//   - empty value    -> kept empty (e.g. BESZEL_KEY — comes from the Beszel UI later)
//   - secret keys    -> auto-generated strong value (passwords, secrets, JWT, key-base)
//   - everything else-> kept verbatim from the example (image tags, hosts, APP_DBS…)
//
// Comments and ordering from the example are preserved so the result stays readable.
import { readFileSync, existsSync, writeFileSync, chmodSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { resolve } from 'node:path';
import { REPO_ROOT } from './config.js';
import { text, confirm, note, pc } from './ui.js';

const PROMPT_RE = /(_DOMAIN$|^ACME_EMAIL$|^GHCR_USER$|^GHCR_TOKEN$|_ADMIN_EMAIL$|_ADMIN_USERNAME$|_ADMIN_NAME$)/;
const SECRET_RE = /(PASSWORD|SECRET|_KEY_BASE$|JWT|_APP_SECRET$)/;

function genSecret(key) {
  if (/_KEY_BASE$/.test(key)) return randomBytes(64).toString('hex'); // 128 hex chars
  if (/(JWT|_APP_SECRET$|_SECRET_KEY$)/.test(key)) return randomBytes(48).toString('base64url'); // ≥32 chars
  return randomBytes(24).toString('base64url');
}

function classify(key, value) {
  if (key === 'DATA_ROOT') return 'dataroot';
  if (PROMPT_RE.test(key)) return 'prompt';
  if (value === '') return 'fixed';
  if (value.startsWith('change-me') || SECRET_RE.test(key)) return 'secret';
  return 'fixed';
}

function parseLine(line) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  return m ? { key: m[1], value: m[2] } : null;
}

function examplePath(group) {
  return resolve(REPO_ROOT, 'deploy', group, '.env.example');
}

// Build .env content (string) + summary, prompting for the external values.
// Does NOT write anything — caller decides where it goes (local file vs temp+upload).
export async function buildEnv(group, { dataRoot }) {
  const path = examplePath(group);
  if (!existsSync(path)) throw new Error(`não encontrei ${path}`);

  const outLines = [];
  const generated = [];
  const domains = [];

  for (const rawLine of readFileSync(path, 'utf8').split('\n')) {
    const kv = parseLine(rawLine);
    if (!kv) {
      outLines.push(rawLine);
      continue;
    }
    const { key, value } = kv;
    switch (classify(key, value)) {
      case 'dataroot':
        outLines.push(`${key}=${dataRoot}`);
        break;
      case 'secret':
        generated.push(key);
        outLines.push(`${key}=${genSecret(key)}`);
        break;
      case 'prompt': {
        const def = value.startsWith('change-me') ? '' : value;
        const v = await text({
          message: key,
          placeholder: def || '(obrigatório)',
          initialValue: def,
          validate: (s) => (s.trim() === '' ? 'Não pode ficar vazio' : undefined),
        });
        outLines.push(`${key}=${v.trim()}`);
        if (key.endsWith('_DOMAIN')) domains.push({ key, value: v.trim() });
        break;
      }
      default:
        outLines.push(rawLine);
    }
  }

  const content = outLines.join('\n');
  return { content: content.endsWith('\n') ? content : content + '\n', generated, domains };
}

// Local: write deploy/<group>/.env (chmod 600), with a keep-existing prompt.
// Returns { path, domains }.
export async function ensureLocalEnv(group, { dataRoot }) {
  const envPath = resolve(REPO_ROOT, 'deploy', group, '.env');

  if (existsSync(envPath)) {
    const keep = await confirm({
      message: `${envPath} já existe. Manter o atual? (Não = regenerar)`,
      initialValue: true,
    });
    if (keep) return { path: envPath, domains: readDomains(envPath) };
  }

  const { content, generated, domains } = await buildEnv(group, { dataRoot });
  writeFileSync(envPath, content);
  chmodSync(envPath, 0o600);
  summary(envPath, generated);
  return { path: envPath, domains };
}

function summary(envPath, generated) {
  note(
    [
      `${pc.green('✓')} ${envPath} (chmod 600)`,
      generated.length ? `Segredos gerados: ${pc.dim(generated.join(', '))}` : 'Sem segredos neste grupo.',
    ].join('\n'),
    'Arquivo .env',
  );
}

export { summary as noteEnvSummary };

function readDomains(envPath) {
  const domains = [];
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const kv = parseLine(line);
    if (kv && kv.key.endsWith('_DOMAIN') && kv.value) domains.push({ key: kv.key, value: kv.value });
  }
  return domains;
}
