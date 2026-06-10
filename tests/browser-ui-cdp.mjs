#!/usr/bin/env node
// browser-ui-cdp.mjs - drive Chrome UI smoke checks through DevTools Protocol.
//
// Why this exists:
// - runs inside a Dev Containers CLI-started workspace container
// - proves Chrome can render container-local content without a desktop stack
// - captures a screenshot and compares browser-exposed accessibility text
//
// Inputs:
// - --url: file:// or http(s):// URL to open in Chrome
// - --expected: text expected in the rendered accessibility tree
// - --screenshot: path where a PNG screenshot should be written
//
// Related files:
// - tests/browser-smoke.sh
// - Dockerfile

import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const args = parseArgs(process.argv.slice(2));

for (const name of ['url', 'expected', 'screenshot']) {
  if (!args[name]) {
    throw new Error(`missing required --${name} argument`);
  }
}

const port = await reservePort();
const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'chrome-ui-cdp.'));
let chrome;

try {
  chrome = spawn('chrome', [
    '--headless',
    `--user-data-dir=${userDataDir}`,
    `--remote-debugging-port=${port}`,
    'about:blank',
  ], {
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const page = await waitForPage(port);
  const cdp = await connectCdp(page.webSocketDebuggerUrl);

  try {
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Accessibility.enable');
    await cdp.send('Page.navigate', { url: args.url });
    await waitForReadyState(cdp);

    const screenshot = await cdp.send('Page.captureScreenshot', {
      format: 'png',
      captureBeyondViewport: true,
    });
    await writeFile(args.screenshot, screenshot.data, 'base64');

    const tree = await cdp.send('Accessibility.getFullAXTree');
    const renderedText = collectAccessibleText(tree.nodes ?? []);

    if (!renderedText.includes(args.expected)) {
      console.error(`Expected rendered text: ${args.expected}`);
      console.error(`Actual rendered text:   ${renderedText}`);
      process.exitCode = 1;
    }
  } finally {
    await cdp.close();
  }
} finally {
  if (chrome) {
    chrome.kill('SIGTERM');
    await waitForExit(chrome);
  }
  await rm(userDataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}

function parseArgs(rawArgs) {
  const parsed = {};

  for (let i = 0; i < rawArgs.length; i += 1) {
    const arg = rawArgs[i];
    if (!arg.startsWith('--')) {
      throw new Error(`unexpected positional argument: ${arg}`);
    }

    const key = arg.slice(2);
    const value = rawArgs[i + 1];
    if (!value || value.startsWith('--')) {
      throw new Error(`missing value for ${arg}`);
    }

    parsed[key] = value;
    i += 1;
  }

  return parsed;
}

async function reservePort() {
  const server = http.createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });

  const { port } = server.address();
  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });

  return port;
}

async function waitForPage(port) {
  const deadline = Date.now() + 15_000;
  let lastError;

  while (Date.now() < deadline) {
    try {
      const pages = await getJson(`http://127.0.0.1:${port}/json/list`);
      const page = pages.find((entry) => entry.type === 'page' && entry.webSocketDebuggerUrl);
      if (page) {
        return page;
      }
    } catch (error) {
      lastError = error;
    }

    await delay(100);
  }

  throw new Error(`Chrome DevTools page was not ready: ${lastError?.message ?? 'timed out'}`);
}

async function getJson(url) {
  const body = await new Promise((resolve, reject) => {
    const request = http.get(url, (response) => {
      let data = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        data += chunk;
      });
      response.on('end', () => {
        if (response.statusCode !== 200) {
          reject(new Error(`HTTP ${response.statusCode} from ${url}`));
          return;
        }
        resolve(data);
      });
    });

    request.once('error', reject);
  });

  return JSON.parse(body);
}

async function connectCdp(webSocketUrl) {
  const socket = new WebSocket(webSocketUrl);
  const pending = new Map();
  let nextId = 1;

  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (!message.id || !pending.has(message.id)) {
      return;
    }

    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);

    if (message.error) {
      reject(new Error(`${message.error.message}: ${message.error.data ?? ''}`.trim()));
      return;
    }

    resolve(message.result ?? {});
  });

  socket.addEventListener('close', () => {
    for (const { reject } of pending.values()) {
      reject(new Error('Chrome DevTools Protocol socket closed'));
    }
    pending.clear();
  });

  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });

  return {
    send(method, params = {}) {
      const id = nextId;
      nextId += 1;
      socket.send(JSON.stringify({ id, method, params }));
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
      });
    },
    close() {
      socket.close();
      return delay(50);
    },
  };
}

async function waitForReadyState(cdp) {
  const deadline = Date.now() + 15_000;

  while (Date.now() < deadline) {
    const result = await cdp.send('Runtime.evaluate', {
      expression: 'document.readyState',
      returnByValue: true,
    });

    if (result.result?.value === 'complete') {
      return;
    }

    await delay(100);
  }

  throw new Error('page did not reach document.readyState === "complete"');
}

function collectAccessibleText(nodes) {
  const values = [];

  for (const node of nodes) {
    const value = node.name?.value;
    if (typeof value === 'string' && value.trim()) {
      values.push(value.trim());
    }
  }

  return values.join('\n');
}

async function waitForExit(child) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return;
  }

  await Promise.race([
    new Promise((resolve) => child.once('exit', resolve)),
    delay(2_000).then(() => child.kill('SIGKILL')),
  ]);
}
