// These negative preflight tests are not media acceptance evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const runner = fileURLToPath(new URL('../../scripts/test-remote-native.mjs', import.meta.url));
const supported = process.platform === 'win32' && Number(process.versions.node.split('.')[0]) === 24;
for (const [name, code, setup] of [
  ['missing native worker cannot pass', 'E2E_NATIVE_WORKER_MISSING', () => []],
  ['worker without a pinned hash cannot run', 'E2E_PINNED_SHA256_REQUIRED', dir => {
    const file = join(dir, 'untrusted.exe'); writeFileSync(file, 'must not execute');
    return ['--worker', file];
  }],
  ['wrong native hash cannot run', 'E2E_NATIVE_HASH_MISMATCH', dir => {
    const file = join(dir, 'untrusted.exe'); writeFileSync(file, 'must not execute');
    return ['--worker', file, '--sha256', '0'.repeat(64)];
  }],
]) {
  test(name, { skip: !supported && 'Windows + Node 24 required for this native acceptance preflight' }, () => {
    const directory = mkdtempSync(join(tmpdir(), 'ht-native-policy-'));
    try {
      const run = spawnSync(process.execPath, [runner, ...setup(directory), '--report-dir', directory], { windowsHide: true, timeout: 15000, encoding: 'utf8' });
      assert.equal(run.status, 1);
      const report = JSON.parse(readFileSync(join(directory, 'report.json'), 'utf8'));
      assert.equal(report.status, 'not_verified');
      assert.equal(report.failure.code, code);
      assert.equal(report.checks.native_backend_ready, undefined);
      assert.equal(report.checks.real_continuing_video, undefined);
      assert.equal(report.input.status, 'not_verified');
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
}
