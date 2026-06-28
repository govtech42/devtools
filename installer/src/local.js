// Local install flow: generate the group .env, then drive the Makefile
// (`make up` already handles colima-up + datadirs + build + up), optional smoke.
import { resolve } from 'node:path';
import { REPO_ROOT } from './config.js';
import { run } from './exec.js';
import { GROUPS, groupOptions } from './groups.js';
import { ensureLocalEnv } from './env.js';
import { select, confirm, note, log, pc } from './ui.js';

export async function runLocal() {
  const group = await select({ message: 'Qual grupo instalar localmente?', options: groupOptions() });

  // Local data root lives under the repo (matches Conductor/DECISIONS DATA_ROOT parity).
  const dataRoot = resolve(REPO_ROOT, `.data-${group}`);
  const { path: envPath, domains } = await ensureLocalEnv(group, { dataRoot });

  if (GROUPS[group].needsGHCR) {
    note(
      `O grupo "${group}" usa imagens de fork no GHCR. Localmente o Plane (profile)\n` +
        `fica desligado e o Chatwoot roda a imagem oficial — ok para desenvolvimento.`,
      pc.yellow('Atenção (GHCR)'),
    );
  }

  const go = await confirm({ message: `Subir o stack "${group}" agora? (make up)`, initialValue: true });
  if (!go) {
    log.info(`.env pronto em ${envPath}. Suba depois com: make up GROUP=${group}`);
    return;
  }

  // `make up` = colima-up + datadirs + build + up -d (see Makefile).
  await run('make', ['up', `GROUP=${group}`]);

  const smoke = await confirm({ message: 'Rodar a suíte de smoke?', initialValue: true });
  if (smoke) {
    await run('make', ['smoke', `GROUP=${group}`], { allowNonZero: true });
  }

  printSummary(group, domains, { local: true });
}

export function printSummary(group, domains, { local }) {
  const lines = [];
  if (domains.length) {
    lines.push('Apps:');
    for (const d of domains) lines.push(`  ${pc.cyan('https://' + d.value)}`);
  }
  if (!local && domains.length) {
    lines.push('', 'Lembre de apontar os DNS (registros A) dos domínios acima para o IP do host.');
  }
  note(lines.join('\n') || `Grupo ${group} pronto.`, pc.green(`Instalação (${group}) concluída`));
}
