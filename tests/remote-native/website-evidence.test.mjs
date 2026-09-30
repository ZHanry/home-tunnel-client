// Predicate tests only. These fixtures cannot establish native media success.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { verifiedWebsiteMedia, websiteInputGranted, collectFailureMedia } from './website-evidence.mjs';

const measured = { viewer_live: true, video_paused: false, media_mask_hidden: true, host_udp_verified: true,
  browser_udp_verified: true, connection_state: 'connected', dtls_state: 'connected', frames_decoded: 6,
  bytes_received: 500, width: 1024, height: 768, video_ready_state: 4, video_current_time: 0.5, status: '已连接 · 可控制' };
test('localized wording cannot replace or prevent genuine media evidence', () => {
  assert.equal(verifiedWebsiteMedia(measured), true);
  assert.equal(verifiedWebsiteMedia({ ...measured, status: 'Connected' }), true);
  assert.equal(verifiedWebsiteMedia({ status: 'UDP 已连接' }), false);
});
test('every live rendering, UDP and DTLS condition must be observed', () => {
  for (const [key, value] of Object.entries({ viewer_live: false, video_paused: true, media_mask_hidden: false,
    host_udp_verified: false, browser_udp_verified: false, connection_state: 'connecting', dtls_state: 'connecting',
    frames_decoded: 0, bytes_received: 0, width: 0, height: 0, video_ready_state: 1, video_current_time: -1 })) {
    assert.equal(verifiedWebsiteMedia({ ...measured, [key]: value }), false, key);
    const omitted = { ...measured }; delete omitted[key];
    assert.equal(verifiedWebsiteMedia(omitted), false, `missing ${key}`);
  }
  assert.equal(verifiedWebsiteMedia(null), false);
  assert.equal(verifiedWebsiteMedia({ ...measured, frames_decoded: NaN }), false);
});
test('native input grant requires visible control and backend acknowledgment', () => {
  const controls = { release_visible: true, release_enabled: true };
  const native = { input_enabled: true, input_epoch: 1 };
  assert.equal(websiteInputGranted(controls, native), true);
  assert.equal(websiteInputGranted(controls, { ...native, input_enabled: false }), false);
  assert.equal(websiteInputGranted(controls, { ...native, input_epoch: 0 }), false);
  assert.equal(websiteInputGranted({ ...controls, release_visible: false }, native), false);
});
test('website failures retain website stats rather than missing harness globals', async () => {
  const page = { evaluate() { throw new Error('website must not query nativeE2E'); } };
  const snapshot = { ...measured, frames_decoded: 0 };
  assert.deepEqual(await collectFailureMedia(page, 'website', measured, async actual => {
    assert.equal(actual, page); return snapshot;
  }), snapshot);
  assert.deepEqual(await collectFailureMedia(page, 'website', measured, async () => undefined), measured);
  assert.deepEqual(await collectFailureMedia(page, 'website', measured, async () => { throw new Error('closed'); }), measured);
});
test('popout shutdown uses the real disconnect control and requires native idle', () => {
  const runner = readFileSync(new URL('../../scripts/test-remote-native.mjs', import.meta.url), 'utf8');
  assert.match(runner, /stage = 'website_shutdown';\s+await page\.locator\('\.remote-dialog \[data-disconnect\]'\)\.click\(\);\s+await until\(async \(\) => \(await rpc\('state'\)\)\.session_idle/);
  assert.doesNotMatch(runner, /page\.locator\('\.remote-dialog \[data-close\]'\)\.click/);
});
