#!/usr/bin/env node
const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

function fail(message) {
  console.error(`check-fail: ${message}`);
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
  console.log("=== Starting Hot Reload and Failover Verification ===");

  // 1. Set up Mock Upstream 1 (will return 429 or 503 to trigger failover)
  let upstream1Hits = 0;
  const mockUpstream1 = http.createServer((req, res) => {
    upstream1Hits++;
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      console.log(`[MockUpstream1] Received request. Replying with 429 Too Many Requests. Hits: ${upstream1Hits}`);
      res.writeHead(429, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: "Rate limit exceeded on upstream 1" } }));
    });
  });

  // 2. Set up Mock Upstream 2 (backup, will return 200 OK)
  let upstream2Hits = 0;
  let lastUpstream2Payload = null;
  const mockUpstream2 = http.createServer((req, res) => {
    upstream2Hits++;
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const payload = JSON.parse(body);
      lastUpstream2Payload = payload;
      const isStream = !!payload.stream;
      console.log(`[MockUpstream2] Received request. stream=${isStream}. Replying with 200 OK. Hits: ${upstream2Hits}`);
      
      if (isStream) {
        res.writeHead(200, {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache'
        });
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'hello from backup stream' } }], usage: null })}\n\n`);
        res.write(`data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 5, completion_tokens: 4, total_tokens: 9 } })}\n\n`);
        res.write('data: [DONE]\n\n');
        res.end();
      } else {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          choices: [{
            message: { role: "assistant", content: "hello from backup non-stream" }
          }],
          usage: { prompt_tokens: 5, completion_tokens: 4, total_tokens: 9 }
        }));
      }
    });
  });

  const port1 = await listen(mockUpstream1);
  const port2 = await listen(mockUpstream2);

  // Generate random proxy port
  const proxyDummy = http.createServer();
  const proxyPort = await listen(proxyDummy);
  proxyDummy.close();

  // 3. Spawn sidecar process
  const sidecarPath = path.join(__dirname, '..', 'FreeModelMenuBar', 'router_sidecar.js');
  console.log(`Spawning sidecar at ${sidecarPath} on port ${proxyPort}`);
  const child = spawn(process.execPath, [sidecarPath], {
    env: {
      ...process.env,
      PORT: String(proxyPort),
      UPSTREAM_BASE_URL: `http://127.0.0.1:${port1}`,
      UPSTREAM_API_KEY: 'temp-key',
      UPSTREAM_MODEL: 'initial-model',
      ROUTE_MODEL: 'codex-mini'
    },
    stdio: ['pipe', 'pipe', 'pipe']
  });

  let stderr = '';
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
  
  let sidecarLogs = [];
  child.stdout.on('data', (chunk) => {
    const lines = chunk.toString().split('\n');
    for (const l of lines) {
      if (l.trim()) {
        console.log(`[Sidecar Output] ${l.trim()}`);
        sidecarLogs.push(l.trim());
      }
    }
  });

  // Wait for sidecar to start
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('sidecar did not start in time')), 3000);
    const interval = setInterval(() => {
      if (sidecarLogs.some(log => log.includes('Server listening'))) {
        clearInterval(interval);
        clearTimeout(timeout);
        resolve();
      }
    }, 100);
  });

  try {
    // Test 1: Send configuration update over stdin (incorporating backup upstream)
    console.log("\n--- Sending update_config JSON over stdin ---");
    const configUpdate = {
      type: "update_config",
      activeAccount: {
        providerID: "primary-unhealthy",
        url: `http://127.0.0.1:${port1}`,
        key: "primary-key",
        model: "primary-model"
      },
      backups: [
        {
          providerID: "backup-healthy",
          url: `http://127.0.0.1:${port2}`,
          key: "backup-key",
          model: "backup-model"
        }
      ],
      routeModel: "codex-mini",
      maxConcurrency: 0,
      minIntervalMs: 0
    };
    child.stdin.write(JSON.stringify(configUpdate) + "\n");

    // Wait a brief moment to ensure hot reload parsed
    await new Promise(resolve => setTimeout(resolve, 500));

    // Test 2: Send non-streaming request.
    // Expected: mockUpstream1 hits once, returns 429. Failover kicks in. mockUpstream2 hits once, returns 200. Client gets 200.
    console.log("\n--- Testing Non-Streaming Failover ---");
    const responseNonStream = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: 'hello non-stream',
      stream: false
    }));

    console.log(`[Client] Non-stream response status: ${responseNonStream.statusCode}`);
    console.log(`[Client] Non-stream response body: ${responseNonStream.body}`);

    if (responseNonStream.statusCode !== 200) {
      fail(`Expected 200, got ${responseNonStream.statusCode}`);
    }
    const bodyObj = JSON.parse(responseNonStream.body);
    if (!bodyObj.output || bodyObj.output[0].content[0].text !== "hello from backup non-stream") {
      fail("Expected body output to contain backup assistant content");
    }
    if (upstream1Hits !== 1 || upstream2Hits !== 1) {
      fail(`Expected exactly 1 hit on upstream 1 and 1 hit on upstream 2, got upstream1=${upstream1Hits}, upstream2=${upstream2Hits}`);
    }
    if (lastUpstream2Payload.model !== "backup-model") {
      fail(`Expected failover model to be backup-model, got ${lastUpstream2Payload.model}`);
    }

    // Reset hits
    upstream1Hits = 0;
    upstream2Hits = 0;

    // Test 3: Send streaming request.
    // Expected: mockUpstream1 hits once, returns 429. Failover kicks in. mockUpstream2 hits once, streams successfully. Client gets 200.
    console.log("\n--- Testing Streaming Failover ---");
    const responseStream = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: 'hello stream',
      stream: true
    }));

    console.log(`[Client] Stream response status: ${responseStream.statusCode}`);
    console.log(`[Client] Stream response body chunk:\n${responseStream.body}`);

    if (responseStream.statusCode !== 200) {
      fail(`Expected 200, got ${responseStream.statusCode}`);
    }
    if (upstream1Hits !== 1 || upstream2Hits !== 1) {
      fail(`Expected exactly 1 hit on upstream 1 and 1 hit on upstream 2, got upstream1=${upstream1Hits}, upstream2=${upstream2Hits}`);
    }
    if (!responseStream.body.includes("hello from backup stream")) {
      fail("Expected stream response to contain backup stream text");
    }

    console.log("\n✅ All hot reload and automatic failover verification tests PASSED!");
  } catch (err) {
    fail(`${err.message}${stderr ? `\nStderr output:\n${stderr}` : ''}`);
  } finally {
    child.kill();
    mockUpstream1.close();
    mockUpstream2.close();
  }
})();
