// Shared "install on a host" steps — identical for every provider once we have an
// SSH handle. Bootstrap -> ship repo -> ship .env -> compose up -> smoke.
import { writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { REPO_ROOT } from './config.js';
import { GROUPS, composeArgs } from './groups.js';
import { buildEnv } from './env.js';
import { confirm, text, note, task, log, pc } from './ui.js';

const APP_DIR = '/opt/devtools';
const RSYNC_EXCLUDES = ['.git', '.data', '.data-*', '.env', 'node_modules', '.terraform', '*.tfstate*', '*.pem'];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Fresh cloud hosts take a bit for sshd to come up — retry before giving up.
async function waitForSSH(ssh, { retries = 18, delayMs = 5000 } = {}) {
  for (let i = 0; i < retries; i++) {
    if (await ssh.testConnection()) return true;
    await sleep(delayMs);
  }
  return false;
}

export async function deployToHost(ssh, group, { cloudInit = false } = {}) {
  // 1. reachability (with retries — cloud instances need a moment)
  const reachable = await task('aguardando SSH…', 'SSH ok', () => waitForSSH(ssh, cloudInit ? {} : { retries: 1 }));
  if (!reachable) throw new Error(`não consegui conectar em ${ssh.target} (verifique ip/usuário/chave).`);

  // 1b. on a freshly provisioned host, let cloud-init finish (apt/dpkg locks)
  if (cloudInit) {
    await task('aguardando cloud-init…', 'cloud-init pronto', () =>
      ssh.exec('cloud-init status --wait >/dev/null 2>&1 || true'),
    );
  }

  // 2. idempotent host bootstrap (Docker, swap, /data dirs, app dir)
  await task('preparando o host (docker, swap, dirs)…', 'host preparado', () =>
    ssh.execScript(resolve(REPO_ROOT, 'infra/scripts/bootstrap-host.sh'), { env: { ...process.env } }),
  );

  // 3. .env (generated locally to a temp file so we never clobber a local dev .env)
  const { content, generated, domains } = await buildEnv(group, { dataRoot: '/data' });
  const tmpEnv = resolve(tmpdir(), `devtools-${group}-${process.pid}.env`);
  writeFileSync(tmpEnv, content, { mode: 0o600 });

  try {
    // 4. ship the repo (no secrets/keys — see RSYNC_EXCLUDES; .env uploaded separately)
    await task('enviando o repositório (rsync)…', 'repositório no host', () =>
      ssh.rsync(REPO_ROOT + '/', `${APP_DIR}/`, RSYNC_EXCLUDES),
    );

    // 5. ship the .env and lock it down
    await task('enviando o .env…', '.env no host (chmod 600)', async () => {
      await ssh.upload(tmpEnv, `${APP_DIR}/deploy/${group}/.env`);
      await ssh.exec(`chmod 600 ${APP_DIR}/deploy/${group}/.env`);
    });
    if (generated.length) note(`Segredos gerados: ${pc.dim(generated.join(', '))}`, 'Arquivo .env');
  } finally {
    try {
      unlinkSync(tmpEnv);
    } catch {
      /* best-effort cleanup */
    }
  }

  // 6. GHCR login for fork-image groups (Plane on dev, Chatwoot on support)
  if (GROUPS[group].needsGHCR) {
    const doLogin = await confirm({
      message: `O grupo "${group}" usa imagens de fork no GHCR. Fazer docker login no host agora?`,
      initialValue: true,
    });
    if (doLogin) {
      const user = await text({ message: 'GHCR_USER', placeholder: 'govtech42' });
      const token = await text({ message: 'GHCR_TOKEN (read:packages)', placeholder: 'ghp_…' });
      await task('docker login ghcr.io…', 'logado no GHCR', () =>
        // token via stdin (não vai para argv/histórico)
        ssh.exec(`cd ${APP_DIR} && docker login ghcr.io -u ${user} --password-stdin`, { input: token.trim() + '\n' }),
      );
    } else {
      note(
        'Sem login no GHCR, o pull/up das imagens de fork vai falhar. As imagens de\n' +
          'fork (Plane/Chatwoot) também precisam ter sido construídas e enviadas ao GHCR.',
        pc.yellow('Atenção'),
      );
    }
  }

  // 7. compose up (build + run) on the host
  const args = composeArgs(group).join(' ');
  await task('subindo o stack (docker compose up -d --build)…', 'stack no ar', () =>
    ssh.exec(`cd ${APP_DIR} && docker compose ${args} up -d --build`),
  );

  // 8. live smoke (best-effort; failures shouldn't abort the summary)
  const smoke = await confirm({ message: 'Rodar a suíte de smoke no host?', initialValue: true });
  if (smoke) {
    try {
      await ssh.exec(`cd ${APP_DIR} && bash test/smoke.sh ${group}`);
    } catch (e) {
      log.warn(pc.yellow(`smoke retornou erro: ${e.message}`));
    }
  }

  // 9. summary + DNS reminder
  printRemoteSummary(group, ssh.host, domains);
}

function printRemoteSummary(group, host, domains) {
  const lines = [`Host: ${pc.cyan(host)}`];
  if (domains.length) {
    lines.push('', 'Apps (após o DNS propagar e o TLS emitir):');
    for (const d of domains) lines.push(`  ${pc.cyan('https://' + d.value)}`);
    lines.push('', `DNS: aponte os registros A acima para ${pc.cyan(host)}.`);
  }
  if (group === 'monitoring') {
    lines.push('', 'Beszel: faça login, copie a chave pública do hub na UI, preencha BESZEL_KEY');
    lines.push('e suba o agente com --profile agents.');
  }
  note(lines.join('\n'), pc.green(`Deploy remoto (${group}) concluído`));
}
