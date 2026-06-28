// clack/prompts + picocolors helpers. Every prompt is funnelled through these so
// Ctrl-C / Esc (clack "cancel") consistently aborts the installer.
import * as p from '@clack/prompts';
import pc from 'picocolors';

export { p, pc };

export function bail(message = 'Cancelado.') {
  p.cancel(message);
  process.exit(0);
}

function unwrap(value) {
  if (p.isCancel(value)) bail();
  return value;
}

export const intro = (s) => p.intro(s);
export const outro = (s) => p.outro(s);
export const note = (msg, title) => p.note(msg, title);
export const log = p.log;

export async function select(opts) {
  return unwrap(await p.select(opts));
}

export async function multiselect(opts) {
  return unwrap(await p.multiselect(opts));
}

export async function text(opts) {
  return unwrap(await p.text(opts));
}

export async function confirm(opts) {
  return unwrap(await p.confirm(opts));
}

// spinner that runs an async task and reports start/stop messages.
export async function task(startMsg, stopMsg, fn) {
  const s = p.spinner();
  s.start(startMsg);
  try {
    const result = await fn(s);
    s.stop(stopMsg ?? startMsg);
    return result;
  } catch (e) {
    s.stop(pc.red(`falhou: ${startMsg}`));
    throw e;
  }
}
