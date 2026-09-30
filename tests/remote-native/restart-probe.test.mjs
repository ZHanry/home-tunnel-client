// Synthetic safety/regression tests only, never native recovery acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { failureMetadata } from './failure-metadata.mjs';
const runner = fileURLToPath(new URL('../../scripts/test-remote-native.mjs', import.meta.url));
test('diagnostic metadata exposes only fixed type, source basename and numeric coordinates', () => {
  const value = failureMetadata({ name: 'TypeError', message: 'secret bearer opaque', code: 'PRIVATE_TOKEN',
    stack: 'TypeError: secret bearer opaque\n at f (https://127.0.0.1:123/private?token=opaque/controller.mjs:78:4)\n at g (D:\\private-user\\scripts\\test-remote-native.mjs:703:31)\n at h (https://private.invalid/private.mjs:8:9)' });
  assert.deepEqual(value, { exception_type: 'TypeError', source_locations: [{ source: 'controller.mjs', line: 78, column: 4 }, { source: 'test-remote-native.mjs', line: 703, column: 31 }] });
  assert.doesNotMatch(JSON.stringify(value), /opaque|bearer|private|https|127\.0\.0\.1/);
});
test('unknown error names, large stacks and unapproved source names are never copied', () => {
  assert.deepEqual(failureMetadata({ name: 'SECRET', stack: 'token' }), { exception_type: 'OtherError', source_locations: [] });
  assert.equal(failureMetadata({ name: 'Error', stack: 'x'.repeat(8192) + '/controller.mjs:12:1' }).source_locations.length, 0);
  assert.equal(failureMetadata({ name: 'Error', stack: Array(20).fill('/controller.mjs:1:1').join('\n') }).source_locations.length, 3);
});
for (const extra of [['--stability', '30x7200'], ['--mode', 'cross-account-assist'], ['--files', 'fixture'], ['--codec', 'VP8'], ['--controller', 'website'], ['--server-source', 'working-tree']]) test(`probe rejects expanded or mixed scope ${extra.join(' ')}`, () => {
  const run = spawnSync(process.execPath, [runner, '--input', 'chromium', '--restart-probe', 'same-identity', ...extra], { timeout: 5000, encoding: 'utf8' });
  assert.equal(run.status, 2); assert.match(run.stderr, /Invalid acceptance mode/);
});
test('probe cannot be requested without the confined input target or with unknown mode', () => {
  for (const args of [['--restart-probe', 'same-identity'], ['--restart-probe', 'arbitrary-process', '--input', 'chromium']]) {
    const result = spawnSync(process.execPath, [runner, ...args], { timeout: 5000, encoding: 'utf8' }); assert.equal(result.status, 2);
  }
});
test('probe shares exact owned restart path and retains per-await substages', () => {
  const source = readFileSync(runner, 'utf8');
  for (const stage of ['restart_close_crashed_session', 'restart_stop_owned_host', 'restart_start_owned_host', 'restart_send_private_configuration', 'restart_await_backend', 'restart_verify_same_identity', 'restart_bind_controller', 'restart_find_host', 'restart_measure_live_input', 'restart_release_input', 'restart_close_recovered_session', 'restart_await_recovered_idle']) assert.ok(source.includes(`stage = '${stage}'`), stage);
  assert.match(source, /if \(withNativeFixture\) \{\s+stage = 'restart_close_crashed_session'/);
  assert.match(source, /openStabilitySession\('restart'\)/); assert.match(source, /proveStabilitySessionInput\('restart'\)/);
  assert.match(source, /let crashSession = created;\s+if \(!withRestartProbe\)/);
  assert.match(source, /withNativeFixture \? failureMetadata\(error\)/);
  assert.doesNotMatch(source, /console\.(?:log|error)\(error\.(?:stack|message)\)/);
});
test('strict stability targets remain unchanged and probe has separate classification', () => {
  const source = readFileSync(runner, 'utf8');
  assert.match(source, /if \(withStability\) \{\s+report.stability =/);
  assert.match(source, /if \(withRestartProbe\) report.restart_probe =/);
  assert.match(source, /timeout_seconds: 600/);
  assert.match(readFileSync(new URL('./stability.mjs', import.meta.url), 'utf8'), /sessions: 30, active_ms: 7_200_000/);
});
