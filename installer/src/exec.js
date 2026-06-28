// Thin spawn wrapper. Two modes:
//   stream (default): child inherits stdout/stderr so the user sees live output.
//   capture: collect stdout/stderr into strings (for parsing CLI output).
// Optional stdin via `input` (string) or `inputFile` (path piped through stdin).
import { spawn } from 'node:child_process';
import { createReadStream } from 'node:fs';
import { REPO_ROOT } from './config.js';

export function run(cmd, args = [], opts = {}) {
  const {
    cwd = REPO_ROOT,
    env = process.env,
    capture = false,
    input = null,
    inputFile = null,
    allowNonZero = false,
  } = opts;

  return new Promise((resolve, reject) => {
    const stdin = input != null || inputFile != null ? 'pipe' : 'inherit';
    const stdout = capture ? 'pipe' : 'inherit';
    const child = spawn(cmd, args, { cwd, env, stdio: [stdin, stdout, capture ? 'pipe' : 'inherit'] });

    let out = '';
    let err = '';
    if (capture) {
      child.stdout.on('data', (d) => (out += d));
      child.stderr.on('data', (d) => (err += d));
    }

    if (input != null) {
      child.stdin.end(input);
    } else if (inputFile != null) {
      createReadStream(inputFile).pipe(child.stdin);
    }

    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0 || allowNonZero) resolve({ code, stdout: out, stderr: err });
      else reject(new Error(`${cmd} ${args.join(' ')} exited ${code}${err ? `\n${err}` : ''}`));
    });
  });
}

// Resolve to true/false instead of throwing — handy for "is X installed" checks.
export async function ok(cmd, args = [], opts = {}) {
  try {
    await run(cmd, args, { ...opts, capture: true, allowNonZero: false });
    return true;
  } catch {
    return false;
  }
}
