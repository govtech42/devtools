// SSH interface — shell-out to the system ssh/scp/rsync behind a small surface.
// Swapping to node-ssh/ssh2 later means reimplementing only this module.
import { run, ok } from './exec.js';

const BASE_OPTS = ['-o', 'StrictHostKeyChecking=accept-new', '-o', 'BatchMode=yes'];

export function makeSSH({ host, user = 'ubuntu', keyPath }) {
  const target = `${user}@${host}`;
  const idOpts = keyPath ? ['-i', keyPath] : [];
  const sshOpts = [...idOpts, ...BASE_OPTS];

  return {
    host,
    user,
    keyPath,
    target,

    // Run a command on the remote host (streams output).
    exec(remoteCmd, opts = {}) {
      return run('ssh', [...sshOpts, target, remoteCmd], opts);
    },

    // Pipe a local script file to `bash -s` on the remote (idempotent bootstrap).
    execScript(localScriptPath, opts = {}) {
      return run('ssh', [...sshOpts, target, 'bash -s'], { ...opts, inputFile: localScriptPath });
    },

    // Quick reachability check; returns true/false, never throws.
    async testConnection() {
      return ok('ssh', [...sshOpts, '-o', 'ConnectTimeout=10', target, 'echo ok']);
    },

    // Copy a single local file to a remote path.
    upload(localPath, remotePath) {
      const scpOpts = [...idOpts, ...BASE_OPTS];
      return run('scp', [...scpOpts, localPath, `${target}:${remotePath}`]);
    },

    // rsync a local directory to the remote (used to ship the repo).
    rsync(localDir, remoteDir, excludes = []) {
      const ex = excludes.flatMap((e) => ['--exclude', e]);
      const sshCmd = `ssh ${sshOpts.join(' ')}`;
      return run('rsync', ['-az', ...ex, '-e', sshCmd, localDir, `${target}:${remoteDir}`]);
    },
  };
}
