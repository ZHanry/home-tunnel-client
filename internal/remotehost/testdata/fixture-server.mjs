// Isolated real control-center fixture. Never points at a deployed service.
import { createServer } from 'node:http';
import { once } from 'node:events';
import { generateKeyPairSync, randomBytes, randomUUID, sign } from 'node:crypto';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { createInterface } from 'node:readline';

const root = resolve(process.env.HT_SERVER_ROOT);
const directory = mkdtempSync(join(tmpdir(), 'ht-go-rd-'));
let app;
const server = createServer((request, response) => app(request, response));
server.listen(0, '127.0.0.1');
await once(server, 'listening');
const origin = `http://127.0.0.1:${server.address().port}`;
const serverKey = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const keyPath = join(directory, 'key.pem');
writeFileSync(keyPath, serverKey.privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
Object.assign(process.env, {
  NODE_ENV: 'test', SQLITE_PATH: ':memory:', COOKIE_SECURE: 'false',
  INTERNAL_SERVICE_KEY: randomBytes(32).toString('hex'), FRPS_PLUGIN_KEY: randomBytes(32).toString('hex'),
  LEASE_SIGNING_KEY: randomBytes(32).toString('hex'), RD_ENABLED: 'true',
  RD_SIGNING_KEY_FILE: keyPath, PUBLIC_BASE_URL: origin,
});
delete process.env.RD_KEYSET_FILE;
const load = name => import(pathToFileURL(join(root, 'control-center/dist', name)).href);
const [{ createApplication }, db, rd, crypto, { issueSession }, { attachRdSignaling }] = await Promise.all([
  load('server.js'), load('db.js'), load('rd/service.js'), load('rd/crypto.js'), load('http.js'), load('rd/signaling.js'),
]);
const require = createRequire(join(root, 'control-center/package.json'));
const { WebSocket } = require('ws');
await db.migrate();
await rd.initializeRd();
app = await createApplication(false);
const signal = attachRdSignaling(server);
const userID = randomUUID(), deviceID = randomUUID();
const account = await db.transaction(async client => {
  await client.query("INSERT INTO users(id,username,display_name,password_hash,password_state,role) VALUES(?,?,?,'fixture','normal','user')", [userID, 'go-rd-fixture', 'Go RD fixture']);
  const session = await issueSession(client, { id: userID, token_version: 1 }, null);
  await client.query('UPDATE sessions SET rd_verified_at=home_tunnel_now() WHERE id=?', [session.sessionId]);
  await client.query('INSERT INTO devices(id,user_id,name,install_id,fingerprint_hash,credential_hash) VALUES(?,?,?,?,?,?)', [deviceID, userID, 'Go host', randomUUID(), randomUUID(), randomUUID()]);
  return session;
});
const keys = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const publicJWK = crypto.publicJwk(keys.publicKey.export({ format: 'jwk' }));
let signingKey = keys, signingJWK = publicJWK, activeAccount = account;
const signature = (payload, typ, includeJWK = false) => {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', typ, ...(includeJWK ? { jwk: signingJWK } : {}) })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.${sign('sha256', Buffer.from(`${header}.${body}`), { key: signingKey.privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
};
let controller;
async function request(path, method = 'GET', body, mode = 'dpop', extra = {}) {
  const headers = { ...extra, 'content-type': 'application/json' };
  if (mode === 'account') headers.authorization = `Bearer ${activeAccount.accessToken}`;
  else if (mode === 'dpop') {
    headers.authorization = `DPoP ${controller.token}`;
    headers.dpop = signature({ htu: `${origin}/api/v1/rd${path}`, htm: method, iat: Math.floor(Date.now()/1000), jti: randomUUID(), ath: crypto.digest(controller.token), nonce: controller.dpop_nonce }, 'dpop+jwt', true);
  }
  const response = await fetch(`${origin}/api/v1/rd${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const result = response.status === 204 ? {} : await response.json();
  if (!response.ok) throw new Error(`${method} ${path} ${response.status} ${result.error_code}`);
  return result;
}
const challenge = await request('/enrollment-challenges', 'POST', { endpoint_kind: 'browser', role: 'controller', public_jwk: publicJWK }, 'account');
controller = await request('/endpoints', 'POST', { challenge_id: challenge.challenge_id, signed_proof: signature(challenge.proof_payload, 'ht-rd-proof+jwt'), name: 'Go integration controller', platform: 'browser' }, 'account');
const primaryController = controller;
const guestID = randomUUID();
const guestAccount = await db.transaction(async client => {
  await client.query("INSERT INTO users(id,username,display_name,password_hash,password_state,role) VALUES(?,?,?,'fixture','normal','user')", [guestID, 'go-rd-guest', 'Go RD guest']);
  const session = await issueSession(client, { id: guestID, token_version: 1 }, null);
  await client.query('UPDATE sessions SET rd_verified_at=home_tunnel_now() WHERE id=?', [session.sessionId]);
  return session;
});
const guestKeys = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const guestJWK = crypto.publicJwk(guestKeys.publicKey.export({ format: 'jwk' }));
activeAccount = guestAccount; signingKey = guestKeys; signingJWK = guestJWK;
const guestChallenge = await request('/enrollment-challenges', 'POST', { endpoint_kind: 'browser', role: 'controller', public_jwk: guestJWK }, 'account');
const guestController = await request('/endpoints', 'POST', { challenge_id: guestChallenge.challenge_id, signed_proof: signature(guestChallenge.proof_payload, 'ht-rd-proof+jwt'), name: 'Go cross-account guest', platform: 'browser' }, 'account');
activeAccount = account; signingKey = keys; signingJWK = publicJWK; controller = primaryController;
const socket = new WebSocket(`${origin.replace('http:', 'ws:')}/api/v1/rd/signal`, 'ht.rd.signal.v1');
const messages = [];
socket.on('message', raw => messages.push(JSON.parse(raw.toString())));
async function waitMessage(type) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const error = messages.find(m => m.type === 'error');
    if (error) throw new Error(`WSS ${error.error_code}`);
    const index = messages.findIndex(m => m.type === type);
    if (index >= 0) return messages.splice(index, 1)[0];
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw new Error(`Timed out waiting for ${type}`);
}
const authChallenge = await waitMessage('auth.challenge');
const ticket = await request('/signal-tickets', 'POST', { purpose: 'connect' });
socket.send(JSON.stringify({ v: 1, type: 'auth', ticket: ticket.ticket, proof: signature({ connection_id: authChallenge.connection_id, nonce: authChallenge.nonce, ticket_hash: crypto.digest(ticket.ticket), endpoint_id: controller.endpoint.id }, 'ht-rd-signal+jwt') }));
await waitMessage('auth.ok');
const emit = result => process.stdout.write(`HT_FIXTURE ${JSON.stringify(result)}\n`);
emit({ origin, account_token: account.accessToken, device_id: deviceID, controller_id: controller.endpoint.id });
let pairing, requestID, hostID, session;
async function command(input) {
  switch (input.action) {
    case 'pair': {
      hostID = input.host_id; requestID = randomUUID();
      pairing = await request('/pairings', 'POST', { host_endpoint_id: hostID, session_request_id: requestID, permissions: ['view', 'input.pointer'], mode: 'one_session', nonce_controller: randomBytes(32).toString('base64url') });
      return { id: pairing.id, request_id: requestID };
    }
    case 'assist': {
      activeAccount = guestAccount; signingKey = guestKeys; signingJWK = guestJWK; controller = guestController;
      const target = await request('/assist-invites/redeem', 'POST', { device_id: input.device_id, temporary_password: input.temporary_password });
      hostID = target.host_endpoint_id; requestID = randomUUID();
      pairing = await request('/pairings', 'POST', { host_endpoint_id: hostID, assist_invite_id: target.invite_id, session_request_id: requestID, permissions: ['view', 'input.pointer'], mode: 'one_session', nonce_controller: randomBytes(32).toString('base64url') });
      return { id: pairing.id, request_id: requestID, host_id: hostID, invite_id: target.invite_id };
    }
    case 'confirm': {
      pairing = await request(`/pairings/${pairing.id}`);
      await request(`/pairings/${pairing.id}/confirm`, 'POST', { signed_proof: signature(pairing.transcript, 'ht-rd-pairing+jwt') });
      return { display_code: pairing.display_code };
    }
    case 'create':
      session = await request('/sessions', 'POST', { host_endpoint_id: hostID, grant_id: pairing.id, permissions: ['view', 'input.pointer'], display_id: 'display-1', protocol: { major: 1, minor: 0 } }, 'dpop', { 'idempotency-key': requestID });
      return session;
    case 'offer': {
      session = await request(`/sessions/${session.id}`);
      const authority = JSON.parse(Buffer.from(session.ticket_jws.split('.')[1], 'base64url'));
      const compact = signature({ v: 1, type: 'peer.offer', session_id: session.id, connection_epoch: session.connection_epoch, from_endpoint_id: controller.endpoint.id, to_endpoint_id: hostID, seq: '1', ticket_jti: authority.jti, created_at: new Date().toISOString(), payload: { type: 'offer', sdp: 'v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n' } }, 'ht-rd-peer+jwt');
      socket.send(JSON.stringify({ v: 1, type: 'peer.offer', request_id: randomUUID(), session_id: session.id, connection_epoch: session.connection_epoch, payload_jws: compact }));
      return { compact };
    }
    case 'answer': {
      const answer = await waitMessage('peer.answer');
      crypto.verifyJws(answer.payload_jws, session.host_public_jwk, 'ht-rd-peer+jwt');
      return { compact: answer.payload_jws };
    }
    case 'ready': {
      session = await request(`/sessions/${session.id}`);
      return request(`/sessions/${session.id}/report`, 'POST', { phase: 'ready', connection_epoch: session.connection_epoch, expected_version: session.state_version });
    }
    case 'state': {
      const current = await request(`/sessions/${session.id}`);
      const slots = await db.query('SELECT * FROM rd_session_slots WHERE session_id=?', [session.id]);
      return { ...current, slots: slots.length };
    }
    case 'age_lease':
      await db.query('UPDATE rd_sessions SET lease_issued_at=? WHERE id=?', [new Date(Date.now()-241000).toISOString(), session.id]);
      return {};
    case 'reconnect':
      session = await request(`/sessions/${session.id}/reconnect`, 'POST', { expected_epoch: session.connection_epoch, reason: 'network_changed' }, 'dpop', { 'idempotency-key': randomUUID() });
      return session;
    default: throw new Error('Unknown fixture action');
  }
}
const input = createInterface({ input: process.stdin });
for await (const line of input) {
  try { emit({ result: await command(JSON.parse(line)) }); }
  catch (error) { emit({ error: String(error.message) }); }
}
socket.terminate();
await signal.close();
server.closeAllConnections();
await new Promise(resolve => server.close(resolve));
await db.closeDatabase();
rmSync(directory, { recursive: true, force: true });
