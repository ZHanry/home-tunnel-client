#!/usr/bin/env node
// Real Windows worker -> production host/control-center -> production Chromium controller.
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const options = Object.create(null);
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i];
  if (!['--worker', '--sha256', '--server-root', '--report-dir'].includes(key) || !process.argv[i + 1] || options[key]) {
    console.error('Usage: node scripts/test-remote-native.mjs --worker <absolute.exe> --sha256 <expected hash> --server-root <built server checkout> [--report-dir <directory>]');
    process.exit(2);
  }
  options[key] = process.argv[i + 1];
}
const reportDir = resolve(options['--report-dir'] ?? join(root, 'outputs', 'remote-native-acceptance'));
mkdirSync(reportDir, { recursive: true });
const report = {
  schema: 1, started_at: new Date().toISOString(), status: 'not_verified',
  scope: 'Windows native desktop capture to Chromium on the same machine, view only',
  transport: 'isolated HTTP/WS IPv4 loopback fixture; production HTTPS policy unchanged',
  checks: {}, limitations: ['Cross-network traversal, Android, audio, clipboard, files and input are not established by this run.'],
  input: { status: 'not_verified', reason: 'No native target-window confinement contract; no input injection is attempted.' },
  privacy: { screenshots: false, recordings: false, sdp: false, network_addresses: false, credentials: false },
};
let directory, fixture, host, browser, page, rpcID = 0, stage = 'preflight';
const children = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
class CheckFailure extends Error { constructor(code) { super(code); this.code = code; } }
function requireCheck(value, code) { if (!value) throw new CheckFailure(code); }
function verifiedMedia(evidence) {
  return evidence.ready && !evidence.closed && evidence.peer_verified && evidence.host_path_verified && evidence.browser_udp_verified && evidence.connection_state === 'connected' && evidence.dtls_state === 'connected' && evidence.frames >= 5 && evidence.frames_decoded >= 5 && evidence.bytes_received > 0 && evidence.width > 0 && evidence.height > 0 && !evidence.input_enabled && !evidence.failures.length;
}

