// EC2 provider via OpenTofu (infra/tofu/ec2). Creates the instance + SG + EIP,
// then returns the connection. Docker/dirs come from bootstrap-host.sh over SSH.
import { run } from '../exec.js';
import { text, note, task, pc } from '../ui.js';
import { ensureTofu, ensureKeypair, ownerIp, tofuApply, tofuOutput } from './tofu.js';

const TOFU_DIR = 'infra/tofu/ec2';
const TYPE_BY_GROUP = { dev: 't3.xlarge', support: 't3.large', admin: 't3.large', monitoring: 't3.small' };

export async function provisionEC2({ group }) {
  await ensureTofu();

  const name = (await text({ message: 'Nome da instância', initialValue: `devtools-${group}` })).trim();
  const region = (await text({ message: 'Região AWS', initialValue: 'us-east-1' })).trim();
  const instanceType = (await text({ message: 'Instance type', initialValue: TYPE_BY_GROUP[group] || 't3.large' })).trim();
  const rootGb = (await text({ message: 'Tamanho do disco root (GB)', initialValue: '80' })).trim();

  const { privPath, publicKey } = await ensureKeypair();
  const ip = await task('descobrindo seu IP público…', 'IP do operador obtido', () => ownerIp());

  note(
    `Instância: ${name} (${instanceType})\nRegião: ${region}\nDisco root: ${rootGb}GB\nSSH liberado p/: ${ip}/32`,
    'Provisionar EC2 (OpenTofu)',
  );

  const env = { ...process.env, AWS_REGION: region, AWS_DEFAULT_REGION: region };
  await tofuApply(
    TOFU_DIR,
    { name, region, instance_type: instanceType, root_volume_gb: rootGb, owner_ip: ip, public_key: publicKey },
    { env },
  );

  const out = await tofuOutput(TOFU_DIR, { env });
  const host = out.public_ip;
  if (!host) throw new Error('OpenTofu não retornou public_ip (EC2).');
  note(`IP: ${pc.cyan(host)}`, 'EC2 pronto');

  return { label: name, host, user: out.ssh_user || 'ubuntu', keyPath: privPath, cloudInit: true };
}
