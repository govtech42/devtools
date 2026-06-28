// Shared paths. The installer lives in <repo>/installer; everything it drives
// (Makefile, deploy/, infra/, test/) is relative to the repo root.
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
