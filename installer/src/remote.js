// Remote install flow: pick group + provider, provision (or collect) the host,
// then run the shared deploy steps over SSH.
import { select } from './ui.js';
import { groupOptions } from './groups.js';
import { providerOptions, PROVIDERS } from './providers/index.js';
import { makeSSH } from './ssh.js';
import { deployToHost } from './deploy.js';

export async function runRemote() {
  const group = await select({ message: 'Qual grupo instalar no servidor?', options: groupOptions() });
  const providerName = await select({ message: 'Onde/como provisionar o host?', options: providerOptions() });

  const conn = await PROVIDERS[providerName].fn({ group });
  const ssh = makeSSH(conn);
  await deployToHost(ssh, group, { cloudInit: conn.cloudInit === true });
}
