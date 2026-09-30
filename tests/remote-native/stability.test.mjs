// Predicate tests only. Synthetic samples below are never acceptance evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { STABILITY, activeMedia, checkSample, checkCompletedWindow } from './stability.mjs';
const sample = (n = 0) => ({ media_state: { peer_verified: true, host_path_verified: true, browser_udp_verified: true, input_enabled: true, lease_valid: true, signal_authenticated: true, connection_state: 'connected', dtls_state: 'connected' }, elapsed_ms: 100 + n * 5000, wall_ms: 1_000_000 + n * 5000, target_ms: 1000 + n * 5000,
  frames_decoded: 100 + n, frames_presented: 100 + n, bytes_received: 1000 + n, video_time: 1 + n,
  input_frames_sent: 10 + n, native_input_accepted: 10 + n, native_frames_encoded: 100 + n,
  lease_sequence: 1, controller_token_refreshes: 0,
  input_events: ['keydown', 'keyup', 'pointerdown', 'pointerup'].map(type => ({ type, code: type.startsWith('key') ? 'KeyA' : null, trusted: true, target_matches: true, offset_ms: 5 })) });
const media = () => ({ ready: true, closed: false, peer_verified: true, host_path_verified: true, browser_udp_verified: true,
  connection_state: 'connected', dtls_state: 'connected', input_enabled: true, lease_valid: true, signal_authenticated: true,
  frames: 5, frames_decoded: 5, bytes_received: 5000, width: 900, height: 700, failures: [] });
test('acceptance constants cannot be shortened by a duration flag', () => {
  assert.equal(STABILITY.sessions, 30); assert.equal(STABILITY.active_ms, 7200000); assert.equal(STABILITY.case_timeout_seconds, 10800); assert.ok(Object.isFrozen(STABILITY));
});
test('only currently authenticated, live media with enabled native input is eligible', () => {
  assert.equal(activeMedia(media()), true);
  for (const [key, value] of Object.entries({ ready: false, closed: true, peer_verified: false, host_path_verified: false, browser_udp_verified: false, connection_state: 'disconnected', dtls_state: 'connecting', input_enabled: false, lease_valid: false, signal_authenticated: false, frames: 0, frames_decoded: 0, bytes_received: 0, width: 0, height: 0, failures: ['failure'] })) assert.equal(activeMedia({ ...media(), [key]: value }), false, key);
});
test('valid consecutive activity observations pass predicates', () => { checkSample(null, sample()); checkSample(sample(), sample(1)); });
for (const key of ['frames_decoded', 'frames_presented', 'bytes_received', 'video_time', 'input_frames_sent', 'native_input_accepted', 'native_frames_encoded']) test(`stalled ${key} fails closed`, () => {
  assert.throws(() => checkSample(sample(), { ...sample(1), [key]: sample()[key] }), /ACTIVITY_STALLED/);
});
test('nonfinite counters, no trusted input, wrong target or stale events fail', () => {
  assert.throws(() => checkSample(null, { ...sample(), native_input_accepted: NaN }), /INVALID_METRIC/);
  assert.throws(() => checkSample(null, { ...sample(), input_events: [] }), /TRUSTED_INPUT_MISSING/);
  for (const change of [{ trusted: false }, { target_matches: false }, { offset_ms: -1 }, { offset_ms: 3001 }]) {
    const value = sample(); Object.assign(value.input_events[0], change);
    assert.throws(() => checkSample(null, value), /TRUSTED_INPUT_MISSING/);
  }
});
test('long observation gaps and wall-clock jumps cannot count as active time', () => {
  assert.throws(() => checkSample(sample(), { ...sample(1), elapsed_ms: 20000 }), /OBSERVATION_GAP/);
  assert.throws(() => checkSample(sample(), { ...sample(1), wall_ms: 1_100_000 }), /CLOCK_INVALID/);
  assert.throws(() => checkSample(sample(), { ...sample(1), elapsed_ms: 100 }), /OBSERVATION_GAP/);
  assert.throws(() => checkSample(sample(), { ...sample(1), target_ms: 999 }), /CLOCK_INVALID/);
});
test('7200 seconds requires real progression and renewal counters', () => {
  const first = sample(); const last = { ...sample(1440), lease_sequence: 31, controller_token_refreshes: 12 };
  checkCompletedWindow(first, last, 1441);
  assert.throws(() => checkCompletedWindow(first, { ...last, elapsed_ms: last.elapsed_ms - 1 }, 1441), /DURATION_INCOMPLETE/);
  assert.throws(() => checkCompletedWindow(first, last, 480), /DURATION_INCOMPLETE/);
  assert.throws(() => checkCompletedWindow(first, { ...last, lease_sequence: 1 }, 1441), /RENEWALS_NOT_OBSERVED/);
  assert.throws(() => checkCompletedWindow(first, { ...last, controller_token_refreshes: 0 }, 1441), /RENEWALS_NOT_OBSERVED/);
  assert.throws(() => checkCompletedWindow(first, { ...last, wall_ms: last.wall_ms + 5001 }, 1441), /CLOCK_INVALID/);
});
const runner = fileURLToPath(new URL('../../scripts/test-remote-native.mjs', import.meta.url));
for (const flags of [[], ['--files', 'fixture'], ['--controller', 'website'], ['--mode', 'cross-account-assist'], ['--server-source', 'working-tree'], ['--codec', 'VP8']]) test(`strict long mode rejects unsafe/inapplicable combination ${flags.join(' ')}`, () => {
  const args = ['--stability', '30x7200', ...(flags.length ? ['--input', 'chromium', ...flags] : [])];
  const run = spawnSync(process.execPath, [runner, ...args], { timeout: 5000, encoding: 'utf8' });
  assert.equal(run.status, 2); assert.match(run.stderr, /Invalid acceptance mode/);
});
test('test host grant and timeout extension is opt-in, input-confined and same-account-only', () => {
  const host = readFileSync(new URL('./host/main.go', import.meta.url), 'utf8');
  assert.match(host, /duration := 4 \* time.Minute/); assert.match(host, /grantDuration := 3 \* time.Minute/);
  assert.match(host, /if initial.Stability/); assert.match(host, /initial.InputTargetPID == 0/);
  assert.match(host, /duration, grantDuration = 3\*time.Hour, 3\*time.Hour/);
  const harness = readFileSync(runner, 'utf8');
  assert.match(harness, /buildArguments.push\('-overlay', overlay\)/);
  assert.match(harness, /ACCESS_TOKEN_SECONDS: '10800'/);
  assert.match(harness, /\[data-disconnect\]/); assert.doesNotMatch(harness, /\[data-close\]/);
});
test('connections precede the two-hour window and extra crash sessions follow it', () => {
  const source = readFileSync(runner, 'utf8');
  assert.ok(source.indexOf('ordinal < STABILITY.sessions') < source.indexOf('await observeActiveWindow('));
  assert.ok(source.indexOf('await observeActiveWindow(') < source.indexOf("stage = 'worker_crash'"));
  assert.match(source, /while \(performance.now\(\) - previousPairingStarted < 15000\)/);
  assert.match(source, /new Set\(report.stability.sessions.map\(item => item.session_id_sha256\)\).size === STABILITY.sessions/);
});
