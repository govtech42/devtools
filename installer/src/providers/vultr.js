// Vultr provider via OpenTofu (infra/tofu/vultr). Needs VULTR_API_KEY (env or
// prompt). Docker/dirs come from bootstrap-host.sh over SSH (user = root).
import { text, note, task, pc } from '../ui.js';
import { ensureTofu, ensureKeypair, ownerIp, tofuApply, tofuOutput } from './tofu.js';

const TOFU_DIR = 'infra/tofu/vultr';
const PLAN_BY_GROUP = { dev: 'vc2-6c-16gb', support: 'vc2-4c-8gb', admin: 'vc2-4c-8gb', monitoring: 'vc2-1c-2gb' };

export async function provisionVultr({ group }) {
  await ensureTofu();

  let apiKey = process.env.VULTR_API_KEY;
  if (!apiKey) {
    apiKey = (await text({ message: 'VULTR_API_KEY', placeholder: 'sua API key da Vultr' })).trim();
  }

  const name = (await text({ message: 'Label da instância', initialValue: `devtools-${group}` })).trim();
  const region = (await text({ message: 'Região Vultr', initialValue: 'ewr' })).trim();
  const plan = (await text({ message: 'Plano', initialValue: PLAN_BY_GROUP[group] || 'vc2-4c-8gb' })).trim();

  const { privPath, publicKey } = await ensureKeypair();
  const ip = await task('descobrindo seu IP público…', 'IP do operador obtido', () => ownerIp());

  note(`Instância: ${name} (${plan})\nRegião: ${region}\nSSH liberado p/: ${ip}/32`, 'Provisionar Vultr (OpenTofu)');

  const env = { ...process.env, VULTR_API_KEY: apiKey };
  await tofuApply(TOFU_DIR, { name, region, plan, owner_ip: ip, public_key: publicKey }, { env });

  const out = await tofuOutput(TOFU_DIR, { env });
  const host = out.public_ip;
  if (!host || host === '0.0.0.0') throw new Error('OpenTofu não retornou um IP válido (Vultr).');
  note(`IP: ${pc.cyan(host)}`, 'Vultr pronto');

  return { label: name, host, user: out.ssh_user || 'root', keyPath: privPath, cloudInit: true };
}
