#!/usr/bin/env node
const assert = require('assert');
const path = require('path');

const {
    detectProtocol,
    buildAnthropicPayload,
    convertAnthropicToResponses,
    normalizeUsage,
    normalizeResponsesTool,
    normalizeToolChoice,
    isFailoverableStatus,
    makeMessageItem,
    makeFunctionCallItem,
    makeOutputTextPart,
    makeResponseObject,
    makeToolMessage,
    repairToolCallMessageOrder,
} = require(path.join(__dirname, '..', 'FreeModelMenuBar', 'router_sidecar'));

let passed = 0;
let failed = 0;

function test(name, fn) {
    try {
        fn();
        passed++;
    } catch (e) {
        failed++;
        console.error(`✗ ${name}\n  ${e.message}`);
        if (e.expected !== undefined && e.actual !== undefined) {
            console.error(`  expected: ${JSON.stringify(e.expected)}`);
            console.error(`  actual:   ${JSON.stringify(e.actual)}`);
        }
    }
}

// ── detectProtocol ──

test('detectProtocol: returns anthropic-messages for /v1/messages URL', () => {
    assert.strictEqual(detectProtocol('https://api.anthropic.com/v1/messages'), 'anthropic-messages');
});

test('detectProtocol: returns chat for /v1/chat/completions URL', () => {
    assert.strictEqual(detectProtocol('https://api.openai.com/v1/chat/completions'), 'chat');
});

test('detectProtocol: returns responses for /v1/responses URL', () => {
    assert.strictEqual(detectProtocol('http://127.0.0.1:7842/v1/responses'), 'responses');
});

test('detectProtocol: bare /v1 defaults to chat', () => {
    assert.strictEqual(detectProtocol('https://api.deepseek.com/v1'), 'chat');
});

test('detectProtocol: case insensitive', () => {
    assert.strictEqual(detectProtocol('HTTPS://API.ANTHROPIC.COM/V1/MESSAGES'), 'anthropic-messages');
});

test('detectProtocol: handles trailing slash', () => {
    assert.strictEqual(detectProtocol('https://api.anthropic.com/v1/messages/'), 'chat');
});

// ── buildAnthropicPayload ──

test('buildAnthropicPayload: string input produces single user message', () => {
    const r = buildAnthropicPayload({ input: 'Hello' }, 'claude-3');
    assert.strictEqual(r.model, 'claude-3');
    assert.strictEqual(r.messages.length, 1);
    assert.strictEqual(r.messages[0].role, 'user');
    assert.strictEqual(r.messages[0].content, 'Hello');
    assert.strictEqual(r.stream, false);
});

test('buildAnthropicPayload: empty input returns minimal payload', () => {
    const r = buildAnthropicPayload({}, 'claude-3');
    assert.strictEqual(r.messages.length, 0);
    assert.strictEqual(r.max_tokens, 4096);
});

test('buildAnthropicPayload: developer role becomes system field', () => {
    const r = buildAnthropicPayload({ input: [{ role: 'developer', content: 'Be brief.' }] }, 'claude-3');
    assert.strictEqual(r.system, 'Be brief.');
    assert.strictEqual(r.messages.length, 0);
});

test('buildAnthropicPayload: multiple strings grouped into one user turn', () => {
    const r = buildAnthropicPayload({ input: ['Hello', 'World'] }, 'claude-3');
    assert.strictEqual(r.messages.length, 1);
    assert.strictEqual(r.messages[0].role, 'user');
    assert.strictEqual(r.messages[0].content, 'Hello\nWorld');
});

test('buildAnthropicPayload: function_call mapped to tool_use (missing result synthesized)', () => {
    const r = buildAnthropicPayload({
        input: [{ type: 'function_call', call_id: 'c1', name: 'get_weather', arguments: '{"city":"NYC"}' }]
    }, 'claude-3');
    // assistant tool_use must be immediately followed by a user tool_result
    assert.strictEqual(r.messages.length, 2);
    assert.strictEqual(r.messages[0].role, 'assistant');
    assert.strictEqual(r.messages[0].content[0].type, 'tool_use');
    assert.strictEqual(r.messages[0].content[0].name, 'get_weather');
    assert.strictEqual(r.messages[0].content[0].id, 'c1');
    assert.deepStrictEqual(r.messages[0].content[0].input, { city: 'NYC' });
    assert.strictEqual(r.messages[1].role, 'user');
    assert.strictEqual(r.messages[1].content[0].type, 'tool_result');
    assert.strictEqual(r.messages[1].content[0].tool_use_id, 'c1');
});

