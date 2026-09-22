import { RemoteApi, boundedResponse } from '/modules/remote/http.js';
import { RemoteSignal } from '/modules/remote/signal.js';
import { RemoteSession, selectedUdpPair } from '/modules/remote/session.js';
import { base64url, sha256, signJws } from '/modules/remote/identity.js';
import { canonicalJson } from '/modules/remote/protocol.js';

let api, signal, session, host, pairing, requestID, nonce, pending = [];
const video = document.querySelector('video');
const state = { phases: [], failures: [], frames: 0 };
const fail = error => { state.failures.push(error?.code ?? 'RD_NATIVE_E2E_BROWSER_FAILED'); session?.fail(error); };
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
  async initialize({ account_token: token, user_id: userID }) {
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
  async pair() {
    if (!host?.capabilities?.displays?.length) throw new Error('RD_CAPTURE_UNAVAILABLE');
    requestID = crypto.randomUUID(); nonce = base64url(crypto.getRandomValues(new Uint8Array(32)));
    pairing = await api.request('/api/v1/rd/pairings', { method: 'POST', body: { host_endpoint_id: host.id, session_request_id: requestID, permissions: ['view'], mode: 'one_session', nonce_controller: nonce } });
    return { id: pairing.id, request_id: requestID };
  },
  async confirm(expectedCode) {
    pairing = await api.request(`/api/v1/rd/pairings/${pairing.id}`);
    const proof = pairing.transcript;
    if (proof.host_endpoint_id !== host.id || proof.host_jkt !== host.jkt || proof.controller_endpoint_id !== api.identity.endpointId || proof.controller_jkt !== api.identity.jkt || proof.nonce_controller !== nonce || proof.server_instance_id !== api.keys.server_instance_id || proof.session_request_id !== requestID || proof.mode !== 'one_session' || canonicalJson(proof.scope) !== canonicalJson(['view']) || !proof.nonce_host) throw new Error('RD_PROOF_INVALID');
    const hash = await sha256(canonicalJson(proof));
    const code = [...hash.subarray(0, 16)].map(n => n.toString(16).padStart(2, '0')).join('').match(/.{4}/g).join('-');
    if (code !== expectedCode || pairing.display_code !== expectedCode) throw new Error('RD_PAIRING_CODE_MISMATCH');
    const confirmed = await api.request(`/api/v1/rd/pairings/${pairing.id}/confirm`, { method: 'POST', body: { signed_proof: await signJws(api.identity, proof, 'ht-rd-pairing+jwt') } });
    if (confirmed.state !== 'confirmed' || !confirmed.grant_id) throw new Error('RD_PAIRING_REQUIRED');
    await api.identity.rememberHost(host.id, host.jkt);
    const snapshot = await api.request('/api/v1/rd/sessions', { method: 'POST', idempotencyKey: requestID, body: { host_endpoint_id: host.id, grant_id: confirmed.grant_id, permissions: ['view'], display_id: host.capabilities.displays[0].id, protocol: { major: 1, minor: 0 }, quality: 'balanced' } });
    return { session_id: snapshot.session_id };
  },
  async start(id) {
    const snapshot = await api.request(`/api/v1/rd/sessions/${id}`);
    if (!snapshot.ticket_jws) throw new Error('RD_LOCAL_APPROVAL_REQUIRED');
    session = new RemoteSession({ api, signal, session: snapshot, hostThumbprint: host.jkt, video,
      onState(phase, error) { state.phases.push(phase); if (error) state.failures.push(error.code ?? 'RD_MEDIA_FAILED'); },
      onReconnectNeeded() { fail(new Error('RD_UNEXPECTED_RECONNECT')); },
    });
    // Local host candidates suffice for this same-machine direct UDP acceptance.
    await session.start([]);
    for (const message of pending) await deliver(message);
    pending = [];
  },
  async evidence() {
    const stats = session?.pc ? await session.pc.getStats() : new Map();
    const pair = selectedUdpPair(stats);
    const values = [...stats.values()];
    const transport = values.find(item => item.type === 'transport' && item.selectedCandidatePairId);
    const inbound = values.find(item => item.type === 'inbound-rtp' && item.kind === 'video');
    const candidates = pair ? stats.get(pair.id) : null;
    const local = candidates ? stats.get(candidates.localCandidateId) : null;
    const remote = candidates ? stats.get(candidates.remoteCandidateId) : null;
    return { ...state, ready: session?.ready === true, closed: session?.closed !== false, peer_verified: session?.peerVerified === true,
      host_path_verified: session?.pathVerified === true, browser_udp_verified: pair?.verified === true,
      input_enabled: session?.inputEnabled === true, connection_state: session?.pc?.connectionState,
      dtls_state: transport?.dtlsState, frames_decoded: inbound?.framesDecoded ?? 0, bytes_received: inbound?.bytesReceived ?? 0,
      local_candidate: local ? { protocol: local.protocol, type: local.candidateType } : null,
      remote_candidate: remote ? { protocol: remote.protocol, type: remote.candidateType } : null };
  },
  async close() { session?.close(); await session?.closeRequest; signal?.close(); api?.close(); },
};
