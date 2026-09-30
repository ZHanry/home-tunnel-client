// UI wording is not media or input evidence. Keep the acceptance predicates
// independent of translation while requiring real rendering and transport data.
export function verifiedWebsiteMedia(evidence) {
  return !!evidence && evidence.viewer_live === true && evidence.video_paused === false &&
    evidence.media_mask_hidden === true && evidence.host_udp_verified === true && evidence.browser_udp_verified === true &&
    evidence.connection_state === 'connected' && evidence.dtls_state === 'connected' &&
    Number.isInteger(evidence.video_ready_state) && evidence.video_ready_state >= 2 &&
    Number.isFinite(evidence.video_current_time) && evidence.video_current_time >= 0 &&
    Number.isFinite(evidence.frames_decoded) && evidence.frames_decoded >= 5 &&
    Number.isFinite(evidence.bytes_received) && evidence.bytes_received > 0 &&
    Number.isFinite(evidence.width) && evidence.width > 0 && Number.isFinite(evidence.height) && evidence.height > 0;
}

export function websiteInputGranted(controls, native) {
  return controls?.release_visible === true && controls.release_enabled === true &&
    native?.input_enabled === true && Number.isSafeInteger(native.input_epoch) && native.input_epoch > 0;
}

export async function collectFailureMedia(page, kind, previous, readWebsite) {
  try {
    const observed = kind === 'website' ? await readWebsite(page) : await page.evaluate(() => window.nativeE2E?.evidence());
    return observed ?? previous;
  } catch { return previous; }
}