test('buildAnthropicPayload: function_call with bad JSON arguments returns empty object', () => {
    const r = buildAnthropicPayload({
        input: [{ type: 'function_call', call_id: 'c1', name: 'foo', arguments: 'not json' }]
    }, 'claude-3');
    assert.deepStrictEqual(r.messages[0].content[0].input, {});
});

test('buildAnthropicPayload: function_call_output mapped to tool_result', () => {
    const r = buildAnthropicPayload({
        input: [{ type: 'function_call_output', call_id: 'c1', output: '42' }]
    }, 'claude-3');
    assert.strictEqual(r.messages[0].role, 'user');
    assert.strictEqual(r.messages[0].content[0].type, 'tool_result');
    assert.strictEqual(r.messages[0].content[0].tool_use_id, 'c1');
    assert.strictEqual(r.messages[0].content[0].content, '42');
});

test('buildAnthropicPayload: tool_choice auto maps to {type: auto}', () => {
    const r = buildAnthropicPayload({ input: 'Hi', tool_choice: 'auto' }, 'claude-3');
    assert.deepStrictEqual(r.tool_choice, { type: 'auto' });
});

test('buildAnthropicPayload: tool_choice required maps to {type: any}', () => {
    const r = buildAnthropicPayload({ input: 'Hi', tool_choice: 'required' }, 'claude-3');
    assert.deepStrictEqual(r.tool_choice, { type: 'any' });
});

test('buildAnthropicPayload: tool_choice function maps to {type: tool, name}', () => {
    const r = buildAnthropicPayload({ input: 'Hi', tool_choice: { type: 'function', name: 'foo' } }, 'claude-3');
    assert.deepStrictEqual(r.tool_choice, { type: 'tool', name: 'foo' });
});

test('buildAnthropicPayload: max_output_tokens maps to max_tokens', () => {
    const r = buildAnthropicPayload({ input: 'Hi', max_output_tokens: 2048 }, 'claude-3');
    assert.strictEqual(r.max_tokens, 2048);
});

test('buildAnthropicPayload: temperature passed through', () => {
    const r = buildAnthropicPayload({ input: 'Hi', temperature: 0.7 }, 'claude-3');
    assert.strictEqual(r.temperature, 0.7);
});

test('buildAnthropicPayload: missing function_call_output gets synthetic tool_result', () => {
    const r = buildAnthropicPayload({
        input: [
            { type: 'function_call', call_id: 'orphan_1', name: 'get_weather', arguments: '{}' }
        ]
    }, 'claude-3');
    // assistant(tool_use) must be immediately followed by user(tool_result)
    assert.strictEqual(r.messages.length, 2);
    assert.strictEqual(r.messages[0].role, 'assistant');
    assert.strictEqual(r.messages[0].content[0].type, 'tool_use');
    assert.strictEqual(r.messages[1].role, 'user');
    assert.strictEqual(r.messages[1].content[0].type, 'tool_result');
    assert.strictEqual(r.messages[1].content[0].tool_use_id, 'orphan_1');
});

test('buildAnthropicPayload: multiple missing function_call_output each get synthetic tool_result', () => {
    const r = buildAnthropicPayload({
        input: [
            { type: 'function_call', call_id: 'call_00', name: 'a', arguments: '{}' },
            { type: 'function_call', call_id: 'call_01', name: 'b', arguments: '{}' }
        ]
    }, 'claude-3');
    // Both tool_use live in the same assistant message; one user turn must hold both tool_results
    assert.strictEqual(r.messages.length, 2);
    assert.strictEqual(r.messages[0].content.length, 2);
    assert.strictEqual(r.messages[1].role, 'user');
    const resultIds = r.messages[1].content.map(b => b.tool_use_id).sort();
    assert.deepStrictEqual(resultIds, ['call_00', 'call_01']);
});

test('buildAnthropicPayload: present function_call_output not duplicated, missing one still filled', () => {
    const r = buildAnthropicPayload({
        input: [
            { type: 'function_call', call_id: 'present_1', name: 'a', arguments: '{}' },
            { type: 'function_call', call_id: 'missing_1', name: 'b', arguments: '{}' },
            { type: 'function_call_output', call_id: 'present_1', output: 'real result' }
        ]
    }, 'claude-3');
    assert.strictEqual(r.messages.length, 2);
    assert.strictEqual(r.messages[0].role, 'assistant');
    const results = r.messages[1].content;
    const present = results.find(b => b.tool_use_id === 'present_1');
    const missing = results.find(b => b.tool_use_id === 'missing_1');
    assert.ok(present, 'present tool_result should exist');
    assert.strictEqual(present.content, 'real result');
    assert.ok(missing, 'missing tool_result should be synthesized');
    assert.notStrictEqual(missing.content, 'real result');
});

