#!/usr/bin/env node
const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

function fail(message) {
  console.error(`router-stream-check-fail: ${message}`);
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

function parseSSE(body) {
  return body
    .split('\n\n')
    .map((block) => block.trim())
    .filter(Boolean)
    .map((block) => {
      const eventLine = block.split('\n').find((line) => line.startsWith('event: '));
      const dataLine = block.split('\n').find((line) => line.startsWith('data: '));
      if (!eventLine || !dataLine) {
        fail(`malformed SSE block: ${block}`);
      }
      return {
        event: eventLine.slice('event: '.length),
        data: JSON.parse(dataLine.slice('data: '.length))
      };
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

    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      upstreamHits += 1;
      const payload = JSON.parse(body);
      if (payload.model !== 'fake-upstream') {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'wrong model' } }));
        return;
      }

      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache'
      });
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'hel' } }], usage: null })}\n\n`);
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'lo' } }], usage: null })}\n\n`);
      res.write(`data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 } })}\n\n`);
      res.write('data: [DONE]\n\n');
      res.end();
    });
  });

  const upstreamPort = await listen(upstream);
  const proxy = http.createServer();
  const proxyPort = await listen(proxy);
  proxy.close();

  const sidecarPath = path.join(process.cwd(), 'FreeModelMenuBar', 'router_sidecar.js');
  const child = spawn(process.execPath, [sidecarPath], {
    env: {
      ...process.env,
      PORT: String(proxyPort),
      UPSTREAM_BASE_URL: `http://127.0.0.1:${upstreamPort}`,
      UPSTREAM_API_KEY: 'test-key',
      UPSTREAM_MODEL: 'fake-upstream',
      ROUTE_MODEL: 'codex-mini'
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

    const response = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: 'hello',
      stream: true
    }));

    if (response.statusCode !== 200) {
      fail(`expected 200, got ${response.statusCode}: ${response.body}`);
    }
    if (!String(response.headers['content-type'] || '').includes('text/event-stream')) {
      fail('expected text/event-stream content type');
    }
    if (upstreamHits !== 1) {
      fail(`expected one upstream hit, got ${upstreamHits}`);
    }

    const events = parseSSE(response.body);
    const byEvent = new Map(events.map((item) => [item.event, item.data]));
    for (const { event, data } of events) {
      if (data.type !== event) {
        fail(`event ${event} data.type mismatch: ${JSON.stringify(data)}`);
      }
      if (typeof data.sequence_number !== 'number') {
        fail(`event ${event} missing numeric sequence_number`);
      }
    }

    const created = byEvent.get('response.created');
    if (!created || created.response?.object !== 'response' || created.response?.created_at === undefined) {
      fail('response.created should wrap a response object with created_at');
    }

    const delta = byEvent.get('response.output_text.delta');
    if (!delta || delta.delta !== 'lo') {
      fail('expected final output_text delta to be present');
    }

    const completed = byEvent.get('response.completed');
    if (!completed || completed.response?.status !== 'completed') {
      fail('response.completed should wrap a completed response');
    }
    if (completed.response.output_text !== 'hello') {
      fail(`expected output_text hello, got ${completed.response.output_text}`);
    }
    if (completed.response.usage?.input_tokens !== 3 ||
        completed.response.usage?.output_tokens !== 2 ||
        completed.response.usage?.total_tokens !== 5) {
      fail(`unexpected Responses usage shape: ${JSON.stringify(completed.response.usage)}`);
    }

    console.log('router-stream-check-pass');
  } catch (error) {
    fail(`${error.message}${stderr ? `\n${stderr}` : ''}`);
  } finally {
    child.kill();
    upstream.close();
  }
})();