class PipeProcess {
  constructor(executable, args, env = process.env) {
    this.messages = []; this.waiters = new Set(); this.closed = false; this.failure = null;
    this.child = spawn(executable, args, { cwd: root, env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    children.push(this);
    this.exit = new Promise(resolve => {
      this.child.once('error', () => { this.failure = new CheckFailure('E2E_CHILD_START_FAILED'); this.closed = true; this.notify(); resolve(); });
      this.child.once('exit', () => { this.closed = true; this.notify(); resolve(); });
    });
    // Arbitrary backend/native logs can contain sensitive content; do not retain them.
    this.child.stderr.resume();
    this.child.stdin.on('error', () => {});
    const lines = createInterface({ input: this.child.stdout });
    lines.on('line', line => {
      if (!line.startsWith('HT_NATIVE ')) return;
      if (line.length > 262144 || this.messages.length >= 128) {
        this.failure = new CheckFailure('E2E_PIPE_LIMIT_EXCEEDED'); this.notify(); return;
      }
      try {
        const value = JSON.parse(line.slice(10));
        if (value.event === 'fatal' || value.event === 'unavailable') this.failure = new CheckFailure(value.code === 'RD_BACKEND_UNAVAILABLE' ? value.code : 'E2E_HOST_FAILED');
        else this.messages.push(value);
      } catch { this.failure = new CheckFailure('E2E_INVALID_PIPE_MESSAGE'); }
      this.notify();
    });
  }
  notify() { for (const callback of this.waiters) callback(); }
  send(value) { this.child.stdin.write(`${JSON.stringify(value)}\n`); }
  read(predicate, timeout = 20000) {
    return new Promise((resolve, reject) => {
      const complete = (error, value) => { clearTimeout(timer); this.waiters.delete(check); error ? reject(error) : resolve(value); };
      const check = () => {
        if (this.failure) { complete(this.failure); return; }
        const index = this.messages.findIndex(predicate);
        if (index >= 0) { complete(null, this.messages.splice(index, 1)[0]); return; }
        if (this.closed) complete(new CheckFailure('E2E_CHILD_EXITED'));
      };
      const timer = setTimeout(() => complete(new CheckFailure('E2E_PIPE_TIMEOUT')), timeout);
      this.waiters.add(check); check();
    });
  }
  async stop() {
    if (this.closed) return;
    this.child.stdin.end();
    await Promise.race([this.exit, delay(5000)]);
    if (!this.closed) { this.child.kill(); await Promise.race([this.exit, delay(2000)]); }
  }
}
async function rpc(action, payload = {}) {
  const id = ++rpcID;
  host.send({ id, action, ...payload });
  const response = await host.read(item => item.id === id);
  requireCheck(response.ok, 'E2E_HOST_ACTION_FAILED');
  return response;
}
async function until(check, code, timeout = 15000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (host?.failure) throw host.failure;
    if (await check()) return;
    await delay(200);
  }
  throw new CheckFailure(code);
}
function revision(path) {
  const result = spawnSync('git', ['-C', path, 'rev-parse', 'HEAD'], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
  const commit = result.status === 0 ? result.stdout.trim() : null;
  const changed = spawnSync('git', ['-C', path, 'status', '--porcelain'], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
  return { commit, modified: changed.status === 0 ? changed.stdout.length > 0 : null };
}
try {
  requireCheck(process.platform === 'win32', 'E2E_WINDOWS_REQUIRED');
  requireCheck(Number(process.versions.node.split('.')[0]) === 24, 'E2E_NODE_24_REQUIRED');
  requireCheck(options['--worker'] && isAbsolute(options['--worker']) && existsSync(options['--worker']), 'E2E_NATIVE_WORKER_MISSING');
  requireCheck(/^[0-9a-f]{64}$/i.test(options['--sha256'] ?? ''), 'E2E_PINNED_SHA256_REQUIRED');
  const actualHash = createHash('sha256').update(readFileSync(options['--worker'])).digest('hex');
  requireCheck(actualHash === options['--sha256'].toLowerCase(), 'E2E_NATIVE_HASH_MISMATCH');
  report.worker_sha256 = actualHash;
  const serverRoot = resolve(options['--server-root'] ?? process.env.HT_SERVER_ROOT ?? join(root, '..', 'home-tunnel-server'));
  requireCheck(existsSync(join(serverRoot, 'control-center', 'dist', 'server.js')), 'E2E_BUILT_SERVER_REQUIRED');
  report.sources = { client: revision(root), server: revision(serverRoot) };
  directory = mkdtempSync(join(tmpdir(), 'home-tunnel-native-e2e-'));
  stage = 'build_host';
  const hostExecutable = join(directory, 'native-e2e-host.exe');
  const build = spawnSync('go', ['build', '-tags', 'remote_native_e2e', '-o', hostExecutable, './tests/remote-native/host'], { cwd: root, windowsHide: true, timeout: 120000, encoding: 'utf8', maxBuffer: 1048576 });
  requireCheck(build.status === 0, 'E2E_NATIVE_HOST_BUILD_FAILED');
  stage = 'fixture';
  fixture = new PipeProcess(process.execPath, [join(root, 'tests', 'remote-native', 'fixture.mjs')], { ...process.env, HT_SERVER_ROOT: serverRoot, HT_NATIVE_E2E_TEMP: directory });
  const initial = await fixture.read(item => item.event === 'fixture', 30000);
  requireCheck(/^http:\/\/127\.0\.0\.1:\d+$/.test(initial.origin), 'E2E_NON_LOOPBACK_FIXTURE');
  report.checks.isolated_real_server = true;
  stage = 'native_backend';
  host = new PipeProcess(hostExecutable, []);
  host.send({ ...initial, worker: options['--worker'], sha256: actualHash, store_path: join(directory, 'host-state.json') });
  const ready = await host.read(item => item.event === 'host', 30000);
  requireCheck(ready.capabilities?.available && ready.capabilities.status === 'ready' && ready.capabilities.displays?.length, 'RD_BACKEND_UNAVAILABLE');
  report.checks.native_backend_ready = true;
  report.capabilities = { permissions: ready.capabilities.permissions, codecs: ready.capabilities.codecs, display_count: ready.capabilities.displays.length };
  stage = 'browser';
  const { chromium } = await import('@playwright/test');
  browser = await chromium.launch({ headless: false, args: ['--autoplay-policy=no-user-gesture-required'] });
  report.browser_version = browser.version();
  const context = await browser.newContext({ viewport: { width: 1000, height: 720 } });
  const target = await context.newPage();
  await target.goto(`${initial.origin}/__native-e2e/target.html`);
  report.input.target_created = true;
  page = await context.newPage();
  await page.goto(`${initial.origin}/__native-e2e/controller.html`);
  await page.waitForFunction(() => !!window.nativeE2E);
  const controller = await page.evaluate(value => window.nativeE2E.initialize(value), { account_token: initial.account_token, user_id: initial.user_id });
  // Tokens remain exclusively in process memory and in the isolated browser context.
  delete initial.account_token;
  await rpc('bind_controller', controller);
  await until(() => page.evaluate(id => window.nativeE2E.findHost(id), ready.endpoint_id), 'E2E_HOST_NOT_ONLINE');
  report.checks.real_browser_identity = true;
  stage = 'pairing';
  const pairing = await page.evaluate(() => window.nativeE2E.pair());
  await host.read(item => item.event === 'approval' && item.approval.kind === 'pairing' && item.approval.id === pairing.id);
  await rpc('approve_pairing', { target_id: pairing.id });
  const display = await host.read(item => item.event === 'approval' && item.approval.kind === 'pairing_display' && item.approval.id === pairing.id);
  const created = await page.evaluate(code => window.nativeE2E.confirm(code), display.approval.display_code);
  report.checks.signed_pairing_and_code_match = true;
  stage = 'session';
  await host.read(item => item.event === 'approval' && item.approval.kind === 'session' && item.approval.id === created.session_id);
  await rpc('approve_session', { target_id: created.session_id });
  await page.evaluate(id => window.nativeE2E.start(id), created.session_id);
  report.checks.explicit_session_approval = true;
  stage = 'media';
  await until(async () => {
    const evidence = await page.evaluate(() => window.nativeE2E.evidence());
    report.media = evidence;
    requireCheck(!evidence.failures.length, 'E2E_BROWSER_PROTOCOL_FAILED');
    return verifiedMedia(evidence);
  }, 'E2E_REAL_MEDIA_NOT_OBSERVED', 30000);
  const first = report.media.frames_decoded;
  await delay(1200);
  report.media = await page.evaluate(() => window.nativeE2E.evidence());
  requireCheck(verifiedMedia(report.media) && report.media.frames_decoded > first, 'E2E_MEDIA_NOT_CONTINUING');
  report.checks.real_continuing_video = true;
  report.checks.selected_udp_and_dtls = true;
  stage = 'shutdown';
  await page.evaluate(() => window.nativeE2E.close());
  await rpc('shutdown');
  report.checks.clean_session_shutdown = true;
  report.status = 'verified';
} catch (error) {
  report.status = report.checks.native_backend_ready ? 'failed' : 'not_verified';
  report.failure = { stage, code: error instanceof CheckFailure ? error.code : 'E2E_UNEXPECTED_FAILURE' };
  process.exitCode = 1;
} finally {
  if (page && !page.isClosed()) await page.evaluate(() => window.nativeE2E?.close()).catch(() => {});
  await browser?.close().catch(() => {});
  for (const child of children.reverse()) await child.stop();
  // directory is always our own mkdtemp result, never user input.
  if (directory) {
    try { rmSync(directory, { recursive: true, force: true, maxRetries: 3, retryDelay: 200 }); }
    catch { report.cleanup = 'failed'; report.status = 'failed'; process.exitCode = 1; }
  }
  report.finished_at = new Date().toISOString();
  const destination = join(reportDir, 'report.json');
  writeFileSync(destination, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  console.log(JSON.stringify({ status: report.status, failure: report.failure, report: destination }));
}
