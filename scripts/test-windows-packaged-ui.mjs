// Exercise the HTML/CSS/JS embedded in the final GUI, inside its real WebView2.
// Only local API responses are fixtures. No source asset is served or substituted.
import { chromium, expect as baseExpect } from '@playwright/test';
const expect = baseExpect.configure({ timeout: 12_000 });
import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { join } from 'node:path';

const output = process.env.HT_WINDOWS_UI_OUTPUT;
const bridge = process.env.HT_WINDOWS_UI_BRIDGE;
if (!output || !bridge || process.env.GITHUB_ACTIONS !== 'true' || process.platform !== 'win32') {
  throw new Error('This harness requires the isolated Windows package capture runner');
}
const report = {
  schema_version: 1, status: 'pending', version: process.env.HT_WINDOWS_UI_VERSION,
  package_sha256: process.env.HT_WINDOWS_UI_ARCHIVE_SHA256,
  source_revision: process.env.HT_WINDOWS_UI_SOURCE_REVISION || process.env.GITHUB_SHA,
  fixture: 'CDP local-API responses in the actual packaged native WebView2; packaged assets are never replaced',
  backend_fixture: true, full_remote_session_acceptance: false,
  actual_screenshots_require_visual_review: true,
  not_verified: ['Live login or device registration', 'Live remote authentication handoff',
    'Native approval-popup lifecycle and separate popup HWND', 'Real remote video/input/files/audio',
    'Physical Windows DPI configurations', 'Long-term stability'],
  cases: [], screenshots: [], unexpected_requests: [], page_errors: 0,
};
let browser, activeCase = 'attach_packaged_webview', bridgeID = 0;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function native(command) {
  const id = ++bridgeID;
  await writeFile(join(bridge, 'request.tmp'), JSON.stringify({ id, ...command }));
  await rename(join(bridge, 'request.tmp'), join(bridge, 'request.json'));
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    try {
      const reply = JSON.parse(await readFile(join(bridge, 'response.json'), 'utf8'));
      if (reply.id === id && reply.status === 'done') return;
    } catch {}
    await delay(100);
  }
  throw new Error('Native capture bridge timeout');
}
async function shot(name) {
  await native({ action: 'capture', name: `${name}.png` });
  report.screenshots.push(`${name}.png`);
}
async function check(name, work) {
  activeCase = name;
  await work();
  report.cases.push({ name, status: 'passed' });
}
try {
  await mkdir(output, { recursive: true });
  browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
  const contexts = browser.contexts();
  const page = contexts.flatMap(context => context.pages()).find(p => p.url().startsWith('http://127.0.0.1:8788/') && !p.url().includes('/popup.html'));
  if (!page) throw new Error('Actual packaged WebView2 page not found');
  const context = page.context();
  const origin = new URL(page.url()).origin;
  // Keep the private desktop token in memory only, including when inspecting the
  // packaged popup page. It must never enter screenshots, traces, logs or JSON.
  const entryURL = page.url();
  const fragment = new URL(entryURL).hash;
  page.on('pageerror', () => { report.page_errors++; });
  await expect(page.locator('#login')).toBeVisible();
  const localID = '11111111-1111-4111-8111-111111111111';
  const remoteID = '22222222-2222-4222-8222-222222222222';
  let signedIn = false, deviceName = 'QA Windows desktop';
  let loginCalls = 0, loginFailure = false, renameFailure = false;
  const remoteWindows = [], mutations = [];
  const remoteState = {
    enrolled: true, enabled: true, running: true, capabilities: { available: true, status: 'ready', permissions: ['view', 'input.keyboard', 'input.pointer', 'input.text'] },
    pending: [], grants: [], invites: [], access_requests: [], files: null,
    access_profile: { device_id: '482913570', fixed_password_enabled: false, revision: 1 },
    fixed_revision: 1, emergency_key: 'X', service: { installed: false, running: false },
  };
  const json = (route, value, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(value) });
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.origin !== origin) {
      report.unexpected_requests.push('non-loopback-origin');
      return route.abort();
    }
    if (!url.pathname.startsWith('/local/')) return route.continue();
    const path = url.pathname, method = route.request().method();
    if (path === '/local/state') return json(route, {
      enrolled: signedIn, agent_state: 'Online', device_id: localID, device_name: deviceName,
      version: report.version, console_url: 'https://fixture.example.invalid', connections: [],
    });
    if (path === '/local/login' && method === 'POST') {
      loginCalls++; await delay(200);
      if (loginFailure === 'mfa') return json(route, { error_code: 'MFA_REQUIRED', message: 'QA fixture requires a dynamic code' }, 401);
      if (loginFailure === 'password-change') return json(route, { message: 'the account requires a password change' }, 401);
      if (loginFailure) return json(route, { message: 'QA sign-in failure; please retry' }, 401);
      signedIn = true; return json(route, { ok: true });
    }
    if (path === '/local/logout' && method === 'POST') { signedIn = false; return json(route, { ok: true }); }
    if (path === '/local/remote/state') return json(route, remoteState);
    if (path === '/local/devices') return json(route, { local_device_id: localID, items: [
      { id: localID, name: deviceName, status: 'active', online: true },
      { id: remoteID, name: 'QA other computer', status: 'active', online: true },
      { id: '33333333-3333-4333-8333-333333333333', name: 'QA offline computer', status: 'active', online: false },
    ] });
    if (path === '/local/device/name' && method === 'PATCH') {
      if (renameFailure) return json(route, { message: 'QA rename temporarily unavailable' }, 503);
      const body = route.request().postDataJSON();
      deviceName = body.name; mutations.push({ action: 'rename', name: deviceName });
      return json(route, { device_name: deviceName });
    }
    if (path === '/local/update') return json(route, { current: report.version, newer: false });
    if (path === '/local/remote/window' && method === 'POST') {
      const body = route.request().postDataJSON(); remoteWindows.push(body);
      return json(route, { ok: true });
    }
    if (path === '/local/remote/popup' && method === 'POST') return json(route, { ok: true });
    if (path === '/local/remote/action' && method === 'POST') {
      const body = route.request().postDataJSON(); mutations.push({ action: body.action });
      if (body.action === 'reject_access_request') remoteState.access_requests = [];
      if (body.action === 'stop') remoteState.active_session_id = '';
      return json(route, { ok: true });
    }
    // An unhandled request must never reach the real local mutating handler.
    report.unexpected_requests.push(`${method} ${path}`);
    return json(route, { message: 'Unhandled packaged-UI fixture request' }, 501);
  });
  await check('login_readable_at_native_minimum', async () => {
    await native({ action: 'resize', width: 960, height: 640 });
    await page.evaluate(() => { localStorage.setItem('ht_theme', 'light'); localStorage.setItem('ht_locale', 'zh-CN'); });
    await page.reload();
    await expect(page.locator('#login')).toBeVisible();
    const geometry = await page.locator('#server, #username, #password').evaluateAll(nodes => nodes.map(n => {
      const r = n.getBoundingClientRect(); return { height: r.height, width: r.width };
    }));
    expect(geometry).toHaveLength(3);
    for (const field of geometry) { expect(field.height).toBeGreaterThanOrEqual(38); expect(field.width).toBeGreaterThan(200); }
    report.login_field_geometry = geometry;
    await shot('login-minimum-top');
    await page.locator('#login-button').scrollIntoViewIfNeeded();
    await expect(page.locator('#login-button')).toBeInViewport();
    await page.locator('#login-button').focus();
    await expect(page.locator('#login-button')).toBeFocused();
    await shot('login-minimum-submit-focus');
  });
  await check('login_failure_retry_and_single_submission', async () => {
    await native({ action: 'resize', width: 1100, height: 760 });
    await page.locator('#server').fill('https://fixture.example.invalid');
    await page.locator('#username').fill('qa-fixture-user');
    await page.locator('#password').fill('qa-fixture-only-password');
    loginFailure = true;
    await page.locator('#password').press('Enter');
    await expect(page.locator('#login-error')).toContainText('QA sign-in failure');
    expect(loginCalls).toBe(1);
    await expect(page.locator('#username')).toHaveValue('qa-fixture-user');
    await shot('login-fixture-retry');
    loginFailure = 'mfa';
    await page.locator('#login-button').click();
    await expect(page.locator('#mfa-step')).toBeVisible();
    await native({ action: 'resize', width: 960, height: 640 });
    await page.locator('#mfa-code').scrollIntoViewIfNeeded();
    await expect(page.locator('#mfa-code')).toBeInViewport();
    await shot('login-minimum-mfa');
    await page.locator('#mfa-code').fill('123456');
    loginFailure = 'password-change';
    await page.locator('#login-button').click();
    await expect(page.locator('#password-change')).toBeVisible();
    await page.locator('#confirm-password').scrollIntoViewIfNeeded();
    await expect(page.locator('#confirm-password')).toBeInViewport();
    expect(await page.locator('#confirm-password').evaluate(el => el.getBoundingClientRect().height)).toBeGreaterThanOrEqual(38);
    await shot('login-minimum-password-recovery');
    await page.locator('#new-password').fill('qa-fixture-new-password');
    await page.locator('#confirm-password').fill('qa-fixture-new-password');
    loginFailure = false;
    await page.locator('#login-button').click();
    await expect(page.locator('#remote-page')).toBeVisible();
    expect(loginCalls).toBe(4);
    await native({ action: 'resize', width: 1100, height: 760 });
  });
  await check('settings_immediate_server_and_embedded_updates', async () => {
    await page.locator('#nav-settings').click();
    await expect(page.locator('#settings-server')).toHaveText('https://fixture.example.invalid');
    await expect(page.locator('#settings-update')).toBeVisible();
    await expect(page.locator('#update-current-version')).toHaveText(report.version);
    await expect(page.locator('#nav-updates, #device-tags, #device-favorite, #metadata-save, #settings-back')).toHaveCount(0);
    await shot('settings-immediate');
    await page.locator('#update-check').click();
    await expect(page.locator('#update-page-status')).toContainText('当前没有更新的正式版本');
  });
  await check('rename_local_device_cancel_failure_and_save', async () => {
    await page.locator('#nav-devices').click();
    const localCard = page.locator('.account-device-card').filter({ hasText: localID });
    await expect(localCard.locator('button')).toHaveText('重命名本机');
    await localCard.locator('button').click();
    await expect(page.locator('#device-rename')).toBeVisible();
    await page.locator('#device-name').fill('Cancelled rename');
    await page.locator('#device-rename-cancel').click();
    await expect(page.locator('#device-rename')).toBeHidden();
    expect(mutations).toHaveLength(0);
    await localCard.locator('button').click();
    await page.keyboard.press('Escape');
    await expect(page.locator('#device-rename')).toBeHidden();
    await localCard.locator('button').click();
    await page.locator('#device-name').fill('QA renamed desktop');
    renameFailure = true;
    await page.locator('#device-rename-save').click();
    await expect(page.locator('#device-rename-error')).toContainText('QA rename temporarily unavailable');
    await expect(page.locator('#device-name')).toHaveValue('QA renamed desktop');
    await shot('devices-rename-retry');
    renameFailure = false;
    await page.locator('#device-rename-save').click();
    await expect(page.locator('#device-rename')).toBeHidden();
    await expect(localCard).toContainText('QA renamed desktop');
    await expect(page.locator('#sidebar-machine')).toHaveText('QA renamed desktop');
    expect(mutations).toEqual([{ action: 'rename', name: 'QA renamed desktop' }]);
    await page.locator('#devices-refresh').click();
    await expect(localCard).toContainText('QA renamed desktop');
    await shot('devices-renamed');
  });
  await check('self_connection_rejected_before_native_dispatch', async () => {
    await page.locator('#nav-remote').click();
    await expect(page.locator('#rd-host-code')).toHaveText('482 913 570');
    for (const value of [localID, '482 913 570']) {
      await page.locator('#remote-device-id').fill(value);
      await page.locator('#remote-connect-form button').click();
      await expect(page.locator('#remote-open-error')).not.toBeEmpty();
      expect(remoteWindows).toHaveLength(0);
    }
    await shot('remote-self-blocked');
    await page.locator('#remote-device-id').fill(remoteID);
    await page.locator('#remote-connect-form button').click();
    await expect.poll(() => remoteWindows.length).toBe(1);
    expect(remoteWindows[0]).toEqual({ device_id: remoteID });
  });
  await check('theme_language_and_repeated_navigation', async () => {
    await page.locator('#sidebar-theme').click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await page.locator('#sidebar-locale').click();
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    for (const item of ['devices', 'settings', 'remote', 'settings']) {
      await page.locator(`#nav-${item}`).click();
      await expect(page.locator(`#nav-${item}`)).toHaveClass(/active/);
      await expect(page.locator('.sidebar-nav button.active')).toHaveCount(1);
    }
    await expect(page.locator('#settings-server')).toHaveText('https://fixture.example.invalid');
    await shot('settings-english-dark');
  });
  await check('packaged_popup_page_request_and_session_rendering', async () => {
    // This deliberately renders the packaged popup document in the main HWND.
    // It is a page-rendering test, never evidence of the native popup lifecycle.
    remoteState.access_requests = [{ id: 'qa-request', requester_name: 'QA request fixture',
      device_name: 'QA other computer', controller_endpoint_id: 'qa-controller',
      permissions: ['view', 'input.keyboard'], expires_at: new Date(Date.now() + 120_000).toISOString() }];
    await page.goto(`${origin}/popup.html${fragment}`);
    await page.waitForFunction(() => Boolean(window.htPopup));
    await page.evaluate(() => window.htPopup.show('request'));
    await expect(page.locator('#request')).toBeVisible();
    await expect(page.locator('#request-who')).toHaveText('QA request fixture');
    await expect(page.locator('#request-reject')).toBeEnabled();
    await shot('popup-request-page-in-main-window');
    const before = mutations.length;
    await page.keyboard.press('Enter'); await page.keyboard.press('Escape');
    expect(mutations).toHaveLength(before);
    await page.locator('#request-reject').click();
    await expect.poll(() => mutations.at(-1)?.action).toBe('reject_access_request');
    remoteState.active_session_id = 'qa-session';
    remoteState.grants = [{ session_id: 'qa-session', requester_name: 'QA session fixture', controller_endpoint_id: 'qa-controller' }];
    await page.evaluate(() => window.htPopup.show('session'));
    await expect(page.locator('#session')).toBeVisible();
    await expect(page.locator('#session-who')).toContainText('QA session fixture');
    await shot('popup-session-page-in-main-window');
    await page.locator('#session-stop').click();
    await expect.poll(() => mutations.at(-1)?.action).toBe('stop');
  });
  await check('no_script_errors_or_unexpected_network', async () => {
    expect(report.page_errors).toBe(0);
    expect(report.unexpected_requests).toEqual([]);
  });
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.cases.push({ name: activeCase, status: 'failed', error_type: error.name });
  // No assertion message/trace: they may embed the private native session URL.
  process.exitCode = 1;
} finally {
  report.finished_at = new Date().toISOString();
  await writeFile(join(output, 'regression.json'), JSON.stringify(report, null, 2) + '\n');
  // Disconnecting a CDP connection leaves the actual native app alive for its
  // owner PowerShell process to close and verify; it never launches Chromium.
  if (browser) await browser.close().catch(() => {});
}
