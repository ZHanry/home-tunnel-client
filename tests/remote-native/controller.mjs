import { RemoteApi, boundedResponse } from '/modules/remote/http.js';
import { RemoteSignal } from '/modules/remote/signal.js';
import { RemoteSession, selectedUdpPair } from '/modules/remote/session.js';
import { base64url, sha256, signJws, thumbprint } from '/modules/remote/identity.js';
import { canonicalJson, decodeFrame, encodeFrame, TYPES } from '/modules/remote/protocol.js';
import { RemoteInput } from '/modules/remote/input.js';
import { RemoteTransfers } from '/modules/remote/transfer.js';

let api, signal, session, host, assistInviteID, pairing, requestID, nonce, input, savedHeartbeat, transfers, pending = [], permissions = ['view'];
const fileState = { offers: [], progress: [], received: [] };
const video = document.querySelector('video');
const state = { phases: [], failures: [], input_releases: [], frames: 0 };
const fail = error => { state.failures.push(error?.code ?? 'RD_NATIVE_E2E_BROWSER_FAILED'); session?.fail(error); };
async function acceptCrossAccountTarget(target) {
  if (!target.invite_id || !target.host_endpoint_id || !target.host_owner_user_id || target.host_owner_user_id === api.userId ||
      target.host_jkt !== await thumbprint(target.host_public_jwk) || target.capabilities?.status !== 'ready' ||
      !target.capabilities.displays?.length) throw new Error('RD_PROOF_INVALID');
  assistInviteID = target.invite_id;
  host = { id: target.host_endpoint_id, owner_user_id: target.host_owner_user_id, jkt: target.host_jkt,
    capabilities: target.capabilities, online: true, local_enabled: true };
  return { host_id: host.id, invite_id: assistInviteID };
}
function frame(_time, metadata) {
  state.frames++;
  state.width = metadata.width; state.height = metadata.height;
  state.mediaTime = metadata.mediaTime;
  video.requestVideoFrameCallback(frame);
}
video.requestVideoFrameCallback(frame);
async function deliver(message) {
  if (!session) { if (message.type.startsWith('peer.')) pending.push(message); return; }
  if (message.session_id !== session.id || message.connection_epoch !== session.epoch) return;
  if (message.payload?.lease_jws && message.payload.lease_seq > session.lease.sequence) session.lease.update(await session.serverClaims(message.payload.lease_jws, 'ht-rd-lease+jwt', 'ht-rd-use'));
  await session.onSignal(message);
}
window.nativeE2E = {
  async initialize({ account_token: token, user_id: userID, input: withInput = false, files: withFiles = false, codec = null }) {
    permissions = withInput ? ['view', 'input.keyboard', 'input.pointer', 'input.text'] : ['view'];
    if (withFiles) permissions.push('files.send', 'files.receive');
    if (codec !== null) {
      if (!['H264', 'VP8'].includes(codec)) throw new Error('E2E_CODEC_INVALID');
      // Constrain the real browser offer in this isolated test page. The actual
      // native encoder, browser decoder, UDP transport and product session run
      // unchanged; these results cannot be inferred from advertised capability.
      const NativePeerConnection = window.RTCPeerConnection;
      window.RTCPeerConnection = class extends NativePeerConnection {
        addTransceiver(trackOrKind, init) {
          const transceiver = super.addTransceiver(trackOrKind, init);
          if (trackOrKind === 'video') {
            const available = RTCRtpReceiver.getCapabilities('video')?.codecs ?? [];
            const selected = available.filter(item => item.mimeType.toLowerCase() === `video/${codec.toLowerCase()}` && (codec !== 'H264' || /(?:^|;)\s*profile-level-id=42e01f(?:;|$)/i.test(item.sdpFmtpLine ?? '') && /(?:^|;)\s*packetization-mode=1(?:;|$)/i.test(item.sdpFmtpLine ?? '')));
            if (!selected.length || typeof transceiver.setCodecPreferences !== 'function') throw new Error('E2E_CODEC_NOT_AVAILABLE');
            transceiver.setCodecPreferences([...selected, ...available.filter(item => item.mimeType.toLowerCase() === 'video/rtx')]);
          }
          return transceiver;
        }
      };
    }
    const account = async (path, options = {}) => {
      const response = await fetch(path, { ...options, redirect: 'error', headers: { 'content-type': 'application/json', ...options.headers, authorization: `Bearer ${token}` } });
      const result = await boundedResponse(response);
      if (!response.ok) throw new Error(result.error_code ?? 'RD_ACCOUNT_FAILED');
      return result;
    };
    api = await new RemoteApi(account, userID).initialize();
    signal = new RemoteSignal(api, deliver, fail);
    await signal.connect();
    return { controller_id: api.identity.endpointId, controller_jkt: api.identity.jkt };
  },
  async findHost(hostID) {
    const result = await api.account('/api/v1/rd/endpoints?limit=100&offset=0');
    host = result.items.find(item => item.id === hostID);
    return !!(host?.online && host.local_enabled && host.capabilities?.status === 'ready');
  },
  async redeemAssist({ device_id, temporary_password }) {
    const target = await api.request('/api/v1/rd/assist-invites/redeem', { method: 'POST', body: { device_id, temporary_password } });
    return acceptCrossAccountTarget(target);
  },
  async redeemFixed({ device_id, password }) {
    const target = await api.request('/api/v1/rd/access/fixed/redeem', { method: 'POST', body: { device_id, password } });
    return acceptCrossAccountTarget(target);
  },
  async createAccessRequest(device_id) {
    const request = await api.request('/api/v1/rd/access/requests', { method: 'POST', body: { device_id } });
    return { id: request.id, expires_at: request.expires_at };
  },
  async awaitAccessRequest({ id, expires_at }) {
    while (Date.now() < Date.parse(expires_at)) {
      const result = await api.request(`/api/v1/rd/access/requests/${id}`);
      if (result.state === 'approved') return acceptCrossAccountTarget(result.target);
      if (result.state !== 'pending') throw new Error('RD_ACCESS_REJECTED');
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    throw new Error('RD_ACCESS_EXPIRED');
  },
  async pair() {
    if (!host?.capabilities?.displays?.length) throw new Error('RD_CAPTURE_UNAVAILABLE');
    requestID = crypto.randomUUID(); nonce = base64url(crypto.getRandomValues(new Uint8Array(32)));
    pairing = await api.request('/api/v1/rd/pairings', { method: 'POST', body: { host_endpoint_id: host.id, session_request_id: requestID, permissions, mode: 'one_session', nonce_controller: nonce,
      ...(assistInviteID ? { assist_invite_id: assistInviteID } : {}) } });
    return { id: pairing.id, request_id: requestID };
  },
  async confirm(expectedCode) {
    pairing = await api.request(`/api/v1/rd/pairings/${pairing.id}`);
    const proof = pairing.transcript;
    if (proof.host_endpoint_id !== host.id || proof.host_jkt !== host.jkt || proof.controller_endpoint_id !== api.identity.endpointId || proof.controller_jkt !== api.identity.jkt || proof.nonce_controller !== nonce || proof.server_instance_id !== api.keys.server_instance_id || proof.session_request_id !== requestID || proof.mode !== 'one_session' || canonicalJson(proof.scope) !== canonicalJson(permissions) || !proof.nonce_host ||
        (assistInviteID ? proof.assist_invite_id !== assistInviteID || proof.host_owner_user_id !== host.owner_user_id || proof.controller_owner_user_id !== api.userId : !!proof.assist_invite_id)) throw new Error('RD_PROOF_INVALID');
    const hash = await sha256(canonicalJson(proof));
    const code = [...hash.subarray(0, 16)].map(n => n.toString(16).padStart(2, '0')).join('').match(/.{4}/g).join('-');
    if (code !== expectedCode || pairing.display_code !== expectedCode) throw new Error('RD_PAIRING_CODE_MISMATCH');
    const confirmed = await api.request(`/api/v1/rd/pairings/${pairing.id}/confirm`, { method: 'POST', body: { signed_proof: await signJws(api.identity, proof, 'ht-rd-pairing+jwt') } });
    if (confirmed.state !== 'confirmed' || !confirmed.grant_id) throw new Error('RD_PAIRING_REQUIRED');
    await api.identity.rememberHost(host.id, host.jkt);
    const snapshot = await api.request('/api/v1/rd/sessions', { method: 'POST', idempotencyKey: requestID, body: { host_endpoint_id: host.id, grant_id: confirmed.grant_id, permissions, display_id: host.capabilities.displays[0].id, protocol: { major: 1, minor: 0 }, quality: 'balanced' } });
    return { session_id: snapshot.session_id };
  },
  async ticketReady(id) {
    const snapshot = await api.request(`/api/v1/rd/sessions/${id}`);
    return !!snapshot.ticket_jws;
  },
  async start(id) {
    const snapshot = await api.request(`/api/v1/rd/sessions/${id}`);
    if (!snapshot.ticket_jws) throw new Error('RD_LOCAL_APPROVAL_REQUIRED');
    state.frames = 0; state.failures = []; state.phases = []; state.input_releases = [];
    session = new RemoteSession({ api, signal, session: snapshot, hostThumbprint: host.jkt, hostOwnerUserId: host.owner_user_id ?? api.userId, video,
      onState(phase, error) { state.phases.push(phase); if (error) state.failures.push(error.code ?? 'RD_MEDIA_FAILED'); },
      onReconnectNeeded() { fail(new Error('RD_UNEXPECTED_RECONNECT')); },
      onControl: frame => transfers?.onFrame(frame),
      onFeatureRevoked: permission => transfers?.revoke(permission),
    });
    transfers = new RemoteTransfers(session, {
      onOffer: offer => fileState.offers.push(offer),
      onProgress: progress => { fileState.progress.push(progress); if (fileState.progress.length > 256) fileState.progress.shift(); },
    });
    input = new RemoteInput(session, video);
    // Local host candidates suffice for this same-machine direct UDP acceptance.
    await session.start([]);
    session.channels.get('control').addEventListener('message', event => {
      try {
        const frame = decodeFrame(event.data, 'control');
        if (frame.epoch === session.epoch && frame.type === TYPES.CONTROL_RELEASED && typeof frame.payload?.reason === 'string' && /^[A-Z_a-z]{1,80}$/.test(frame.payload.reason)) state.input_releases.push(frame.payload.reason);
      } catch { /* The production receiver handles malformed messages. */ }
    });
    for (const message of pending) await deliver(message);
    pending = [];
  },
  async evidence() {
    const stats = session?.pc ? await session.pc.getStats() : new Map();
    const pair = selectedUdpPair(stats);
    const values = [...stats.values()];
    const transport = values.find(item => item.type === 'transport' && item.selectedCandidatePairId);
    const inbound = values.find(item => item.type === 'inbound-rtp' && item.kind === 'video');
    const codec = inbound?.codecId ? stats.get(inbound.codecId) : null;
    const candidates = pair ? stats.get(pair.id) : null;
    const local = candidates ? stats.get(candidates.localCandidateId) : null;
    const remote = candidates ? stats.get(candidates.remoteCandidateId) : null;
    return { ...state, ready: session?.ready === true, closed: session?.closed !== false, peer_verified: session?.peerVerified === true,
      host_path_verified: session?.pathVerified === true, browser_udp_verified: pair?.verified === true,
      input_enabled: session?.inputEnabled === true, connection_state: session?.pc?.connectionState,
      input_epoch: session?.inputEpoch ?? 0,
      dtls_state: transport?.dtlsState, frames_decoded: inbound?.framesDecoded ?? 0, bytes_received: inbound?.bytesReceived ?? 0,
      video_codec: codec?.mimeType ?? null, video_codec_parameters: codec?.sdpFmtpLine ?? null,
      video_decoder_implementation: inbound?.decoderImplementation ?? null, video_power_efficient_decoder: inbound?.powerEfficientDecoder ?? null,
      input_frames_sent: session?.sequences.get('input') ?? 0, input_buffered_bytes: session?.channels.get('input')?.bufferedAmount ?? 0,
      local_candidate: local ? { protocol: local.protocol, type: local.candidateType } : null,
      remote_candidate: remote ? { protocol: remote.protocol, type: remote.candidateType } : null };
  },
  prepareInput() { video.focus(); },
  requestInput() { session.requestInput(); },
  sendKey() {
    if (!input.allowed('input.keyboard')) throw new Error('RD_INPUT_DENIED');
    const event = { code: 'KeyA', repeat: false, preventDefault() {} };
    input.key(event, true); input.key(event, false);
    return { frames_sent: session.sequences.get('input') ?? 0, held_keys: input.keys.size };
  },
  async sendText() { return await input.submitText('验收✓'); },
  holdKey() {
    if (!input.allowed('input.keyboard')) throw new Error('RD_INPUT_DENIED');
    input.key({ code: 'KeyA', repeat: false, preventDefault() {} }, true);
  },
  sendStaleInput(epoch) {
    if (!session.inputEnabled || !Number.isInteger(epoch) || epoch < 1 || epoch >= session.inputEpoch) throw new Error('RD_STATE_CONFLICT');
    const payload = new Uint8Array(8), view = new DataView(payload.buffer);
    view.setUint16(0, 7); view.setUint16(2, 4); view.setUint8(4, 1);
    const sequence = (session.sequences.get('input') ?? 0) + 1;
    session.channels.get('input').send(encodeFrame(TYPES.KEY, payload, { epoch: session.epoch, inputEpoch: epoch, sequence }));
    session.sequences.set('input', sequence);
  },
  pauseHeartbeat() { savedHeartbeat = session.sendInputHeartbeat; session.sendInputHeartbeat = () => {}; },
  restoreHeartbeat() { if (savedHeartbeat) { session.sendInputHeartbeat = savedHeartbeat; savedHeartbeat = null; } },
  sendPointer({ x, y, width, height, hold = false }) {
    if (!session.inputEnabled || !session.permissions.has('input.pointer')) throw new Error('RD_INPUT_DENIED');
    const display = session.layout.displays.find(item => item.id === session.layout.active_display);
    if (width !== display.width_px || height !== display.height_px || x < 0 || y < 0 || x >= width || y >= height) throw new Error('RD_INPUT_COORDINATE_INVALID');
    const coordinate = (value, maximum) => Math.round(value / Math.max(1, maximum - 1) * 65535);
    const payload = down => {
      const bytes = new Uint8Array(32), view = new DataView(bytes.buffer);
      view.setUint32(0, session.layout.layout_epoch); view.setUint16(4, display.slot);
      view.setUint16(6, coordinate(x, width)); view.setUint16(8, coordinate(y, height));
      view.setUint8(10, 1); view.setUint8(11, down ? 1 : 0); view.setUint32(12, ++input.motion);
      return bytes;
    };
    session.send(TYPES.BUTTON, payload(true)); input.buttons = 1;
    if (!hold) { session.send(TYPES.BUTTON, payload(false)); input.buttons = 0; }
  },
  releaseInput() { input.release(); },
  async enableFiles() { await session.setFeature('files.send', true); await session.setFeature('files.receive', true); },
  fileEvidence() { return structuredClone(fileState); },
  async offerFiles() {
    const bytes = Uint8Array.from({ length: 1048593 }, (_, n) => (n * 31 + 17) & 255);
    await transfers.offerFiles([new File([], 'browser-empty.bin'), new File([bytes], 'browser-multichunk.bin')]);
  },
  async acceptFile(id) {
    const offer = fileState.offers.find(item => item.id === id);
    if (!offer || !['native-empty.bin', 'native-multichunk.bin'].includes(offer.name)) throw new Error('E2E_FILE_NAME_INVALID');
    // The origin-private browser filesystem uses real streaming writes. This
    // fixture deliberately does not count as a user save-picker acceptance.
    const directory = await navigator.storage.getDirectory();
    const handle = await directory.getFileHandle(offer.name, { create: true });
    const sink = await handle.createWritable();
    await transfers.acceptFile(id, {
      write: bytes => sink.write(bytes), abort: () => sink.abort(),
      async close() {
        await sink.close(); const saved = await handle.getFile();
        const digest = await crypto.subtle.digest('SHA-256', await saved.arrayBuffer());
        fileState.received.push({ id, name: offer.name, size: saved.size, sha256: [...new Uint8Array(digest)].map(n => n.toString(16).padStart(2, '0')).join('') });
      },
    });
  },
  async cancelFile(id) { await transfers.cancel(id); },
  async disableFiles() { await session.setFeature('files.send', false); await session.setFeature('files.receive', false); },
  async closeSession() { input?.close(); session?.close(); await session?.closeRequest; session = null; input = null; pending = []; },
  async close() { await transfers?.close(); input?.close(); session?.close(); await session?.closeRequest; signal?.close(); api?.close(); },
};
