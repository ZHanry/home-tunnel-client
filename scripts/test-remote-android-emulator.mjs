#!/usr/bin/env node
import { createHash, randomBytes } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const options = Object.create(null);
const names = new Set(['--worker', '--sha256', '--host-exe', '--server-root', '--android-root', '--adb', '--serial', '--ca', '--cert', '--key', '--output', '--mode']);
for (let index = 2; index < process.argv.length; index += 2) {
  const name = process.argv[index];
  if (!names.has(name) || !process.argv[index + 1] || options[name]) throw new Error('Invalid emulator acceptance arguments');
  options[name] = process.argv[index + 1];
}
for (const name of names) if (name !== '--mode' && !options[name]) throw new Error(`Missing ${name}`);
const mode = options['--mode'] ?? 'same-account';
if (!['same-account', 'cross-account-assist', 'cross-account-fixed', 'cross-account-request'].includes(mode)) throw new Error('Invalid acceptance mode');
if (process.platform !== 'win32' || Number(process.versions.node.split('.')[0]) !== 24) throw new Error('Windows and Node 24 are required');
for (const name of ['--worker', '--host-exe', '--server-root', '--android-root', '--adb', '--ca', '--cert', '--key', '--output']) {
  if (!isAbsolute(options[name])) throw new Error(`${name} must be absolute`);
}
const worker = options['--worker'];
const expectedHash = options['--sha256'].toLowerCase();
if (!/^[a-f0-9]{64}$/.test(expectedHash) || createHash('sha256').update(readFileSync(worker)).digest('hex') !== expectedHash) throw new Error('Pinned Windows worker SHA-256 does not match');
const serverRoot = options['--server-root'];
const androidRoot = options['--android-root'];
const adb = options['--adb'];
const serial = options['--serial'];
const reportPath = options['--output'];
if (!existsSync(join(serverRoot, 'control-center', 'dist', 'server.js'))) throw new Error('Build the server before acceptance');
const temporary = mkdtempSync(join(tmpdir(), 'ht-android-emulator-'));
copyFileSync(options['--ca'], join(temporary, 'ca.crt'));
const children = [];
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const adbCall = (args, timeout = 15000) => spawnSync(adb, ['-s', serial, ...args], { encoding: 'utf8', windowsHide: true, timeout, maxBuffer: 65536 });
function adbRequire(args) {
  const result = adbCall(args);
  if (result.status !== 0) throw new Error('Selected emulator or ADB reverse is unavailable');
  return result.stdout.trim();
}
class PipeProcess {
  constructor(executable, args, environment = process.env) {
    this.messages = [];
    this.eventKinds = [];
    this.waiters = new Set();
    this.closed = false;
    this.child = spawn(executable, args, { cwd: root, env: environment, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    children.push(this);
    this.child.stderr.resume();
    this.child.stdin.on('error', () => {});
    this.exit = new Promise(resolve => this.child.once('exit', (code, signal) => { this.closed = true; this.notify(); resolve({ code, signal }); }));
    this.child.once('error', () => { this.closed = true; this.notify(); });
    createInterface({ input: this.child.stdout }).on('line', line => {
      if (!line.startsWith('HT_NATIVE ') || line.length > 262144 || this.messages.length >= 128) return;
      try {
        const value = JSON.parse(line.slice(10));
        this.eventKinds.push(value.event === 'approval' ? `approval:${value.approval?.kind}` : value.event ?? 'response');
        this.messages.push(value); this.notify();
      }
      catch { this.closed = true; this.notify(); }
    });
  }
  notify() { for (const waiter of this.waiters) waiter(); }
  send(value) { this.child.stdin.write(`${JSON.stringify(value)}\n`); }
  read(predicate, timeout = 30000) {
    return new Promise((resolve, reject) => {
      const finish = (error, value) => { clearTimeout(timer); this.waiters.delete(check); error ? reject(error) : resolve(value); };
      const check = () => {
        const failure = this.messages.find(message => message.event === 'fatal' || message.event === 'unavailable');
        if (failure) return finish(new Error(failure.code || 'Acceptance process failed'));
        const index = this.messages.findIndex(predicate);
        if (index >= 0) return finish(null, this.messages.splice(index, 1)[0]);
        if (this.closed) finish(new Error('Acceptance process exited'));
      };
      const timer = setTimeout(() => finish(new Error('Acceptance event timed out')), timeout);
      this.waiters.add(check);
      check();
    });
  }
  async stop() {
    if (this.closed) return;
    this.child.stdin.end();
    await Promise.race([this.exit, pause(5000)]);
    if (!this.closed) { this.child.kill(); await Promise.race([this.exit, pause(5000)]); }
  }
}
let fixture, host, browser, browserServer, instrumentation, reversePort, stage = 'initialization', instrumentationFailure = '';
let commandId = 0;
async function hostAction(action, extra = {}) {
  const id = ++commandId;
  host.send({ id, action, ...extra });
  const result = await host.read(message => message.id === id, 25000);
  if (!result.ok) throw new Error(`Host action ${action} failed: ${result.code}`);
  return result;
}
function pairingEvidence() {
  const result = adbCall(['exec-out', 'run-as', 'io.github.zhanry.hometunnel.debug', 'cat', 'files/remote-surface-pairing.json'], 5000);
  if (result.status !== 0 || !result.stdout) return null;
  try { return JSON.parse(result.stdout); } catch { return null; }
}
async function waitPairingEvidence(id, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const evidence = pairingEvidence();
    if (evidence?.pairing_id === id) return evidence;
    await pause(250);
  }
  throw new Error('Android pairing evidence was not written');
}
try {
  stage = 'fixture';
  fixture = new PipeProcess(process.execPath, [join(root, 'tests', 'remote-native', 'fixture.mjs')], {
    ...process.env, HT_SERVER_ROOT: serverRoot, HT_NATIVE_E2E_TEMP: temporary,
    HT_NATIVE_E2E_HTTPS: '1', HT_NATIVE_E2E_TLS_CERT: options['--cert'], HT_NATIVE_E2E_TLS_KEY: options['--key'],
  });
  const initial = await fixture.read(value => value.event === 'fixture');
  const origin = new URL(initial.origin);
  if (origin.protocol !== 'https:' || origin.hostname !== '127.0.0.1' || !initial.password) throw new Error('Isolated HTTPS fixture is required');
  reversePort = origin.port;
  adbRequire(['reverse', `tcp:${reversePort}`, `tcp:${reversePort}`]);
  const { chromium } = await import('@playwright/test');
  browserServer = await chromium.launchServer({ headless: false, args: ['--window-position=60,60', '--window-size=1000,750'] });
  browser = await chromium.connect(browserServer.wsEndpoint());
  const context = await browser.newContext({ viewport: null, ignoreHTTPSErrors: true });
  const target = await context.newPage();
  await target.goto(`${initial.origin}/__native-e2e/target.html`);
  await target.bringToFront();
  await target.locator('#input-target').click();
  await target.evaluate(() => { document.querySelector('#input-target').value = ''; window.nativeInputTarget.events = []; });
  const inputTargetPid = browserServer.process().pid;
  if (!Number.isInteger(inputTargetPid) || inputTargetPid < 1) throw new Error('Isolated input target process is unavailable');
  stage = 'host';
  host = new PipeProcess(options['--host-exe'], []);
  host.send({ ...initial, worker, sha256: expectedHash, store_path: join(temporary, 'host-state.json'), ca_file: join(temporary, 'ca.crt'), input_target_pid: inputTargetPid });
  const ready = await host.read(value => value.event === 'host');
  if (!ready.capabilities?.available || ready.capabilities.status !== 'ready' || !ready.capabilities.displays?.length) throw new Error('Native Windows host is unavailable');
  const focus = await hostAction('focus_input_target');
  if (!focus.foreground_matches_target) throw new Error('Isolated input target could not gain OS focus');
  const inputPoint = (await hostAction('input_target_point')).point;
  if (!inputPoint?.hit_matches_target_root || !inputPoint.hit_matches_target_pid) throw new Error('Isolated input target is obscured');
  stage = 'android';
  const display = ready.capabilities.displays[0];
  const crossAccount = mode !== 'same-account';
  const assistance = mode === 'cross-account-assist' ? (await hostAction('create_invite')).invite : null;
  const fixedPassword = mode === 'cross-account-fixed' ? randomBytes(24).toString('base64url') : null;
  const accessProfile = mode === 'cross-account-fixed'
    ? (await hostAction('set_fixed_password', { fixed_password: fixedPassword })).profile
    : mode === 'cross-account-request' ? (await hostAction('create_access_profile')).profile : null;
  if (assistance && (!/^[0-9]{9}$/.test(assistance.device_id) || !assistance.temporary_password || !assistance.id)) throw new Error('Host assistance invitation is invalid');
  if (accessProfile && !/^[0-9]{9}$/.test(accessProfile.device_id)) throw new Error('Host access profile is invalid');
  const privateFixture = join(temporary, 'android-fixture.json');
  writeFileSync(privateFixture, JSON.stringify({
    allow_test_pairing: true, api_base_url: `${initial.origin}/api/v1/`,
    management_access_token: crossAccount ? initial.assist_account_token : initial.account_token,
    password: crossAccount ? initial.assist_password : initial.password, mfa_code: '',
    user_id: crossAccount ? initial.assist_user_id : initial.user_id, server_instance_id: initial.server_instance_id,
    server_active_kid: initial.active_kid, host_endpoint_id: ready.endpoint_id,
    host_jkt: ready.jkt, width: display.width, height: display.height,
    access_mode: mode,
    input_point: { x: inputPoint.x, y: inputPoint.y, width: inputPoint.width, height: inputPoint.height },
    ...(assistance ? { assist_device_id: assistance.device_id, assist_temporary_password: assistance.temporary_password } : {}),
    ...(accessProfile ? { access_device_id: accessProfile.device_id } : {}),
    ...(fixedPassword ? { fixed_password: fixedPassword } : {}),
  }));
  instrumentation = spawn('python', [join(androidRoot, 'scripts', 'run-remote-surface-acceptance.py'), '--adb', adb, '--serial', serial, '--fixture', privateFixture, '--output', reportPath], {
    cwd: androidRoot, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  instrumentation.stdout.resume();
  instrumentation.stderr.on('data', chunk => {
    const code = String(chunk).match(/RD_ACCEPTANCE_[A-Z0-9_]{1,80}/)?.[0];
    if (code) instrumentationFailure = code;
  });
  const instrumentExit = new Promise(resolve => instrumentation.once('exit', (code, signal) => resolve({ code, signal })));
  stage = 'pairing';
  if (mode === 'cross-account-request') {
    let requests = [];
    for (let attempt = 0; attempt < 60; attempt++) {
      requests = (await hostAction('list_access_requests')).requests ?? [];
      if (requests.length) break;
      await pause(250);
    }
    if (requests.length !== 1) throw new Error('Expected one isolated access request');
    await hostAction('approve_access_request', { target_id: requests[0].id });
  }
  const requested = await Promise.race([
    host.read(value => value.event === 'approval' && value.approval?.kind === (crossAccount ? 'pairing_display' : 'pairing'), 90000),
    instrumentExit.then(() => { throw new Error('Android instrumentation ended before pairing'); }),
  ]);
  const approval = requested.approval;
  await hostAction('bind_controller', { controller_id: approval.controller_endpoint_id, controller_jkt: approval.controller_thumbprint });
  if (!crossAccount) await hostAction('approve_pairing', { target_id: approval.id });
  const confirmed = crossAccount ? requested : await host.read(value => value.event === 'approval' && value.approval?.kind === 'pairing_display' && value.approval.id === approval.id);
  const remoteCode = await waitPairingEvidence(approval.id);
  if (remoteCode.comparison_code !== confirmed.approval.display_code || remoteCode.controller_jkt !== approval.controller_thumbprint) throw new Error('Pairing comparison code or controller identity differs');
  stage = 'surface';
  const result = await Promise.race([instrumentExit, pause(180000).then(() => ({ code: -1 }))]);
  if (result.code !== 0 || !existsSync(reportPath)) throw new Error(`Android decoded Surface acceptance failed: ${instrumentationFailure || 'RD_ACCEPTANCE_INSTRUMENTATION_FAILED'}`);
  const evidence = JSON.parse(readFileSync(reportPath, 'utf8'));
  if (evidence.passed !== true || evidence.transport_policy !== 'verified-direct-udp') throw new Error('Android evidence is incomplete');
  const input = await target.evaluate(() => ({
    events: window.nativeInputTarget.events,
    text: document.querySelector('#input-target').value,
  }));
  const observed = type => input.events.some(event => event.type === type && event.target_matches);
  const keyboard = type => input.events.some(event => event.type === type && event.code === 'KeyA');
  if (!observed('pointerdown') || !observed('pointerup') || !keyboard('keydown') || !keyboard('keyup') || !input.text.endsWith('验收✓')) {
    throw new Error('Real native pointer, keyboard, or Unicode input was not observed');
  }
  if (crossAccount && host.eventKinds.some(kind => kind === 'approval:pairing' || kind === 'approval:session')) {
    throw new Error('Pre-authorized cross-account access unexpectedly requested another host confirmation');
  }
  if (assistance) await hostAction('revoke_invite', { target_id: assistance.id });
  writeFileSync(reportPath, `${JSON.stringify({ ...evidence, access_mode: mode, no_extra_host_confirmation: crossAccount, native_pointer_verified: true, native_keyboard_verified: true, native_unicode_text_verified: true }, null, 2)}\n`);
  process.stdout.write(`Android emulator native Surface acceptance passed; evidence: ${reportPath}\n`);
} catch (error) {
  process.stderr.write(`Android emulator acceptance failed at ${stage}: ${error.message}\n`);
  if (host) {
    process.stderr.write(`Host events: ${host.eventKinds.join(', ').slice(0, 500)}\n`);
    process.stderr.write(`Host failures: ${host.messages.filter(message => message.event === 'fatal' || message.event === 'unavailable').map(message => `${message.code}:${message.stage ?? 'startup'}:${message.session_active ?? false}`).join(', ')}\n`);
  }
  process.exitCode = 1;
} finally {
  if (instrumentation && instrumentation.exitCode === null) instrumentation.kill();
  if (browser) await Promise.race([browser.close().catch(() => {}), pause(5000)]);
  if (browserServer) await Promise.race([browserServer.close().catch(() => {}), pause(5000)]);
  if (host) await host.stop();
  if (fixture) await fixture.stop();
  if (reversePort) adbCall(['reverse', '--remove', `tcp:${reversePort}`]);
  rmSync(temporary, { recursive: true, force: true });
}
process.exit(process.exitCode ?? 0);
