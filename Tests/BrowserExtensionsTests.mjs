// Runs a signed desktop app twice. No changes to the user's browser profile.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {readFile, writeFile, unlink} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createServer as createSocketServer} from 'node:net';
import path from 'node:path';

const work = process.argv[2], root = process.cwd();
const control = path.join(work, 'control'), profile = path.join(work, 'profile');
const app = path.join(work, 'Talaria.app');
const fixture = path.join(root, 'Tests/Fixtures/browser-extension-storage');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const server = createServer((request, response) => {
  response.setHeader('Content-Type', 'text/html');
  response.end('<!doctype html><title>Extension fixture</title><h1>Ordinary page</h1><p>The extension inserts a marker above this text.</p>');
});
server.listen(0, '127.0.0.1'); await once(server, 'listening');
const url = `http://127.0.0.1:${server.address().port}/`;
let launcher, pid, sockets = [], debugURL;

async function until(fn, description, timeout = 20000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    const value = await fn(); if (value) return value;
    await delay(100);
  }
  throw new Error(`Timed out: ${description}`);
}

async function connect(address) {
  const socket = new WebSocket(address); sockets.push(socket); await once(socket, 'open');
  let sequence = 0; const pending = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data), item = pending.get(message.id);
    if (!item) return;
    pending.delete(message.id); clearTimeout(item.timer);
    message.error ? item.reject(new Error(JSON.stringify(message.error))) : item.resolve(message.result);
  });
  return (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method} ${(params.expression || '').slice(0,160)}`)); }, 10000);
    pending.set(id, {resolve, reject, timer}); socket.send(JSON.stringify({id, method, params}));
  });
}

async function targets() { return (await fetch(debugURL + '/json/list')).json(); }
async function pageCall(pageURL) {
  const target = await until(async () => (await targets()).find(t => t.type === 'page' && t.url === pageURL), pageURL);
  return connect(target.webSocketDebuggerUrl);
}
async function evaluate(send, expression) {
  const result = await send('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true, userGesture: true});
  assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
async function command(value) {
  await writeFile(control, value);
  await until(async () => { try { await readFile(control); return false; } catch (error) { if (error.code === 'ENOENT') return true; throw error; } }, 'native command consumed');
}
async function start() {
  const socket = createSocketServer(); socket.listen(0, '127.0.0.1'); await once(socket, 'listening');
  const port = socket.address().port; await new Promise(resolve => socket.close(resolve));
  debugURL = `http://127.0.0.1:${port}`;
  await unlink(control + '.pid').catch(error => { if (error.code !== 'ENOENT') throw error; });
  const args = ['-n', '-W', app, '--args', url, profile, control, fixture, `--remote-debugging-port=${port}`];
  launcher = spawn('open', args, {stdio: 'ignore'});
  await until(async () => {
    try { pid = Number(await readFile(control + '.pid', 'utf8')); await targets(); return true; }
    catch { return false; }
  }, 'desktop runtime ready');
  return pageCall(url);
}
async function stop() {
  sockets.forEach(socket => socket.close()); sockets = [];
  await command('quit');
  await until(() => launcher.exitCode !== null, 'normal desktop app termination');
  assert.equal(launcher.exitCode, 0); launcher = null; pid = null;
}
async function proof(send, minimumVisits = 1) {
  return until(async () => {
    const state = await evaluate(send, `(() => {
      const state = JSON.parse(document.documentElement.dataset.extensionProof || 'null');
      const marker = document.getElementById('talaria-extension-proof');
      return marker?.textContent === 'Extension active — visit ' + state?.visits && marker.getBoundingClientRect().height > 0 ? state : null;
    })()`);
    return state?.visits >= minimumVisits ? state : null;
  }, 'visible page marker and worker/storage response');
}
async function snapshot() {
  await command('snapshot');
  return JSON.parse(await readFile(control + '.snapshot', 'utf8'));
}

