#!/usr/bin/env node
const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

function fail(message) {
  console.error(`queued-abort-check-fail: ${message}`);
  process.exit(1);
}

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

(async () => {
  let upstreamHits = 0;

  const upstream = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/chat/completions') {
      res.writeHead(404);
      res.end('not found');
      return;
    }

    upstreamHits += 1;
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      // Delay response by 1500ms to allow time to abort the queued request
      setTimeout(() => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          choices: [{ message: { content: 'hello from upstream' } }],
          usage: { prompt_tokens: 5, completion_tokens: 5, total_tokens: 10 }
        }));
      }, 1500);
    });
  });

  const upstreamPort = await listen(upstream);
  const proxy = http.createServer();
  const proxyPort = await listen(proxy);
  proxy.close();

  const sidecarPath = path.join(process.cwd(), 'FreeModelMenuBar', 'FreeModelMenuBar', 'router_sidecar.js');
  const child = spawn(process.execPath, [sidecarPath], {
    env: {
      ...process.env,
      PORT: String(proxyPort),
      UPSTREAM_BASE_URL: `http://127.0.0.1:${upstreamPort}/chat/completions`,
      UPSTREAM_API_KEY: 'test-key',
      UPSTREAM_MODEL: 'fake-upstream',
      ROUTE_MODEL: 'codex-mini',
      PROXY_MAX_CONCURRENCY: '1',
      PROXY_MIN_INTERVAL_MS: '0'
    },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  let childStdout = '';
  child.stdout.on('data', (chunk) => {
    childStdout += chunk.toString();
  });

  let stderr = '';
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });

  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('sidecar did not start')), 3000);
      child.stdout.on('data', (chunk) => {
        if (chunk.toString().includes('Server listening')) {
          clearTimeout(timeout);
          resolve();
        }
      });
    });

    console.log('Sending Request A...');
    const reqA = http.request({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });
    reqA.on('error', () => {}); // Prevent crash
    reqA.write(JSON.stringify({ model: 'codex-mini', input: 'Hello A' }));
    reqA.end();

    // Wait 100ms
    await new Promise(r => setTimeout(r, 100));

    console.log('Sending Request B...');
    const reqB = http.request({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });
    reqB.on('error', () => {}); // Prevent crash
    reqB.write(JSON.stringify({ model: 'codex-mini', input: 'Hello B' }));
    reqB.end();

    // Wait 200ms and then abort Request B while it is queued
    await new Promise(r => setTimeout(r, 200));
    console.log('Aborting Request B...');
    reqB.destroy();

    // Wait 2000ms for Request A to finish
    await new Promise(r => setTimeout(r, 2000));

    console.log(`Upstream hits: ${upstreamHits}`);
    console.log(`Proxy output logs:\n${childStdout}`);

    // Verify upstream only received Request A (upstreamHits = 1)
    if (upstreamHits !== 1) {
      fail(`Upstream received ${upstreamHits} requests, but expected only 1 (Request B should be aborted before forwarding)`);
    }

    // Verify 499 log was printed
    if (!childStdout.includes('"status":499')) {
      fail('Expected proxy logs to contain a 499 Client Closed Request status code');
    }

    console.log('queued-abort-check-pass');
  } catch (error) {
    fail(`${error.message}${stderr ? `\n${stderr}` : ''}`);
  } finally {
    child.kill();
    upstream.close();
  }
})();
