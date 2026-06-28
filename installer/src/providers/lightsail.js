// Lightsail provider — wraps infra/scripts/create-lightsail.sh (AWS CLI), then
// reads back the allocated static IP. Keeps the locked "Lightsail via AWS CLI"
// path; OpenTofu is only for the EC2/Vultr providers.
import { resolve } from 'node:path';
import { REPO_ROOT } from '../config.js';
import { run, ok } from '../exec.js';
import { GROUPS } from '../groups.js';
import { text, note, task, pc } from '../ui.js';

const KEY_PAIR = 'devtools-key'; // shared across instances (script reuses if present)

export async function provisionLightsail({ group }) {
  if (!(await ok('aws', ['--version']))) {
    throw new Error('AWS CLI v2 não encontrado. Instale e rode `aws configure` antes (provider Lightsail).');
  }

  const name = (await text({ message: 'Nome da instância', initialValue: `devtools-${group}` })).trim();
  const region = (await text({ message: 'Região', initialValue: 'us-east-1' })).trim();
  const az = (await text({ message: 'Availability zone', initialValue: `${region}a` })).trim();
  const bundle = GROUPS[group].bundle;
  const diskName = GROUPS[group].diskName;

  note(
    `Instância: ${name} (${bundle})\nDisco: ${diskName} 80GB\nRegião/AZ: ${region}/${az}`,
    'Provisionar Lightsail',
  );

  const env = { ...process.env, NAME: name, BUNDLE: bundle, DISK_NAME: diskName, REGION: region, AZ: az, KEY_PAIR };

  // Streamed so the operator sees the (multi-minute) create + wait.
  await run('bash', [resolve(REPO_ROOT, 'infra/scripts/create-lightsail.sh')], { env });

  // Read the static IP back (the script allocates "<name>-ip").
  const host = await task('lendo o IP estático…', 'IP obtido', async () => {
    const { stdout } = await run(
      'aws',
      ['lightsail', 'get-static-ip', '--static-ip-name', `${name}-ip`, '--region', region, '--query', 'staticIp.ipAddress', '--output', 'text'],
      { capture: true, env },
    );
    return stdout.trim();
  });

  if (!host || host === 'None') throw new Error('não consegui obter o IP estático do Lightsail.');
  note(`IP: ${pc.cyan(host)}`, 'Lightsail pronto');

  return {
    label: name,
    host,
    user: 'ubuntu',
    keyPath: resolve(REPO_ROOT, 'infra/scripts', `${KEY_PAIR}.pem`),
    cloudInit: true, // user-data ainda pode estar rodando → deploy aguarda
  };
}
