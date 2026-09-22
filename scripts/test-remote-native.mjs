#!/usr/bin/env node
// Real Windows worker -> production host/control-center -> production Chromium controller.
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const options = Object.create(null);
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i];
  if (!['--worker', '--sha256', '--server-root', '--report-dir', '--input', '--codec', '--files'].includes(key) || !process.argv[i + 1] || options[key]) {
    console.error('Usage: node scripts/test-remote-native.mjs --worker <absolute.exe> --sha256 <expected hash> --server-root <built server checkout> [--report-dir <directory>] [--input chromium] [--codec H264|VP8] [--files fixture]');
    process.exit(2);
  }
  options[key] = process.argv[i + 1];
}
const reportDir = resolve(options['--report-dir'] ?? join(root, 'outputs', 'remote-native-acceptance'));
const withInput = options['--input'] === 'chromium';
const withFiles = options['--files'] === 'fixture';
const requestedCodec = options['--codec'] ?? null;
if (requestedCodec !== null && !['H264', 'VP8'].includes(requestedCodec)) { console.error('Unsupported codec constraint'); process.exit(2); }
mkdirSync(reportDir, { recursive: true });
const report = {
  schema: 1, started_at: new Date().toISOString(), status: 'not_verified',
  scope: `Windows native desktop capture to Chromium on the same machine, ${withInput ? 'view and input confined to a dedicated test browser process' : 'view without input'}${withFiles ? ', with bidirectional fixture file transfer' : ''}`,
  transport: 'isolated HTTP/WS IPv4 loopback fixture; production HTTPS policy unchanged',
  checks: {}, limitations: ['Cross-network traversal, Android, audio, clipboard, files and input are not established by this run.'],
  input: { status: 'not_verified', reason: withInput ? 'Input acceptance has not completed.' : 'Input acceptance was not requested; no input injection is attempted.' },
  privacy: { screenshots: false, recordings: false, sdp: false, network_addresses: false, credentials: false },
  requested_codec: requestedCodec,
};
let directory, fixture, host, browser, page, target, targetBrowser, targetServer, rpcID = 0, stage = 'preflight';
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
function treeHash(directory) {
  const entries = [];
  const visit = (path, prefix = '') => {
    for (const entry of readdirSync(path, { withFileTypes: true })) {
      const relative = `${prefix}${entry.name}`;
      requireCheck(!entry.isSymbolicLink(), 'E2E_BUILD_SYMLINK_REJECTED');
      if (entry.isDirectory()) visit(join(path, entry.name), `${relative}/`);
      else if (entry.isFile()) entries.push({ path: relative, sha256: createHash('sha256').update(readFileSync(join(path, entry.name))).digest('hex') });
    }
  };
  visit(directory); entries.sort((a, b) => a.path.localeCompare(b.path, 'en'));
  return { file_count: entries.length, sha256: createHash('sha256').update(JSON.stringify(entries)).digest('hex') };
}
try {
  requireCheck(process.platform === 'win32', 'E2E_WINDOWS_REQUIRED');
  requireCheck(Number(process.versions.node.split('.')[0]) === 24, 'E2E_NODE_24_REQUIRED');
  requireCheck(options['--input'] === undefined || withInput, 'E2E_INPUT_TARGET_INVALID');
  requireCheck(options['--files'] === undefined || withFiles, 'E2E_FILE_FIXTURE_INVALID');
  requireCheck(options['--worker'] && isAbsolute(options['--worker']) && existsSync(options['--worker']), 'E2E_NATIVE_WORKER_MISSING');
  requireCheck(/^[0-9a-f]{64}$/i.test(options['--sha256'] ?? ''), 'E2E_PINNED_SHA256_REQUIRED');
  const actualHash = createHash('sha256').update(readFileSync(options['--worker'])).digest('hex');
  requireCheck(actualHash === options['--sha256'].toLowerCase(), 'E2E_NATIVE_HASH_MISMATCH');
  report.worker_sha256 = actualHash;
  const serverRoot = resolve(options['--server-root'] ?? process.env.HT_SERVER_ROOT ?? join(root, '..', 'home-tunnel-server'));
  requireCheck(existsSync(join(serverRoot, 'control-center', 'package.json')), 'E2E_SERVER_SOURCE_REQUIRED');
  report.sources = { client: revision(root), server: revision(serverRoot) };
  const serverLock = JSON.parse(readFileSync(join(root, 'tests', 'remote-native', 'server-lock.json'), 'utf8'));
  requireCheck(report.sources.server.commit === serverLock.revision && report.sources.server.modified === false, 'E2E_LOCKED_CLEAN_SERVER_REQUIRED');
  stage = 'build_server';
  const controlCenter = resolve(serverRoot, 'control-center');
  const dist = resolve(controlCenter, 'dist');
  requireCheck(dirname(dist) === controlCenter && (!existsSync(dist) || !lstatSync(dist).isSymbolicLink()), 'E2E_SERVER_BUILD_PATH_INVALID');
  // This exact generated directory is removed before compilation, so ignored
  // stale files cannot be mistaken for products of the recorded source commit.
  rmSync(dist, { recursive: true, force: true });
  const serverBuild = spawnSync('cmd.exe', ['/d', '/s', '/c', 'pnpm.cmd run build'], { cwd: controlCenter, windowsHide: true, timeout: 120000, encoding: 'utf8', maxBuffer: 1048576, env: { ...process.env, PATH: `${dirname(process.execPath)}${delimiter}${process.env.PATH ?? ''}` } });
  requireCheck(serverBuild.status === 0 && existsSync(join(dist, 'server.js')), 'E2E_SERVER_FRESH_BUILD_FAILED');
  const afterBuild = revision(serverRoot);
  requireCheck(afterBuild.commit === serverLock.revision && afterBuild.modified === false, 'E2E_SERVER_SOURCE_CHANGED_DURING_BUILD');
  report.server_build = { fresh: true, source_commit: afterBuild.commit, command: 'pnpm run build', dist: treeHash(dist) };
  directory = mkdtempSync(join(tmpdir(), 'home-tunnel-native-e2e-'));
  const fileRoot = withFiles ? join(directory, 'file-fixture') : '';
  const nativeFileBytes = Buffer.from(Uint8Array.from({ length: 1048607 }, (_, n) => (n * 13 + 29) & 255));
  if (withFiles) {
    mkdirSync(fileRoot); writeFileSync(join(fileRoot, 'native-empty.bin'), '');
    writeFileSync(join(fileRoot, 'native-multichunk.bin'), nativeFileBytes);
  }
  stage = 'build_host';
  const hostExecutable = join(directory, 'native-e2e-host.exe');
  const build = spawnSync('go', ['build', '-tags', 'remote_native_e2e', '-o', hostExecutable, './tests/remote-native/host'], { cwd: root, windowsHide: true, timeout: 120000, encoding: 'utf8', maxBuffer: 1048576 });
  requireCheck(build.status === 0, 'E2E_NATIVE_HOST_BUILD_FAILED');
  stage = 'fixture';
  fixture = new PipeProcess(process.execPath, [join(root, 'tests', 'remote-native', 'fixture.mjs')], { ...process.env, HT_SERVER_ROOT: serverRoot, HT_NATIVE_E2E_TEMP: directory });
  const initial = await fixture.read(item => item.event === 'fixture', 30000);
  requireCheck(/^http:\/\/127\.0\.0\.1:\d+$/.test(initial.origin), 'E2E_NON_LOOPBACK_FIXTURE');
  report.checks.isolated_real_server = true;
  const { chromium } = await import('@playwright/test');
  let inputTargetPID = 0;
  if (withInput) {
    stage = 'input_target';
    // This process contains only our isolated test page. Its PID is enforced by
    // the native worker before every OS input injection, including text.
    targetServer = await chromium.launchServer({ headless: false, args: ['--window-position=40,40', '--window-size=900,700'] });
    inputTargetPID = targetServer.process().pid;
    requireCheck(Number.isInteger(inputTargetPID) && inputTargetPID > 0, 'E2E_INPUT_TARGET_PID_REQUIRED');
    targetBrowser = await chromium.connect(targetServer.wsEndpoint());
    const targetContext = await targetBrowser.newContext({ viewport: null });
    target = await targetContext.newPage();
    await target.goto(`${initial.origin}/__native-e2e/target.html`);
    report.input.target_created = true;
    report.input.native_process_confinement = true;
  }
  stage = 'native_backend';
  host = new PipeProcess(hostExecutable, []);
  host.send({ ...initial, worker: options['--worker'], sha256: actualHash, store_path: join(directory, 'host-state.json'), input_target_pid: inputTargetPID, file_test_root: fileRoot });
  const ready = await host.read(item => item.event === 'host', 30000);
  requireCheck(ready.capabilities?.available && ready.capabilities.status === 'ready' && ready.capabilities.displays?.length, 'RD_BACKEND_UNAVAILABLE');
  report.checks.native_backend_ready = true;
  report.capabilities = { permissions: ready.capabilities.permissions, codecs: ready.capabilities.codecs, display_count: ready.capabilities.displays.length };
  stage = 'browser';
  browser = await chromium.launch({ headless: false, args: ['--autoplay-policy=no-user-gesture-required'] });
  report.browser_version = browser.version();
  const context = await browser.newContext({ viewport: { width: 1000, height: 720 } });
  if (!target) {
    target = await context.newPage();
    await target.goto(`${initial.origin}/__native-e2e/target.html`);
    report.input.target_created = true;
  }
  page = await context.newPage();
  await page.goto(`${initial.origin}/__native-e2e/controller.html`);
  await page.waitForFunction(() => !!window.nativeE2E);
  const controller = await page.evaluate(value => window.nativeE2E.initialize(value), { account_token: initial.account_token, user_id: initial.user_id, input: withInput, files: withFiles, codec: requestedCodec });
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
  report.native_media = (await rpc('diagnostics')).native;
  if (requestedCodec) {
    const expectedMime = `video/${requestedCodec}`;
    requireCheck(report.media.video_codec === expectedMime && report.native_media.video_codec === expectedMime && report.native_media.video_frames_encoded > 0 && typeof report.native_media.video_encoder_implementation === 'string' && report.native_media.video_encoder_implementation.length > 0, 'E2E_REQUESTED_CODEC_NOT_OBSERVED');
    report.checks.requested_codec_encoded_and_decoded = true;
  }
  if (withFiles) {
    stage = 'files';
    report.files = { status: 'not_verified', scope: 'Real bidirectional DataChannel bytes and disk writes using isolated fixture selection; native and browser user pickers are not exercised.' };
    await page.evaluate(() => window.nativeE2E.enableFiles());
    await page.evaluate(() => window.nativeE2E.offerFiles());
    let incoming;
    await until(async () => { incoming = (await rpc('file_state')).files.items.filter(item => !item.outgoing && item.event === 'offer'); return incoming.length === 2; }, 'E2E_NATIVE_FILE_OFFERS_MISSING');
    for (const item of incoming) await rpc('file_accept', { target_id: item.id });
    await until(async () => (await rpc('file_state')).files.items.filter(item => !item.outgoing && item.event === 'complete').length === 2, 'E2E_BROWSER_FILES_NOT_SAVED', 45000);
    const expectedBrowser = Buffer.from(Uint8Array.from({ length: 1048593 }, (_, n) => (n * 31 + 17) & 255));
    requireCheck(readFileSync(join(fileRoot, 'browser-empty.bin')).length === 0 && readFileSync(join(fileRoot, 'browser-multichunk.bin')).equals(expectedBrowser), 'E2E_NATIVE_FILE_BYTES_MISMATCH');
    report.files.browser_to_native = incoming.map(item => ({ name: item.name, size: item.size, sha256: createHash('sha256').update(readFileSync(join(fileRoot, item.name))).digest('hex') }));
    await rpc('file_offer');
    let offers;
    await until(async () => { offers = (await page.evaluate(() => window.nativeE2E.fileEvidence())).offers; return offers.length === 2; }, 'E2E_BROWSER_FILE_OFFERS_MISSING');
    for (const item of offers) await page.evaluate(id => window.nativeE2E.acceptFile(id), item.id);
    await until(async () => (await page.evaluate(() => window.nativeE2E.fileEvidence())).received.length === 2, 'E2E_NATIVE_FILES_NOT_SAVED', 45000);
    const received = (await page.evaluate(() => window.nativeE2E.fileEvidence())).received;
    requireCheck(received.every(item => item.sha256 === createHash('sha256').update(item.name === 'native-empty.bin' ? Buffer.alloc(0) : nativeFileBytes).digest('hex')), 'E2E_BROWSER_FILE_BYTES_MISMATCH');
    await until(async () => (await rpc('file_state')).files.items.filter(item => item.outgoing && item.event === 'complete').length === 2, 'E2E_NATIVE_COMPLETION_ACK_MISSING');
    report.files.native_to_browser = received.map(({ name, size, sha256 }) => ({ name, size, sha256 }));
    await rpc('file_offer');
    let cancelledOffers;
    await until(async () => { cancelledOffers = (await page.evaluate(() => window.nativeE2E.fileEvidence())).offers.filter(item => !offers.some(previous => previous.id === item.id)); return cancelledOffers.length === 2; }, 'E2E_CANCEL_OFFERS_MISSING');
    for (const item of cancelledOffers) await page.evaluate(id => window.nativeE2E.cancelFile(id), item.id);
    await until(async () => (await rpc('file_state')).files.items.filter(item => cancelledOffers.some(offer => offer.id === item.id) && item.event === 'cancelled').length === 2, 'E2E_NATIVE_CANCEL_NOT_OBSERVED');
    await page.evaluate(() => window.nativeE2E.offerFiles());
    let revokedOffers;
    await until(async () => { revokedOffers = (await rpc('file_state')).files.items.filter(item => !item.outgoing && item.event === 'offer'); return revokedOffers.length === 2; }, 'E2E_REVOKE_OFFERS_MISSING');
    await page.evaluate(() => window.nativeE2E.disableFiles());
    await until(async () => (await rpc('file_state')).files.items.filter(item => revokedOffers.some(offer => offer.id === item.id) && item.event === 'cancelled').length === 2, 'E2E_FILE_REVOCATION_NOT_OBSERVED');
    requireCheck(readFileSync(join(fileRoot, 'browser-multichunk.bin')).equals(expectedBrowser), 'E2E_CANCEL_CHANGED_SAVED_FILE');
    const after = await page.evaluate(() => window.nativeE2E.evidence());
    requireCheck(verifiedMedia(after) && after.frames_decoded > report.media.frames_decoded, 'E2E_FILES_INTERRUPTED_VIDEO');
    report.files.cancellation_and_revocation = 'passed'; report.files.saved_file_preserved = true;
    report.files.video_frames_decoded_after = after.frames_decoded;
    report.files.status = 'passed'; report.checks.bidirectional_file_bytes_and_hashes = true; report.checks.video_continues_after_files_disabled = true;
  }
  if (withInput) {
    stage = 'input';
    await page.evaluate(() => window.nativeE2E.prepareInput());
    await target.bringToFront();
    const activation = await rpc('focus_input_target');
    report.input.target_window_found = activation.target_window_found;
    report.input.target_window_activated = activation.target_window_activated;
    // This setup click is confined by Playwright to our page and is cleared
    // before measurement; it does not count as native pointer evidence.
    await target.locator('#input-target').click();
    await target.keyboard.press('KeyA');
    report.input.target_event_probe = await target.evaluate(() => ['keydown', 'keyup'].every(type => window.nativeInputTarget.events.some(item => item.type === type && item.code === 'KeyA')));
    requireCheck(report.input.target_event_probe, 'E2E_TARGET_EVENT_PROBE_FAILED');
    await target.evaluate(() => { document.querySelector('#input-target').value = ''; document.querySelector('#input-target').focus(); window.nativeInputTarget.events = []; });
    const focused = () => target.evaluate(() => document.hasFocus() && document.activeElement === document.querySelector('#input-target'));
    await until(focused, 'E2E_INPUT_TARGET_NOT_FOREGROUND', 5000);
    const osFocus = await rpc('input_focus');
    report.input.window_diagnostics = osFocus.window_diagnostics;
    report.input.os_foreground_verified = osFocus.foreground_matches_target;
    requireCheck(osFocus.foreground_matches_target, 'E2E_INPUT_OS_FOREGROUND_MISMATCH');
    await page.evaluate(() => window.nativeE2E.requestInput());
    await until(async () => (await page.evaluate(() => window.nativeE2E.evidence())).input_enabled, 'E2E_INPUT_HANDSHAKE_FAILED', 7000);
    requireCheck(await focused(), 'E2E_INPUT_TARGET_LOST_FOCUS');
    const point = (await rpc('input_target_point')).point;
    report.input.target_point = point;
    requireCheck(point.hit_matches_target_root && point.hit_matches_target_pid, 'E2E_INPUT_TARGET_OBSCURED');
    // A real bounded native click establishes Chrome's native renderer focus;
    // CDP/DOM focus alone does not establish the Win32 keyboard focus window.
    await page.evaluate(value => window.nativeE2E.sendPointer(value), point);
    await until(() => target.evaluate(() => ['pointerdown', 'pointerup'].every(type => window.nativeInputTarget.events.some(item => item.type === type && item.target_matches))), 'E2E_REAL_POINTER_NOT_OBSERVED', 5000);
    report.input.pointer_down_up = true;
    report.input.keyboard_sender = await page.evaluate(() => window.nativeE2E.sendKey());
    await until(() => target.evaluate(() => ['keydown', 'keyup'].every(type => window.nativeInputTarget.events.some(item => item.type === type && item.code === 'KeyA'))), 'E2E_REAL_KEYBOARD_NOT_OBSERVED', 5000);
    report.input.keyboard_down_up = true;
    requireCheck(await focused(), 'E2E_INPUT_TARGET_LOST_FOCUS');
    await target.evaluate(() => { document.querySelector('#input-target').value = ''; });
    await page.evaluate(() => window.nativeE2E.sendText());
    await until(() => target.evaluate(() => document.querySelector('#input-target').value === '验收✓'), 'E2E_REAL_UNICODE_TEXT_NOT_OBSERVED', 5000);
    report.input.unicode_text = true;
    report.input.trusted_event_count = await target.evaluate(() => window.nativeInputTarget.events.length);
    const previousEpoch = (await page.evaluate(() => window.nativeE2E.evidence())).input_epoch;
    await page.evaluate(() => window.nativeE2E.releaseInput());
    await page.evaluate(() => window.nativeE2E.requestInput());
    await until(async () => { const evidence = await page.evaluate(() => window.nativeE2E.evidence()); return evidence.input_enabled && evidence.input_epoch > previousEpoch; }, 'E2E_INPUT_REACQUIRE_FAILED', 7000);
    await target.evaluate(() => { window.nativeInputTarget.events = []; });
    const beforeStale = (await rpc('diagnostics')).native;
    await page.evaluate(epoch => window.nativeE2E.sendStaleInput(epoch), previousEpoch);
    await until(async () => (await rpc('diagnostics')).native.input_ignored_epoch === beforeStale.input_ignored_epoch + 1, 'E2E_STALE_INPUT_NOT_REJECTED', 3000);
    requireCheck(await target.evaluate(() => !window.nativeInputTarget.events.some(item => item.type === 'keydown')), 'E2E_STALE_INPUT_WAS_INJECTED');
    await page.evaluate(() => window.nativeE2E.sendKey());
    await until(() => target.evaluate(() => ['keydown', 'keyup'].every(type => window.nativeInputTarget.events.some(item => item.type === type && item.code === 'KeyA'))), 'E2E_INPUT_DID_NOT_SURVIVE_STALE_EPOCH', 3000);
    report.input.stale_epoch_rejected = true;
    await target.evaluate(() => { window.nativeInputTarget.events = []; });
    await page.evaluate(() => { window.nativeE2E.pauseHeartbeat(); window.nativeE2E.holdKey(); });
    await until(() => target.evaluate(() => window.nativeInputTarget.events.some(item => item.type === 'keydown' && item.code === 'KeyA')), 'E2E_WATCHDOG_KEYDOWN_MISSING', 3000);
    await until(() => target.evaluate(() => window.nativeInputTarget.events.some(item => item.type === 'keyup' && item.code === 'KeyA')), 'E2E_WATCHDOG_DID_NOT_RELEASE', 2500);
    const watchdogRelease = await target.evaluate(() => {
      const events = window.nativeInputTarget.events;
      return events.find(item => item.type === 'keyup' && item.code === 'KeyA').timestamp - events.find(item => item.type === 'keydown' && item.code === 'KeyA').timestamp;
    });
    requireCheck(watchdogRelease >= 0 && watchdogRelease <= 2000, 'E2E_WATCHDOG_RELEASE_TOO_SLOW');
    report.input.heartbeat_watchdog = { passed: true, release_ms: watchdogRelease, measured_from: 'trusted_keydown' };
    await page.evaluate(() => { window.nativeE2E.restoreHeartbeat(); window.nativeE2E.releaseInput(); });
    report.media = await page.evaluate(() => window.nativeE2E.evidence());
    requireCheck(verifiedMedia(report.media), 'E2E_INPUT_RELEASE_FAILED');
    report.input.released = true;
    await page.evaluate(() => window.nativeE2E.closeSession());
    await until(async () => (await rpc('state')).session_idle, 'E2E_NORMAL_SESSION_DID_NOT_CLOSE', 5000);
    report.checks.clean_session_shutdown = true;
    // A second independently paired/approved session tests process death. The
    // first session's normal shutdown and healthy media evidence remain intact.
    stage = 'worker_crash';
    const crashPairing = await page.evaluate(() => window.nativeE2E.pair());
    await host.read(item => item.event === 'approval' && item.approval.kind === 'pairing' && item.approval.id === crashPairing.id);
    await rpc('approve_pairing', { target_id: crashPairing.id });
    const crashDisplay = await host.read(item => item.event === 'approval' && item.approval.kind === 'pairing_display' && item.approval.id === crashPairing.id);
    const crashSession = await page.evaluate(code => window.nativeE2E.confirm(code), crashDisplay.approval.display_code);
    await host.read(item => item.event === 'approval' && item.approval.kind === 'session' && item.approval.id === crashSession.session_id);
    await rpc('approve_session', { target_id: crashSession.session_id });
    await page.evaluate(id => window.nativeE2E.start(id), crashSession.session_id);
    await until(async () => verifiedMedia(await page.evaluate(() => window.nativeE2E.evidence())), 'E2E_CRASH_SESSION_MEDIA_MISSING', 30000);
    await page.evaluate(() => window.nativeE2E.prepareInput());
    await rpc('focus_input_target');
    requireCheck((await rpc('input_focus')).foreground_matches_target, 'E2E_INPUT_OS_FOREGROUND_MISMATCH');
    await page.evaluate(() => window.nativeE2E.requestInput());
    await until(async () => (await page.evaluate(() => window.nativeE2E.evidence())).input_enabled, 'E2E_CRASH_INPUT_HANDSHAKE_FAILED', 7000);
    const crashPoint = (await rpc('input_target_point')).point;
    requireCheck(crashPoint.hit_matches_target_root && crashPoint.hit_matches_target_pid, 'E2E_INPUT_TARGET_OBSCURED');
    await target.evaluate(() => { window.nativeInputTarget.events = []; });
    await page.evaluate(value => window.nativeE2E.sendPointer(value), crashPoint);
    await until(() => target.evaluate(() => ['pointerdown', 'pointerup'].every(type => window.nativeInputTarget.events.some(item => item.type === type && item.target_matches))), 'E2E_CRASH_TARGET_CLICK_MISSING', 3000);
    await target.evaluate(() => { window.nativeInputTarget.events = []; });
    await page.evaluate(() => window.nativeE2E.holdKey());
    await page.evaluate(value => window.nativeE2E.sendPointer({ ...value, hold: true }), crashPoint);
    await until(() => target.evaluate(() => window.nativeInputTarget.events.some(item => item.type === 'keydown' && item.code === 'KeyA' && item.target_matches) && window.nativeInputTarget.events.some(item => item.type === 'pointerdown' && item.target_matches)), 'E2E_CRASH_HELD_INPUT_MISSING', 3000);
    requireCheck(await target.evaluate(() => !window.nativeInputTarget.events.some(item => item.type === 'keyup' || item.type === 'pointerup')), 'E2E_CRASH_INPUT_ALREADY_RELEASED');
    const crashStarted = await target.evaluate(() => performance.now());
    await rpc('crash_worker');
    await until(() => target.evaluate(start => ['keyup', 'pointerup'].every(type => window.nativeInputTarget.events.some(item => item.type === type && item.timestamp >= start)), crashStarted), 'E2E_WORKER_CRASH_DID_NOT_RELEASE', 2200);
    const release = await target.evaluate(start => ({
      key_release_ms: window.nativeInputTarget.events.find(item => item.type === 'keyup' && item.code === 'KeyA' && item.timestamp >= start).timestamp - start,
      button_release_ms: window.nativeInputTarget.events.find(item => item.type === 'pointerup' && item.timestamp >= start).timestamp - start,
    }), crashStarted);
    requireCheck(release.key_release_ms >= 0 && release.key_release_ms <= 2000 && release.button_release_ms >= 0 && release.button_release_ms <= 2000, 'E2E_WORKER_CRASH_RELEASE_TOO_SLOW');
    report.input.worker_crash = { passed: true, ...release };
    report.input.status = 'passed'; delete report.input.reason;
    report.limitations = ['Cross-network traversal, Android, audio, clipboard and files are not established by this run.'];
  }
  stage = 'shutdown';
  await page.evaluate(() => window.nativeE2E.close());
  await rpc('shutdown');
  if (!withInput) report.checks.clean_session_shutdown = true;
  report.status = 'passed';
  report.limitations = [
    `Cross-network traversal, Android, audio, clipboard${withFiles ? '' : ', files'}${withInput ? '' : ', input'} are not established by this run.`,
    ...(withFiles ? ['File selection uses a confined test fixture and browser origin-private storage; native and browser user pickers are not established.'] : []),
  ];
} catch (error) {
  if (withInput && host && !host.closed && !host.failure) {
    try { report.input.native_diagnostics = (await rpc('diagnostics')).native; } catch {}
    try { report.input.failure_window_diagnostics = (await rpc('input_focus')).window_diagnostics; } catch {}
  }
  if (page && !page.isClosed()) {
    try { report.media = await page.evaluate(() => window.nativeE2E?.evidence()); } catch {}
  }
  if (withInput && target && !target.isClosed()) {
    try { report.input.observed_events = await target.evaluate(() => window.nativeInputTarget.events.slice(0, 32).map(({ type, code, target_matches }) => ({ type, code, target_matches }))); } catch {}
    try { report.input.target_value_length = await target.evaluate(() => document.querySelector('#input-target').value.length); } catch {}
  }
  report.status = report.checks.native_backend_ready ? 'failed' : 'not_verified';
  report.failure = { stage, code: error instanceof CheckFailure ? error.code : (String(error.message).match(/\bRD_[A-Z_]{3,80}\b/)?.[0] ?? 'E2E_UNEXPECTED_FAILURE') };
  process.exitCode = 1;
} finally {
  if (page && !page.isClosed()) await page.evaluate(() => window.nativeE2E?.close()).catch(() => {});
  await browser?.close().catch(() => {});
  await targetBrowser?.close().catch(() => {});
  await targetServer?.close().catch(() => {});
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
