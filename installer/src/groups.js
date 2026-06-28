// Per-group metadata. The group is the unit of deploy = one Lightsail/EC2/Vultr host.
// Compose file, Lightsail bundle, optional compose profiles, and whether the group
// needs GHCR (fork images: Plane on dev, Chatwoot on support).
export const GROUPS = {
  dev: {
    label: 'Dev — Forgejo + Mattermost + Plane',
    bundle: 'xlarge_2_0', // Lightsail 16 GB
    diskName: 'devtools-data',
    profiles: ['plane'],
    needsGHCR: true,
  },
  support: {
    label: 'Support — Planka + Chatwoot',
    bundle: 'large_2_0', // 8 GB
    diskName: 'support-data',
    profiles: [],
    needsGHCR: true,
  },
  admin: {
    label: 'Admin — Twenty CRM',
    bundle: 'large_2_0', // 8 GB
    diskName: 'admin-data',
    profiles: [],
    needsGHCR: false,
  },
  monitoring: {
    label: 'Monitoring — Beszel',
    bundle: 'small_2_0', // 2 GB
    diskName: 'monitoring-data',
    profiles: [],
    needsGHCR: false,
  },
};

export const GROUP_NAMES = Object.keys(GROUPS);

export function groupOptions() {
  return GROUP_NAMES.map((value) => ({ value, label: GROUPS[value].label }));
}

// `docker compose` args common to every invocation for a group.
export function composeArgs(group) {
  const dir = `deploy/${group}`;
  const args = ['compose', '-f', `${dir}/docker-compose.yml`, '--env-file', `${dir}/.env`];
  for (const prof of GROUPS[group].profiles) args.push('--profile', prof);
  return args;
}
