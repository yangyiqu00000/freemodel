#!/usr/bin/env node
const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

function fail(message) {
  console.error(`throttling-check-fail: ${message}`);
  process.exit(1);
}

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function requestJSON(options, body) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ statusCode: res.statusCode, headers: res.headers, body: data }));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

(async () => {
  const requestHistory = [];

  const upstream = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/chat/completions') {
      res.writeHead(404);
      res.end('not found');
      return;
    }

    const requestTime = Date.now();
    requestHistory.push({ type: 'start', time: requestTime });

    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      // Delay response by 800ms to test concurrency queueing
      setTimeout(() => {
        requestHistory.push({ type: 'end', time: Date.now() });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          choices: [{ message: { content: 'hello from upstream' } }],
          usage: { prompt_tokens: 5, completion_tokens: 5, total_tokens: 10 }
        }));
      }, 800);
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
      PROXY_MIN_INTERVAL_MS: '2000' // 2 seconds minimum interval
    },
    stdio: ['ignore', 'pipe', 'pipe']
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

    console.log('Sending concurrent requests...');
    const tStart = Date.now();

    // Send two requests concurrently
    const p1 = requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ model: 'codex-mini', input: 'Hello A' }));

    // Send B 100ms later to guarantee order
    await new Promise(r => setTimeout(r, 100));

    const p2 = requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({ model: 'codex-mini', input: 'Hello B' }));

    const [r1, r2] = await Promise.all([p1, p2]);
    const tEnd = Date.now();

    console.log(`Total test execution time: ${tEnd - tStart}ms`);
    console.log('Request history in upstream:', JSON.stringify(requestHistory));

    if (r1.statusCode !== 200 || r2.statusCode !== 200) {
      fail(`Expected 200 for both requests, got: R1=${r1.statusCode}, R2=${r2.statusCode}`);
    }

    if (requestHistory.length !== 4) {
      fail(`Expected 4 history entries in upstream, got ${requestHistory.length}`);
    }

    const tA_start = requestHistory[0].time;
    const tB_start = requestHistory[2].time;

    const intervalBetweenStarts = tB_start - tA_start;
    console.log(`Interval between request starts: ${intervalBetweenStarts}ms`);

    // Verify minimum request interval of 2000ms was respected
    if (intervalBetweenStarts < 1950) {
      fail(`Throttling failed: B started ${intervalBetweenStarts}ms after A (expected >= 2000ms)`);
    }

    console.log('throttling-check-pass');
  } catch (error) {
    fail(`${error.message}${stderr ? `\n${stderr}` : ''}`);
  } finally {
    child.kill();
    upstream.close();
  }
})();
