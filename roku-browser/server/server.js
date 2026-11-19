'use strict';
// TV Browser server: runs a real Chromium browser (headless) on your PC and
// lets the Roku channel drive it. The Roku shows screenshots from /frame.jpg
// and sends remote-control actions to /cmd.

const http = require('http');
const os = require('os');
const { chromium } = require('playwright');

const PORT = Number(process.env.PORT) || 8080;
const HOME_URL = process.env.HOME_URL || 'https://duckduckgo.com/';
const SEARCH_URL = 'https://duckduckgo.com/?q=';
// The Roku screen is 1280x720. Zoom > 1 renders a smaller viewport that the
// TV scales up, which makes text bigger and easier to read from the couch.
const OUT_W = 1280;
const OUT_H = 720;
const MIN_ZOOM = 1;
const MAX_ZOOM = 2.5;
let zoom = clampZoom(Number(process.env.ZOOM) || 1.25);

const ALLOWED_KEYS = new Set([
  'Enter', 'Backspace', 'Tab', 'Escape', 'Space', 'Delete',
  'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown', 'Home', 'End',
]);
const NON_TEXT_INPUTS = ['button', 'submit', 'checkbox', 'radio', 'range', 'color', 'file', 'image', 'reset', 'hidden'];

let context;
let pages = [];
let page;
let lastFrame = null;

function clampZoom(z) {
  return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, Math.round(z * 100) / 100));
}

function viewport() {
  return { width: Math.round(OUT_W / zoom), height: Math.round(OUT_H / zoom) };
}

function trackPage(p) {
  if (pages.includes(p)) return;
  pages.push(p);
  page = p; // pop-ups and new tabs become the visible page
  p.setViewportSize(viewport()).catch(() => {});
  p.on('close', () => {
    pages = pages.filter((x) => x !== p);
    if (page === p) page = pages[pages.length - 1];
  });
}

async function ensurePage() {
  if (!page || page.isClosed()) {
    const p = await context.newPage();
    trackPage(p);
    await goto(HOME_URL);
  }
}

// Turns what the user typed into a URL. Words become a search; only
// http(s) is allowed so nobody on the network can open file:// on your PC.
function normalizeUrl(input) {
  const s = String(input || '').trim();
  if (!s) return HOME_URL;
  if (/^https?:\/\//i.test(s)) return s;
  if (/^[a-z][a-z0-9+.-]*:/i.test(s) && !/^[^\s/:]+:\d+/.test(s)) return SEARCH_URL + encodeURIComponent(s);
  if (/^(localhost|\d+\.\d+\.\d+\.\d+)(:\d+)?(\/.*)?$/i.test(s)) return 'http://' + s; // devices on your network
  if (!/\s/.test(s) && /^[^\s/]+\.[a-z]{2,}(:\d+)?(\/.*)?$/i.test(s)) return 'https://' + s;
  return SEARCH_URL + encodeURIComponent(s);
}

async function goto(url) {
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
    return null;
  } catch (e) {
    return 'Could not load page: ' + String(e.message || e).split('\n')[0];
  }
}

// Gives the page a moment to react to a click or key press.
async function settle(ms = 400) {
  await page.waitForTimeout(ms).catch(() => {});
  await page.waitForLoadState('domcontentloaded', { timeout: 5000 }).catch(() => {});
}

async function state() {
  const p = page;
  let focus = { editable: false, value: '', password: false };
  try {
    focus = await p.evaluate((nonText) => {
      const el = document.activeElement;
      if (!el) return { editable: false, value: '', password: false };
      const tag = el.tagName;
      const type = (el.type || '').toLowerCase();
      const editable = el.isContentEditable || tag === 'TEXTAREA' || (tag === 'INPUT' && !nonText.includes(type));
      const value = editable ? String(el.value != null ? el.value : el.innerText || '') : '';
      return { editable, value: value.slice(0, 500), password: type === 'password' };
    }, NON_TEXT_INPUTS);
  } catch (_) { /* page is navigating */ }
  let title = '';
  try { title = await p.title(); } catch (_) { /* ignore */ }
  return { url: p.url(), title, zoom, tabs: pages.length, ...focus };
}

