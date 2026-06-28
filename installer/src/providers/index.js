// Provider registry. Every provider exposes `provision({ group }) -> { host, user,
// keyPath, label? }`; deploy.js takes it from there, identically for all of them.
import { provisionExisting } from './existing.js';
import { provisionLightsail } from './lightsail.js';
import { provisionEC2 } from './ec2.js';
import { provisionVultr } from './vultr.js';

export const PROVIDERS = {
  existing: { label: 'Host existente', hint: 'já provisionado — informe ip/usuário/chave', fn: provisionExisting },
  lightsail: { label: 'AWS Lightsail', hint: 'cria a instância via AWS CLI', fn: provisionLightsail },
  ec2: { label: 'AWS EC2', hint: 'cria a instância via OpenTofu', fn: provisionEC2 },
  vultr: { label: 'Vultr', hint: 'cria a instância via OpenTofu', fn: provisionVultr },
};

export function providerOptions() {
  return Object.entries(PROVIDERS).map(([value, p]) => ({ value, label: p.label, hint: p.hint }));
}
