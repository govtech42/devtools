// "Host existente" provider: the box is already provisioned; just collect how to
// reach it. Returns the common connection shape { label, host, user, keyPath }.
import { homedir } from 'node:os';
import { resolve, isAbsolute } from 'node:path';
import { REPO_ROOT } from '../config.js';
import { text } from '../ui.js';

const nonEmpty = (s) => (s.trim() === '' ? 'Não pode ficar vazio' : undefined);

function resolveKeyPath(p) {
  if (p.startsWith('~')) return resolve(homedir(), p.slice(1).replace(/^\//, ''));
  return isAbsolute(p) ? p : resolve(REPO_ROOT, p);
}

export async function provisionExisting() {
  const label = await text({ message: 'Label do servidor', placeholder: 'meu-vps', initialValue: '' });
  const host = await text({ message: 'IP ou hostname', validate: nonEmpty });
  const user = await text({ message: 'Usuário SSH', initialValue: 'ubuntu', validate: nonEmpty });
  const keyPath = await text({
    message: 'Caminho da chave SSH privada',
    placeholder: 'infra/scripts/devtools-key.pem',
    validate: nonEmpty,
  });

  return {
    label: label.trim() || host.trim(),
    host: host.trim(),
    user: user.trim(),
    keyPath: resolveKeyPath(keyPath.trim()),
  };
}
