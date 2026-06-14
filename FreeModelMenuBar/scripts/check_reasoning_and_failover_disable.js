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
  console.log("=== Starting Reasoning Content and Failover Disable Verification ===");

  // 1. Set up Mock Upstream 1
  let upstream1Hits = 0;
  let lastUpstream1Payload = null;
  const mockUpstream1 = http.createServer((req, res) => {
    upstream1Hits++;
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      if (req.url.includes('/chat/completions')) {
        const payload = JSON.parse(body);
        lastUpstream1Payload = payload;
        
        // If it's a test for reasoning content:
        if (payload.messages && payload.messages.some(m => m.content === "trigger_reasoning")) {
          console.log(`[MockUpstream1] Turn 1: Returning message with reasoning_content`);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            choices: [{
              message: {
                role: "assistant",
                content: "final response content",
                reasoning_content: "my detailed thinking process"
              }
            }],
            usage: { prompt_tokens: 10, completion_tokens: 15, total_tokens: 25 }
          }));
          return;
        }

        if (payload.messages && payload.messages.some(m => m.content === "trigger_turn_2")) {
          // Check if previous assistant message in history contains reasoning_content
          const assistantMsg = payload.messages.find(m => m.role === "assistant");
          if (assistantMsg && assistantMsg.reasoning_content === "my detailed thinking process") {
            console.log(`[MockUpstream1] Turn 2: Success! reasoning_content was restored: ${assistantMsg.reasoning_content}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
              choices: [{
                message: { role: "assistant", content: "turn 2 response" }
              }]
            }));
          } else {
            console.log(`[MockUpstream1] Turn 2: Error! assistant message had reasoning_content = ${assistantMsg ? assistantMsg.reasoning_content : 'null'}`);
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: { message: "The reasoning_content in the thinking mode must be passed back to the API." } }));
          }
          return;
        }

        if (payload.messages && payload.messages.some(m => m.content === "trigger_inline_think")) {
          console.log(`[MockUpstream1] Turn 4: Returning message with inline <think> tags in content`);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            choices: [{
              message: {
                role: "assistant",
                content: "<think>my inline think block</think>\nactual message"
              }
            }]
          }));
          return;
        }
      }

      console.log(`[MockUpstream1] Replying with 429 Too Many Requests`);
      res.writeHead(429, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: "Rate limit exceeded on upstream 1" } }));
    });
  });

  // 2. Set up Mock Upstream 2 (backup)
  let upstream2Hits = 0;
  const mockUpstream2 = http.createServer((req, res) => {
    upstream2Hits++;
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      console.log(`[MockUpstream2] Replying with 200 OK`);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        choices: [{
          message: { role: "assistant", content: "hello from backup" }
        }],
        usage: { prompt_tokens: 5, completion_tokens: 4, total_tokens: 9 }
      }));
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
      ROUTE_MODEL: 'codex-mini',
      PROXY_FAILOVER_ENABLED: 'true' // initially enabled
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
    // Test 1: failoverEnabled = false
    console.log("\n--- Test 1: Configuration failoverEnabled = false ---");
    const configUpdate1 = {
      type: "update_config",
      activeAccount: {
        providerID: "primary-unhealthy",
        url: `http://127.0.0.1:${port1}`,
        key: "primary-key",
        model: "deepseek-chat"
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
      failoverEnabled: false
    };
    child.stdin.write(JSON.stringify(configUpdate1) + "\n");
    await new Promise(resolve => setTimeout(resolve, 300));

    // Request should fail with 429 without failover
    upstream1Hits = 0;
    upstream2Hits = 0;
    const response1 = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: 'hello test 1',
      stream: false
    }));

    console.log(`[Client] Test 1 status: ${response1.statusCode}`);
    if (response1.statusCode !== 429) {
      fail(`Expected 429, got ${response1.statusCode}`);
    }
    if (upstream1Hits !== 1 || upstream2Hits !== 0) {
      fail(`Expected 1 hit on upstream 1 and 0 on upstream 2. Got: 1=${upstream1Hits}, 2=${upstream2Hits}`);
    }
    console.log("✅ Test 1: Disable failover successfully prevents fallback routing.");

    // Test 2: failoverEnabled = true
    console.log("\n--- Test 2: Configuration failoverEnabled = true ---");
    const configUpdate2 = {
      ...configUpdate1,
      failoverEnabled: true
    };
    child.stdin.write(JSON.stringify(configUpdate2) + "\n");
    await new Promise(resolve => setTimeout(resolve, 300));

    // Request should failover to upstream 2 and return 200
    upstream1Hits = 0;
    upstream2Hits = 0;
    const response2 = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: 'hello test 2',
      stream: false
    }));

    console.log(`[Client] Test 2 status: ${response2.statusCode}`);
    if (response2.statusCode !== 200) {
      fail(`Expected 200, got ${response2.statusCode}`);
    }
    if (upstream1Hits !== 1 || upstream2Hits !== 1) {
      fail(`Expected 1 hit on upstream 1 and 1 on upstream 2. Got: 1=${upstream1Hits}, 2=${upstream2Hits}`);
    }
    console.log("✅ Test 2: Enable failover successfully enables fallback routing.");

    // Test 3: Reasoning Content cache and restore
    console.log("\n--- Test 3: Reasoning Content Restoration ---");
    // Ensure upstream 1 returns success for the reasoning content request (so we don't trigger failover, or we configure upstream 1 to succeed)
    upstream1Hits = 0;
    upstream2Hits = 0;

    // Turn 1 request
    console.log("[Client] Sending Turn 1 Request to proxy...");
    const responseTurn1 = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: 'trigger_reasoning',
      stream: false
    }));

    if (responseTurn1.statusCode !== 200) {
      fail(`Turn 1 failed with status ${responseTurn1.statusCode}: ${responseTurn1.body}`);
    }
    const turn1Body = JSON.parse(responseTurn1.body);
    const assistantMsgId = turn1Body.output[0].id;
    console.log(`[Client] Turn 1 complete. Generated message ID: ${assistantMsgId}`);

    // Turn 2 request - pass the turn 1 response in input history
    console.log("[Client] Sending Turn 2 Request, including Turn 1 in input history...");
    const responseTurn2 = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: [
        { role: 'user', content: 'trigger_reasoning' },
        { id: assistantMsgId, role: 'assistant', content: 'final response content' },
        { role: 'user', content: 'trigger_turn_2' }
      ],
      stream: false
    }));

    console.log(`[Client] Turn 2 response status: ${responseTurn2.statusCode}`);
    if (responseTurn2.statusCode !== 200) {
      fail(`Turn 2 failed with status ${responseTurn2.statusCode}: ${responseTurn2.body}`);
    }
    console.log("✅ Test 3: Reasoning content successfully cached and restored across turns.");

    // Test 4: Inline <think> tag extraction and stripping
    console.log("\n--- Test 4: Inline <think> Tag Extraction and Stripping ---");
    const responseTurn4 = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: 'trigger_inline_think',
      stream: false
    }));

    if (responseTurn4.statusCode !== 200) {
      fail(`Test 4 failed with status ${responseTurn4.statusCode}`);
    }
    const turn4Body = JSON.parse(responseTurn4.body);
    const textOutput = turn4Body.output_text;
    console.log(`[Client] Test 4 output text: "${textOutput}"`);
    if (textOutput.includes("<think>")) {
      fail("Expected output text to strip <think> tag");
    }
    if (textOutput.trim() !== "actual message") {
      fail(`Expected output text to be "actual message", got "${textOutput}"`);
    }
    console.log("✅ Test 4: Inline <think> tags successfully extracted and stripped from client response.");

    console.log("\n🎉 All reasoning content and failover disable tests PASSED!");
  } catch (err) {
    fail(`${err.message}${stderr ? `\nStderr output:\n${stderr}` : ''}`);
  } finally {
    child.kill();
    mockUpstream1.close();
    mockUpstream2.close();
  }
})();