test('buildAnthropicPayload: tool_use without result in later turn still gets synthetic tool_result', () => {
    const r = buildAnthropicPayload({
        input: [
            { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'q1' }] },
            { type: 'function_call', call_id: 'answered', name: 'a', arguments: '{}' },
            { type: 'function_call_output', call_id: 'answered', output: 'ok' },
            { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'q2' }] },
            { type: 'function_call', call_id: 'unanswered', name: 'b', arguments: '{}' }
        ]
    }, 'claude-3');
    // The last assistant message has an unanswered tool_use -> must be followed by tool_result
    const lastAssistant = [...r.messages].reverse().find(m => m.role === 'assistant');
    const idx = r.messages.indexOf(lastAssistant);
    const next = r.messages[idx + 1];
    assert.ok(next && next.role === 'user', 'next message after unanswered tool_use must be user');
    assert.ok(Array.isArray(next.content) && next.content.some(b => b.type === 'tool_result' && b.tool_use_id === 'unanswered'));
});

test('buildAnthropicPayload: tools converted to Anthropic format', () => {
    const r = buildAnthropicPayload({
        input: 'Hi',
        tools: [{ type: 'function', function: { name: 'foo', description: 'bar', parameters: { type: 'object' } } }]
    }, 'claude-3');
    assert.strictEqual(r.tools.length, 1);
    assert.strictEqual(r.tools[0].name, 'foo');
    assert.strictEqual(r.tools[0].input_schema.type, 'object');
});

// ── convertAnthropicToResponses ──

test('convertAnthropicToResponses: text-only response', () => {
    const json = { content: [{ type: 'text', text: 'Hello' }], usage: { input_tokens: 5, output_tokens: 3 } };
    const r = convertAnthropicToResponses(json, 'codex-mini');
    assert.strictEqual(r.object, 'response');
    assert.strictEqual(r.output_text, 'Hello');
    assert.strictEqual(r.output.length, 1);
    assert.strictEqual(r.output[0].type, 'message');
    assert.strictEqual(r.usage.input_tokens, 5);
    assert.strictEqual(r.usage.output_tokens, 3);
});

test('convertAnthropicToResponses: text + tool_use in one response', () => {
    const json = {
        content: [
            { type: 'text', text: 'Checking...' },
            { type: 'tool_use', id: 'tu_1', name: 'get_weather', input: { city: 'NYC' } }
        ],
        usage: { input_tokens: 10, output_tokens: 8 }
    };
    const r = convertAnthropicToResponses(json, 'codex-mini');
    assert.strictEqual(r.output.length, 2);
    assert.strictEqual(r.output[0].type, 'message');
    assert.strictEqual(r.output[1].type, 'function_call');
    assert.strictEqual(r.output[1].name, 'get_weather');
    assert.strictEqual(r.output[1].call_id, 'tu_1');
});

test('convertAnthropicToResponses: empty content yields empty output', () => {
    const json = { content: [], usage: {} };
    const r = convertAnthropicToResponses(json, 'codex-mini');
    assert.strictEqual(r.output.length, 0);
    assert.strictEqual(r.output_text, '');
});

test('convertAnthropicToResponses: missing usage falls back to zeros', () => {
    const json = { content: [{ type: 'text', text: 'x' }] };
    const r = convertAnthropicToResponses(json, 'codex-mini');
    assert.strictEqual(r.usage.input_tokens, 0);
    assert.strictEqual(r.usage.output_tokens, 0);
});

// ── normalizeUsage ──

test('normalizeUsage: uses input_tokens / output_tokens', () => {
    const u = normalizeUsage({ input_tokens: 50, output_tokens: 30 });
    assert.strictEqual(u.input_tokens, 50);
    assert.strictEqual(u.output_tokens, 30);
    assert.strictEqual(u.total_tokens, 80);
});

test('normalizeUsage: falls back to prompt_tokens / completion_tokens', () => {
    const u = normalizeUsage({ prompt_tokens: 40, completion_tokens: 20 });
    assert.strictEqual(u.input_tokens, 40);
    assert.strictEqual(u.output_tokens, 20);
});

