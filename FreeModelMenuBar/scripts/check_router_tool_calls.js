#!/usr/bin/env node
const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

function fail(message) {
  console.error(`router-tool-call-check-fail: ${message}`);
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
  let upstreamPayload;
  let secondUpstreamPayload;
  let thirdUpstreamPayload;
  let fourthUpstreamPayload;
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
      if (upstreamHits === 1) {
        upstreamPayload = payload;
      } else if (upstreamHits === 2) {
        secondUpstreamPayload = payload;
      } else if (upstreamHits === 3) {
        thirdUpstreamPayload = payload;
      } else {
        fourthUpstreamPayload = payload;
      }
      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache'
      });
      if (upstreamHits === 1) {
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { reasoning_content: 'Need to open Chrome.' } }], usage: null })}\n\n`);
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { tool_calls: [{ index: 0, id: 'call_abc', type: 'function', function: { name: 'open_chrome', arguments: '' } }] } }], usage: null })}\n\n`);
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: '{\"url\":\"' } }] } }], usage: null })}\n\n`);
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: 'chrome\"}' } }] } }], usage: null })}\n\n`);
      } else {
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'done' } }], usage: null })}\n\n`);
      }
      res.write(`data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 4, completion_tokens: 3, total_tokens: 7 } })}\n\n`);
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
      UPSTREAM_BASE_URL: `http://127.0.0.1:${upstreamPort}/chat/completions`,
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
      input: 'open chrome',
      stream: true,
      tools: [
        {
          type: 'function',
          name: 'open_chrome',
          description: 'Open Chrome',
          parameters: {
            type: 'object',
            properties: {
              url: { type: 'string' }
            }
          }
        }
      ],
      tool_choice: 'auto'
    }));

    if (response.statusCode !== 200) {
      fail(`expected 200, got ${response.statusCode}: ${response.body}`);
    }
    if (!upstreamPayload?.tools?.[0]?.function || upstreamPayload.tools[0].function.name !== 'open_chrome') {
      fail(`Responses tools were not translated to Chat Completions tools: ${JSON.stringify(upstreamPayload?.tools)}`);
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

    const added = byEvent.get('response.output_item.added');
    if (added?.item?.type !== 'function_call' || added.item.name !== 'open_chrome') {
      fail(`expected function_call output item, got ${JSON.stringify(added)}`);
    }

    const argumentDone = byEvent.get('response.function_call_arguments.done');
    if (argumentDone?.arguments !== '{"url":"chrome"}') {
      fail(`expected complete function arguments, got ${JSON.stringify(argumentDone)}`);
    }

    const itemDone = byEvent.get('response.output_item.done');
    if (itemDone?.item?.status !== 'completed' || itemDone.item.arguments !== '{"url":"chrome"}') {
      fail(`expected completed function_call item, got ${JSON.stringify(itemDone)}`);
    }

    const completed = byEvent.get('response.completed');
    if (completed?.response?.output?.[0]?.type !== 'function_call') {
      fail(`expected completed response with function_call output, got ${JSON.stringify(completed)}`);
    }

    const followup = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: [
        {
          type: 'function_call',
          call_id: 'call_abc',
          name: 'open_chrome',
          arguments: '{"url":"chrome"}'
        },
        {
          type: 'function_call_output',
          call_id: 'call_abc',
          output: 'Chrome opened'
        }
      ],
      stream: true,
      tools: [
        {
          type: 'function',
          name: 'open_chrome',
          description: 'Open Chrome',
          parameters: { type: 'object', properties: {} }
        }
      ]
    }));

    if (followup.statusCode !== 200) {
      fail(`expected follow-up 200, got ${followup.statusCode}: ${followup.body}`);
    }
    const assistantToolMessage = secondUpstreamPayload?.messages?.find((message) => message.role === 'assistant' && message.tool_calls);
    if (assistantToolMessage?.reasoning_content !== 'Need to open Chrome.') {
      fail(`expected cached reasoning_content on follow-up assistant tool message, got ${JSON.stringify(assistantToolMessage)}`);
    }

    const reordered = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: [
        {
          type: 'function_call',
          call_id: 'call_abc',
          name: 'open_chrome',
          arguments: '{"url":"chrome"}'
        },
        {
          role: 'user',
          content: 'continue after restoring old messages'
        },
        {
          type: 'function_call_output',
          call_id: 'call_abc',
          output: 'Chrome opened'
        }
      ],
      stream: true,
      tools: [
        {
          type: 'function',
          name: 'open_chrome',
          description: 'Open Chrome',
          parameters: { type: 'object', properties: {} }
        }
      ]
    }));

    if (reordered.statusCode !== 200) {
      fail(`expected reordered-history 200, got ${reordered.statusCode}: ${reordered.body}`);
    }
    const messages = thirdUpstreamPayload?.messages || [];
    const assistantIndex = messages.findIndex((message) => message.role === 'assistant' && message.tool_calls);
    if (assistantIndex < 0 ||
        messages[assistantIndex + 1]?.role !== 'tool' ||
        messages[assistantIndex + 1]?.tool_call_id !== 'call_abc' ||
        messages[assistantIndex + 2]?.role !== 'user') {
      fail(`expected tool output to be repaired directly after assistant tool_calls, got ${JSON.stringify(messages)}`);
    }

    const missingToolResult = await requestJSON({
      hostname: '127.0.0.1',
      port: proxyPort,
      path: '/v1/responses',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      model: 'codex-mini',
      input: [
        {
          type: 'function_call',
          call_id: 'call_missing',
          name: 'open_chrome',
          arguments: '{"url":"chrome"}'
        },
        {
          role: 'user',
          content: 'continue even though restored history lost the tool output'
        }
      ],
      stream: true,
      tools: [
        {
          type: 'function',
          name: 'open_chrome',
          description: 'Open Chrome',
          parameters: { type: 'object', properties: {} }
        }
      ]
    }));

    if (missingToolResult.statusCode !== 200) {
      fail(`expected missing-tool-history to be healed, got ${missingToolResult.statusCode}: ${missingToolResult.body}`);
    }
    const healedMessages = fourthUpstreamPayload?.messages || [];
    const healedAssistantIndex = healedMessages.findIndex((message) => message.role === 'assistant' && message.tool_calls);
    if (healedAssistantIndex < 0 ||
        healedMessages[healedAssistantIndex + 1]?.role !== 'tool' ||
        healedMessages[healedAssistantIndex + 1]?.tool_call_id !== 'call_missing' ||
        !String(healedMessages[healedAssistantIndex + 1]?.content || '').includes('missing_from_restored_history')) {
      fail(`expected missing tool result to be synthesized after assistant tool_calls, got ${JSON.stringify(healedMessages)}`);
    }

    console.log('router-tool-call-check-pass');
  } catch (error) {
    fail(`${error.message}${stderr ? `\n${stderr}` : ''}`);
  } finally {
    child.kill();
    upstream.close();
  }
})();