async function run(q) {
  await ensurePage();
  const action = q.get('a') || 'state';
  const num = (k) => Number(q.get(k)) || 0;
  const extra = {};

  switch (action) {
    case 'state':
      break;
    case 'nav': {
      const err = await goto(normalizeUrl(q.get('url')));
      if (err) extra.error = err;
      break;
    }
    case 'click':
      await page.mouse.click(num('x') / zoom, num('y') / zoom);
      await settle();
      break;
    case 'scroll':
      await page.mouse.move(num('x') / zoom, num('y') / zoom);
      await page.mouse.wheel(0, num('dy') / zoom);
      await page.waitForTimeout(250);
      break;
    case 'fill': {
      // Replaces the text in the focused field, optionally pressing Enter.
      await page.keyboard.press('ControlOrMeta+A');
      await page.keyboard.press('Backspace');
      await page.keyboard.type(q.get('text') || '', { delay: 5 });
      if (q.get('enter') === '1') {
        await page.keyboard.press('Enter');
        await settle(800);
      }
      break;
    }
    case 'key': {
      const key = q.get('key');
      if (ALLOWED_KEYS.has(key)) {
        await page.keyboard.press(key);
        await settle(300);
      }
      break;
    }
    case 'back': {
      const before = page.url();
      await page.goBack({ waitUntil: 'domcontentloaded', timeout: 10000 }).catch(() => {});
      let wentBack = page.url() !== before;
      if (wentBack && page.url() === 'about:blank') {
        // Don't fall back to the empty tab the browser started with.
        await page.goForward({ waitUntil: 'domcontentloaded', timeout: 10000 }).catch(() => {});
        wentBack = false;
      }
      if (!wentBack && pages.length > 1) {
        await page.close(); // close a pop-up tab and return to the one under it
        wentBack = true;
      }
      extra.wentBack = wentBack;
      break;
    }
    case 'forward':
      await page.goForward({ waitUntil: 'domcontentloaded', timeout: 10000 }).catch(() => {});
      break;
    case 'reload':
      await page.reload({ waitUntil: 'domcontentloaded', timeout: 20000 }).catch(() => {});
      break;
    case 'home': {
      const err = await goto(HOME_URL);
      if (err) extra.error = err;
      break;
    }
    case 'zoom':
      zoom = clampZoom(zoom + (Number(q.get('step')) || 0));
      await Promise.all(pages.map((p) => p.setViewportSize(viewport()).catch(() => {})));
      await page.waitForTimeout(300);
      break;
    default:
      extra.error = 'Unknown action: ' + action;
  }
  return { ...(await state()), ...extra };
}

async function frame() {
  await ensurePage();
  try {
    lastFrame = await page.screenshot({ type: 'jpeg', quality: 75, timeout: 5000 });
  } catch (_) {
    if (!lastFrame) throw new Error('No frame available yet');
  }
  return lastFrame;
}

// Runs commands one at a time so clicks and typing happen in order.
let chain = Promise.resolve();
function enqueue(fn) {
  const result = chain.then(fn);
  chain = result.catch(() => {});
  return result;
}

function sendJson(res, status, body) {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': data.length, 'Cache-Control': 'no-store' });
  res.end(data);
}

const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://localhost');
  try {
    if (u.pathname === '/frame.jpg') {
      const buf = await frame();
      res.writeHead(200, { 'Content-Type': 'image/jpeg', 'Content-Length': buf.length, 'Cache-Control': 'no-store' });
      res.end(buf);
    } else if (u.pathname === '/cmd') {
      sendJson(res, 200, await enqueue(() => run(u.searchParams)));
    } else if (u.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('TV Browser server is running. Enter this address in the Roku channel.\n');
    } else {
      sendJson(res, 404, { error: 'Not found' });
    }
  } catch (e) {
    sendJson(res, 500, { error: String(e.message || e) });
  }
});

function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list || []) {
      if (a.family === 'IPv4' && !a.internal) out.push(a.address);
    }
  }
  return out;
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  context = await browser.newContext({ viewport: viewport() });
  context.on('page', trackPage);
  trackPage(await context.newPage());
  await goto(HOME_URL);

  server.listen(PORT, '0.0.0.0', () => {
    console.log('TV Browser server is running.');
    const ips = lanAddresses();
    if (ips.length) {
      console.log('On your Roku, enter this server address:');
      for (const ip of ips) console.log(`   ${ip}:${PORT}`);
    }
    console.log('Press Ctrl+C to stop.');
  });

  const shutdown = async () => {
    server.close();
    await browser.close().catch(() => {});
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { normalizeUrl };