test('normalizeUsage: uses provided fallback when usage is null', () => {
    const u = normalizeUsage(null, 100, 200);
    assert.strictEqual(u.input_tokens, 100);
    assert.strictEqual(u.output_tokens, 200);
});

test('normalizeUsage: uses provided fallback when usage is undefined', () => {
    const u = normalizeUsage(undefined, 10, 20);
    assert.strictEqual(u.input_tokens, 10);
    assert.strictEqual(u.output_tokens, 20);
});

test('normalizeUsage: respects total_tokens if present', () => {
    const u = normalizeUsage({ input_tokens: 5, output_tokens: 3, total_tokens: 10 });
    assert.strictEqual(u.total_tokens, 10);
});

// ── normalizeResponsesTool ──

test('normalizeResponsesTool: full nested format', () => {
    const t = { type: 'function', function: { name: 'foo', description: 'bar', parameters: { type: 'object' } } };
    const r = normalizeResponsesTool(t);
    assert.strictEqual(r.function.name, 'foo');
    assert.strictEqual(r.function.description, 'bar');
    assert.deepStrictEqual(r.function.parameters, { type: 'object' });
});

test('normalizeResponsesTool: flattened format (name directly on tool)', () => {
    const t = { type: 'function', name: 'bar', description: 'desc', parameters: {} };
    const r = normalizeResponsesTool(t);
    assert.strictEqual(r.function.name, 'bar');
    assert.strictEqual(r.function.description, 'desc');
});

test('normalizeResponsesTool: null for non-function tool', () => {
    assert.strictEqual(normalizeResponsesTool(null), null);
    assert.strictEqual(normalizeResponsesTool(undefined), null);
    assert.strictEqual(normalizeResponsesTool({ type: 'builtin' }), null);
    assert.strictEqual(normalizeResponsesTool('string'), null);
});

test('normalizeResponsesTool: missing description defaults to empty string', () => {
    const t = { type: 'function', function: { name: 'foo' } };
    assert.strictEqual(normalizeResponsesTool(t).function.description, '');
});

// ── normalizeToolChoice ──

test('normalizeToolChoice: auto/none/required pass through', () => {
    assert.strictEqual(normalizeToolChoice('auto'), 'auto');
    assert.strictEqual(normalizeToolChoice('none'), 'none');
    assert.strictEqual(normalizeToolChoice('required'), 'required');
});

test('normalizeToolChoice: function type with name wraps correctly', () => {
    assert.deepStrictEqual(normalizeToolChoice({ type: 'function', name: 'foo' }), { type: 'function', function: { name: 'foo' } });
});

test('normalizeToolChoice: function type with function.name passes through', () => {
    assert.deepStrictEqual(normalizeToolChoice({ type: 'function', function: { name: 'foo' } }), { type: 'function', function: { name: 'foo' } });
});

test('normalizeToolChoice: undefined for unknown shape', () => {
    assert.strictEqual(normalizeToolChoice({ type: 'something_else' }), undefined);
});

test('normalizeToolChoice: null passes through (returns null)', () => {
    assert.strictEqual(normalizeToolChoice(null), null);
});

// ── isFailoverableStatus ──

test('isFailoverableStatus: returns true for 429, 502, 503', () => {
    assert.ok(isFailoverableStatus(429));
    assert.ok(isFailoverableStatus(502));
    assert.ok(isFailoverableStatus(503));
});

test('isFailoverableStatus: returns false for 2xx, 4xx (except 429)', () => {
    assert.ok(!isFailoverableStatus(200));
    assert.ok(!isFailoverableStatus(400));
    assert.ok(!isFailoverableStatus(401));
});

test('isFailoverableStatus: returns true for all 5xx status codes', () => {
    assert.ok(isFailoverableStatus(500));
    assert.ok(isFailoverableStatus(501));
    assert.ok(isFailoverableStatus(502));
    assert.ok(isFailoverableStatus(503));
    assert.ok(isFailoverableStatus(504));
});

// ── Factory functions ──

test('makeOutputTextPart: produces correct shape', () => {
    const p = makeOutputTextPart('hello');
    assert.strictEqual(p.type, 'output_text');
    assert.strictEqual(p.text, 'hello');
    assert.deepStrictEqual(p.annotations, []);
});