try {
  let page = await start();
  await command('fixture-installer');
  const installer = await pageCall('chrome://extensions/?talaria-fixture');
  await evaluate(installer, 'chrome.developerPrivate.updateProfileConfiguration({inDeveloperMode:true})');
  await evaluate(installer, 'chrome.developerPrivate.loadUnpacked({failQuietly:true})');
  console.log('Fixture installed through Chromium.');
  const extensions = await evaluate(installer, 'chrome.developerPrivate.getExtensionsInfo({includeDisabled:true,includeTerminated:true})');
  const {id} = extensions.find(extension => extension.name === 'Talaria Page Marker') || {};
  assert.ok(id, 'The normal unpacked installer registers the fixture');
  await command('close-fixture-installer');
  await until(async () => !(await targets()).some(target => target.url.includes('talaria-fixture')), 'fixture installer closes');
  await page('Page.reload'); const first = await proof(page);
  assert.equal(first.token, first.contentToken);
  assert.ok(first.visits > 0);
  let native = await snapshot();
  assert.ok(native.embedded && native.visible && native.alloy && native.width > 100 && native.height > 100, JSON.stringify(native));
  await command('manager');
  let manager = await pageCall('chrome://extensions/');
  const installed = await evaluate(manager, 'chrome.developerPrivate.getExtensionsInfo({includeDisabled:true,includeTerminated:true})');
  assert.ok(installed.some(extension => extension.id === id && extension.state === 'ENABLED'));
  await command('manager'); // Reopening must reuse the utility window.
  assert.equal((await targets()).filter(target => target.url === 'chrome://extensions/').length, 1);
  await command('close-manager');
  await until(async () => !(await targets()).some(target => target.url === 'chrome://extensions/'), 'manager closes');
  await page('Page.reload'); const beforeRestart = await proof(page, first.visits + 1);
  assert.equal(beforeRestart.token, first.token);
  assert.ok(beforeRestart.previousVisits >= first.visits);
  await stop();
  console.log('First run shut down normally; restarting.');

  page = await start(); // No extension manager, --load-extension, or installation call.
  const restored = await proof(page);
  console.log('Restored extension and storage.');
  assert.equal(restored.token, beforeRestart.token);
  assert.equal(restored.contentToken, beforeRestart.token);
  assert.equal(restored.previousSync, beforeRestart.token);
  assert.ok(restored.previousVisits >= beforeRestart.visits);
  native = await snapshot(); assert.ok(native.embedded && native.visible && native.alloy);
  const screenshot = await page('Page.captureScreenshot', {format: 'png'});
  await writeFile(path.join(root, 'build/extension-restart-page.png'), Buffer.from(screenshot.data, 'base64'));

  await command('manager'); manager = await pageCall('chrome://extensions/');
  await evaluate(manager, `chrome.management.setEnabled(${JSON.stringify(id)}, false)`);
  await page('Page.reload');
  await until(() => evaluate(page, `document.readyState === 'complete'`), 'reload after disabling');
  await delay(1000);
  assert.equal(await evaluate(page, `document.getElementById('talaria-extension-proof') !== null`), false);
  await evaluate(manager, `chrome.management.setEnabled(${JSON.stringify(id)}, true)`);
  await page('Page.reload'); const enabled = await proof(page);
  assert.equal(enabled.token, first.token);
  await stop();
  await writeFile(path.join(root, 'build/browser-extensions-results.json'), JSON.stringify({first, beforeRestart, restored, enabled, native, management: 'disable and enable passed'}, null, 2));
  console.log('PASS: embedded content scripts, worker messaging, local/sync storage, restart persistence, manager reuse, disable/enable and shutdown.');
} finally {
  sockets.forEach(socket => socket.close());
  if (launcher && launcher.exitCode === null) {
    await writeFile(control, 'quit').catch(() => {}); await delay(2000);
    if (launcher.exitCode === null && pid) { try { process.kill(pid, 'SIGTERM'); } catch {} }
    launcher.kill();
  }
  server.closeAllConnections(); server.close();
}
