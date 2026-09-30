// QA-only observations. Durations, decoded frames and native input events are
// measured from the live browser/worker; no test clock can shorten acceptance.
import { appendFileSync } from 'node:fs';
export const STABILITY = Object.freeze({ sessions: 30, active_ms: 7_200_000, sample_ms: 5000, maximum_gap_ms: 15000, maximum_clock_skew_ms: 5000, case_timeout_seconds: 10800 });
const requireValue = (value, code) => { if (!value) { const error = new Error(code); error.code = code; throw error; } };
export function activeMedia(e) {
  return !!e && e.ready === true && e.closed === false && e.peer_verified === true && e.host_path_verified === true && e.browser_udp_verified === true && e.connection_state === 'connected' && e.dtls_state === 'connected' && e.input_enabled === true && e.lease_valid === true && e.signal_authenticated === true && e.frames >= 5 && e.frames_decoded >= 5 && e.bytes_received > 0 && e.width > 0 && e.height > 0 && Array.isArray(e.failures) && e.failures.length === 0;
}
export function checkSample(previous, sample) {
  const counters = ['elapsed_ms', 'wall_ms', 'target_ms', 'frames_decoded', 'frames_presented', 'bytes_received', 'video_time', 'input_frames_sent', 'native_input_accepted', 'native_frames_encoded', 'lease_sequence', 'controller_token_refreshes'];
  requireValue(sample.media_state && ['peer_verified', 'host_path_verified', 'browser_udp_verified', 'input_enabled', 'lease_valid', 'signal_authenticated'].every(key => sample.media_state[key] === true) && sample.media_state.connection_state === 'connected' && sample.media_state.dtls_state === 'connected', 'E2E_STABILITY_ACTIVE_MEDIA_LOST');
  requireValue(counters.every(key => Number.isFinite(sample[key]) && sample[key] >= 0), 'E2E_STABILITY_INVALID_METRIC');
  requireValue(sample.input_events.length === 4 && ['keydown', 'keyup', 'pointerdown', 'pointerup'].every(type => sample.input_events.some(event => event.type === type && event.trusted === true && event.target_matches === true && Number.isFinite(event.offset_ms) && event.offset_ms >= 0 && event.offset_ms <= 3000 && (!type.startsWith('key') || event.code === 'KeyA'))), 'E2E_STABILITY_TRUSTED_INPUT_MISSING');
  if (!previous) return;
  const elapsed = sample.elapsed_ms - previous.elapsed_ms;
  requireValue(elapsed > 0 && elapsed <= STABILITY.maximum_gap_ms, 'E2E_STABILITY_OBSERVATION_GAP');
  requireValue(Math.abs(sample.wall_ms - previous.wall_ms - elapsed) <= STABILITY.maximum_clock_skew_ms && sample.wall_ms > previous.wall_ms && sample.target_ms > previous.target_ms && Math.abs(sample.target_ms - previous.target_ms - elapsed) <= STABILITY.maximum_clock_skew_ms, 'E2E_STABILITY_CLOCK_INVALID');
  for (const key of ['frames_decoded', 'frames_presented', 'bytes_received', 'video_time', 'input_frames_sent', 'native_input_accepted', 'native_frames_encoded']) requireValue(sample[key] > previous[key], 'E2E_STABILITY_ACTIVITY_STALLED');
  requireValue(sample.lease_sequence >= previous.lease_sequence && sample.controller_token_refreshes >= previous.controller_token_refreshes, 'E2E_STABILITY_COUNTER_REGRESSED');
}
export function checkCompletedWindow(first, last, samples) {
  requireValue(last.elapsed_ms - first.elapsed_ms >= STABILITY.active_ms && samples >= Math.floor(STABILITY.active_ms / STABILITY.maximum_gap_ms) + 1, 'E2E_STABILITY_DURATION_INCOMPLETE');
  requireValue(Math.abs((last.wall_ms - first.wall_ms) - (last.elapsed_ms - first.elapsed_ms)) <= STABILITY.maximum_clock_skew_ms, 'E2E_STABILITY_CLOCK_INVALID');
  requireValue(last.lease_sequence > first.lease_sequence && last.controller_token_refreshes > first.controller_token_refreshes, 'E2E_STABILITY_RENEWALS_NOT_OBSERVED');
}
export async function observeInputCycle({ page, target, rpc, until, requireCheck, started, point }) {
  requireCheck((await rpc('input_focus')).foreground_matches_target, 'E2E_STABILITY_TARGET_LOST_FOREGROUND');
  const before = await target.evaluate(() => {
    if (!document.hasFocus() || document.activeElement !== document.querySelector('#input-target')) return null;
    document.querySelector('#input-target').value = '';
    window.nativeInputTarget.events = [];
    return performance.now();
  });
  requireCheck(Number.isFinite(before), 'E2E_STABILITY_TARGET_LOST_FOCUS');
  await page.evaluate(value => { window.nativeE2E.sendPointer(value); window.nativeE2E.sendKey(); }, point);
  await until(() => target.evaluate(() => ['keydown', 'keyup', 'pointerdown', 'pointerup'].every(type => window.nativeInputTarget.events.some(event => event.type === type && event.trusted === true && event.target_matches && (!type.startsWith('key') || event.code === 'KeyA')))), 'E2E_STABILITY_NATIVE_INPUT_NOT_OBSERVED', 3000);
  const media = await page.evaluate(() => window.nativeE2E.evidence());
  requireCheck(activeMedia(media), 'E2E_STABILITY_ACTIVE_MEDIA_LOST');
  const native = (await rpc('diagnostics')).native;
  requireCheck(native.input_enabled === true, 'E2E_STABILITY_NATIVE_INPUT_DISABLED');
  const input = await target.evaluate(start => ({ target_ms: performance.now(), events: ['keydown', 'keyup', 'pointerdown', 'pointerup'].map(type => {
    const event = window.nativeInputTarget.events.find(item => item.type === type && (!type.startsWith('key') || item.code === 'KeyA'));
    return { type, code: event?.code ?? null, trusted: event?.trusted === true, target_matches: event?.target_matches === true, offset_ms: event ? event.timestamp - start : null };
  }) }), before);
  return { media_state: Object.fromEntries(['peer_verified', 'host_path_verified', 'browser_udp_verified', 'input_enabled', 'lease_valid', 'signal_authenticated', 'connection_state', 'dtls_state'].map(key => [key, media[key]])),
    elapsed_ms: performance.now() - started, wall_ms: Date.now(), target_ms: input.target_ms,
    frames_decoded: media.frames_decoded, frames_presented: media.frames, bytes_received: media.bytes_received, video_time: media.mediaTime,
    input_frames_sent: media.input_frames_sent, native_input_accepted: native.input_accepted, native_frames_encoded: native.video_frames_encoded,
    lease_sequence: media.lease_sequence, controller_token_refreshes: media.controller_token_refreshes, input_events: input.events };
}
export async function observeActiveWindow(options, path, progress) {
  const started = performance.now();
  let first, previous, count = 0;
  for (;;) {
    const sample = await observeInputCycle({ ...options, started });
    appendFileSync(path, `${JSON.stringify({ sample: ++count, ...sample })}\n`, { mode: 0o600 });
    checkSample(previous, sample);
    first ??= sample;
    previous = sample;
    progress({ samples: count, active_seconds: (sample.elapsed_ms - first.elapsed_ms) / 1000 });
    if (sample.elapsed_ms - first.elapsed_ms >= STABILITY.active_ms) break;
    await new Promise(resolve => setTimeout(resolve, STABILITY.sample_ms));
  }
  checkCompletedWindow(first, previous, count);
  return { status: 'passed', actual_active_seconds: (previous.elapsed_ms - first.elapsed_ms) / 1000, samples: count, maximum_allowed_sample_gap_ms: STABILITY.maximum_gap_ms, first, last: previous };
}