test('makeMessageItem: completed status includes content', () => {
    const m = makeMessageItem('msg_1', 'completed', 'hello');
    assert.strictEqual(m.id, 'msg_1');
    assert.strictEqual(m.type, 'message');
    assert.strictEqual(m.role, 'assistant');
    assert.strictEqual(m.status, 'completed');
    assert.strictEqual(m.content.length, 1);
    assert.strictEqual(m.content[0].text, 'hello');
});

test('makeMessageItem: in_progress status has empty content', () => {
    const m = makeMessageItem('msg_1', 'in_progress', '');
    assert.strictEqual(m.content.length, 0);
});

test('makeFunctionCallItem: produces correct shape', () => {
    const f = makeFunctionCallItem('fc_1', 'call_1', 'completed', 'get_weather', '{}');
    assert.strictEqual(f.id, 'fc_1');
    assert.strictEqual(f.type, 'function_call');
    assert.strictEqual(f.call_id, 'call_1');
    assert.strictEqual(f.name, 'get_weather');
    assert.strictEqual(f.arguments, '{}');
});

test('makeResponseObject: includes all required top-level fields', () => {
    const r = makeResponseObject('resp_1', 1000, 'completed', [], 'output', { input_tokens: 1, output_tokens: 1, total_tokens: 2 });
    assert.strictEqual(r.id, 'resp_1');
    assert.strictEqual(r.object, 'response');
    assert.strictEqual(r.status, 'completed');
    assert.strictEqual(r.error, null);
    assert.strictEqual(r.output_text, 'output');
    assert.ok(Array.isArray(r.output));
    assert.strictEqual(r.usage.total_tokens, 2);
});

test('makeResponseObject: usage can be null', () => {
    const r = makeResponseObject('resp_1', 1000, 'in_progress', [], '', null);
    assert.strictEqual(r.usage, null);
});

test('makeToolMessage: creates tool role message', () => {
    const m = makeToolMessage('call_1', 'result');
    assert.strictEqual(m.role, 'tool');
    assert.strictEqual(m.tool_call_id, 'call_1');
    assert.strictEqual(m.content, 'result');
});

// ── repairToolCallMessageOrder ──

test('repairToolCallMessageOrder: already correct order unchanged', () => {
    const input = [
        { role: 'assistant', content: null, tool_calls: [{ id: 'c1', function: { name: 'f' } }] },
        { role: 'tool', tool_call_id: 'c1', content: 'result' }
    ];
    const r = repairToolCallMessageOrder(input, new Map());
    assert.strictEqual(r.error, undefined);
    assert.strictEqual(r.messages.length, 2);
});

test('repairToolCallMessageOrder: inserts synthetic message for missing tool result', () => {
    const input = [
        { role: 'assistant', content: null, tool_calls: [{ id: 'c_missing_1', function: { name: 'f' } }] }
    ];
    const r = repairToolCallMessageOrder(input, new Map());
    assert.strictEqual(r.messages.length, 2);
    assert.strictEqual(r.messages[1].role, 'tool');
    assert.ok(r.messages[1].content.includes('missing_from_restored_history'));
});

test('repairToolCallMessageOrder: uses externalToolResults for context restoration', () => {
    const input = [
        { role: 'assistant', content: null, tool_calls: [{ id: 'ctx_1', function: { name: 'f' } }] }
    ];
    const ctx = new Map([['ctx_1', 'restored_result']]);
    const r = repairToolCallMessageOrder(input, ctx);
    assert.strictEqual(r.messages.length, 2);
    assert.strictEqual(r.messages[1].content, 'restored_result');
});

test('repairToolCallMessageOrder: reorders out-of-order tool results', () => {
    const input = [
        { role: 'user', content: 'hi' },
        { role: 'tool', tool_call_id: 'c2', content: 'r2' },
        { role: 'assistant', content: null, tool_calls: [{ id: 'c1', function: { name: 'f' } }, { id: 'c2', function: { name: 'g' } }] },
        { role: 'tool', tool_call_id: 'c1', content: 'r1' }
    ];
    const r = repairToolCallMessageOrder(input, new Map());
    assert.strictEqual(r.error, undefined);
    const toolIdx = r.messages.findIndex(m => m.role === 'assistant');
    assert.strictEqual(r.messages[toolIdx + 1].tool_call_id, 'c1');
    assert.strictEqual(r.messages[toolIdx + 2].tool_call_id, 'c2');
});

// ── Summary ──

const total = passed + failed;
console.log(`\n\x1b[${failed ? '31m' : '32m'}${passed}/${total} passed${failed ? `, ${failed} failed` : ''}\x1b[0m`);
process.exit(failed ? 1 : 0);
