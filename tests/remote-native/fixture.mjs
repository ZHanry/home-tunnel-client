// An isolated instance of the production control center, never a protocol mock.
import { createServer } from 'node:http';
import { createServer as createSecureServer } from 'node:https';
import { once } from 'node:events';
import { generateKeyPairSync, randomBytes, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(process.env.HT_SERVER_ROOT);
const directory = resolve(process.env.HT_NATIVE_E2E_TEMP);
const here = fileURLToPath(new URL('.', import.meta.url));
const files = new Map([
  ['/__native-e2e/controller.html', ['controller.html', 'text/html']],
  ['/__native-e2e/controller.mjs', ['controller.mjs', 'text/javascript']],
  ['/__native-e2e/target.html', ['target.html', 'text/html']],
]);
let app;
const serve = (request, response) => {
  const file = files.get(request.url);
  if (file) {
    response.writeHead(200, { 'content-type': `${file[1]}; charset=utf-8`, 'cache-control': 'no-store' });
    response.end(readFileSync(join(here, file[0])));
  } else if (app) app(request, response);
  else { response.writeHead(503); response.end(); }
};
const secure = process.env.HT_NATIVE_E2E_HTTPS === '1';
const server = secure
  ? createSecureServer({ key: readFileSync(process.env.HT_NATIVE_E2E_TLS_KEY), cert: readFileSync(process.env.HT_NATIVE_E2E_TLS_CERT) }, serve)
  : createServer(serve);
server.listen(0, '127.0.0.1');
await once(server, 'listening');
const origin = `${secure ? 'https' : 'http'}://127.0.0.1:${server.address().port}`;
const key = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const keyPath = join(directory, 'fixture-signing.pem');
writeFileSync(keyPath, key.privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
Object.assign(process.env, {
  NODE_ENV: 'test', SQLITE_PATH: ':memory:', COOKIE_SECURE: 'false',
  INTERNAL_SERVICE_KEY: randomBytes(32).toString('hex'), FRPS_PLUGIN_KEY: randomBytes(32).toString('hex'),
  LEASE_SIGNING_KEY: randomBytes(32).toString('hex'), RD_ENABLED: 'true',
  RD_SIGNING_KEY_FILE: keyPath, PUBLIC_BASE_URL: origin,
});
delete process.env.RD_KEYSET_FILE;
const load = name => import(pathToFileURL(join(root, 'control-center/dist', name)).href);
const [{ createApplication }, db, rd, { issueSession }, { attachRdSignaling }] = await Promise.all([
  load('server.js'), load('db.js'), load('rd/service.js'), load('http.js'), load('rd/signaling.js'),
]);
const { hashPassword } = await load('security.js');
await db.migrate();
await rd.initializeRd();
app = await createApplication(false);
const signaling = attachRdSignaling(server);
const userID = randomUUID(), deviceID = randomUUID(), assistUserID = randomUUID();
const password = secure ? randomBytes(24).toString('base64url') : null;
const passwordHash = password ? await hashPassword(password) : 'unusable-e2e-password';
const assistPassword = secure ? randomBytes(24).toString('base64url') : null;
const assistPasswordHash = assistPassword ? await hashPassword(assistPassword) : 'unusable-e2e-password';
const account = await db.transaction(async client => {
  await client.query("INSERT INTO users(id,username,display_name,password_hash,password_state,role) VALUES(?,?,?,?,'normal','user')", [userID, `native-e2e-${userID}`, 'Native media acceptance', passwordHash]);
  const session = await issueSession(client, { id: userID, token_version: 1 }, null);
  await client.query('UPDATE sessions SET rd_verified_at=home_tunnel_now() WHERE id=?', [session.sessionId]);
  await client.query('INSERT INTO devices(id,user_id,name,install_id,fingerprint_hash,credential_hash) VALUES(?,?,?,?,?,?)', [deviceID, userID, 'Native acceptance host', randomUUID(), randomUUID(), randomUUID()]);
  return session;
});
const assistAccount = await db.transaction(async client => {
  await client.query("INSERT INTO users(id,username,display_name,password_hash,password_state,role) VALUES(?,?,?,?,'normal','user')", [assistUserID, `native-assist-${assistUserID}`, 'Native cross-account controller', assistPasswordHash]);
  const session = await issueSession(client, { id: assistUserID, token_version: 1 }, null);
  await client.query('UPDATE sessions SET rd_verified_at=home_tunnel_now() WHERE id=?', [session.sessionId]);
  return session;
});
const keys = await rd.keySet();
// This private pipe is consumed by the runner; credentials must never enter the report.
process.stdout.write(`HT_NATIVE ${JSON.stringify({ event: 'fixture', origin, account_token: account.accessToken, password, user_id: userID, device_id: deviceID, assist_account_token: assistAccount.accessToken, assist_username: `native-assist-${assistUserID}`, assist_password: assistPassword, assist_user_id: assistUserID, server_instance_id: keys.server_instance_id, active_kid: keys.active_kid })}\n`);
process.stdin.resume();
await once(process.stdin, 'end');
await signaling.close();
server.closeAllConnections();
await new Promise(resolve => server.close(resolve));
await db.closeDatabase();
