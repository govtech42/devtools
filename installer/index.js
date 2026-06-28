#!/usr/bin/env node
// devtools installer — TUI for installing the stack locally or on a remote VPS.
import { intro, outro, select, pc, p } from './src/ui.js';
import { runLocal } from './src/local.js';
import { runRemote } from './src/remote.js';

async function main() {
  console.log('');
  intro(pc.bgCyan(pc.black(' devtools installer ')));

  const mode = await select({
    message: 'O que você quer fazer?',
    options: [
      { value: 'local', label: 'Local', hint: 'instalar nesta máquina (Colima/Docker)' },
      { value: 'remote', label: 'Remoto', hint: 'provisionar e/ou instalar num servidor via SSH' },
    ],
  });

  if (mode === 'local') await runLocal();
  else await runRemote();

  outro(pc.green('Pronto.'));
}

main().catch((err) => {
  p.log.error(pc.red(err?.message ?? String(err)));
  process.exit(1);
});
