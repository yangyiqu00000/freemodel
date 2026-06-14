//
//  router_sidecar.js
//  FreeModelMenuBar
//
//  Stateless local Responses proxy sidecar for FreeModelMenuBar.
//  Translates Responses API requests to standard OpenAI Chat Completions requests.
//

const http = require('http');
const https = require('https');
const url = require('url');
const { StringDecoder } = require('string_decoder');

// Environment Variables & Mutable Configuration
const PORT = parseInt(process.env.PORT || '38440', 10);
const currentConfig = {
    port: PORT,
    upstreamBaseUrl: (process.env.UPSTREAM_BASE_URL || 'https://api.deepseek.com/v1').trim(),
    upstreamApiKey: (process.env.UPSTREAM_API_KEY || '').trim(),
    upstreamModel: (process.env.UPSTREAM_MODEL || 'deepseek-chat').trim(),
    routeModel: (process.env.ROUTE_MODEL || 'codex-mini').trim(),
    maxConcurrency: parseInt(process.env.PROXY_MAX_CONCURRENCY || '0', 10),
    minIntervalMs: parseInt(process.env.PROXY_MIN_INTERVAL_MS || '0', 10),
    activeProviderId: 'primary',
    providers: [],
    failoverEnabled: process.env.PROXY_FAILOVER_ENABLED !== 'false'
};

// Dynamic getter bridges for legacy code compatibility
Object.defineProperty(global, 'ROUTE_MODEL', {
    get: () => currentConfig.routeModel,
    configurable: true
});
Object.defineProperty(global, 'UPSTREAM_MODEL', {
    get: () => currentConfig.upstreamModel,
    configurable: true
});

const reasoningContentByCallId = new Map();
const toolResultByCallId = new Map();

const queue = [];
let activeCount = 0;
let lastRequestStartTime = 0;
let queueTimeout = null;

console.log(`[Proxy] Initial Settings: Concurrency Limit = ${currentConfig.maxConcurrency}, Min Interval = ${currentConfig.minIntervalMs}ms`);

// Exit automatically on EOF, and support dynamic config updates via stdin JSON lines
const readline = require('readline');
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
});

rl.on('line', (line) => {
    try {
        const msg = JSON.parse(line);
        if (msg.type === 'update_config') {
            if (msg.activeAccount) {
                currentConfig.activeProviderId = msg.activeAccount.providerID || 'primary';
                currentConfig.upstreamBaseUrl = (msg.activeAccount.url || '').trim();
                currentConfig.upstreamApiKey = (msg.activeAccount.key || '').trim();
                currentConfig.upstreamModel = (msg.activeAccount.model || '').trim();
            }
            if (msg.backups !== undefined) {
                currentConfig.providers = msg.backups;
            }
            if (msg.routeModel !== undefined) currentConfig.routeModel = msg.routeModel;
            if (msg.maxConcurrency !== undefined) currentConfig.maxConcurrency = parseInt(msg.maxConcurrency, 10) || 0;
            if (msg.minIntervalMs !== undefined) currentConfig.minIntervalMs = parseInt(msg.minIntervalMs, 10) || 0;
            if (msg.failoverEnabled !== undefined) {
                currentConfig.failoverEnabled = !!msg.failoverEnabled;
            }

            console.log(JSON.stringify({
                time: new Date().toTimeString().split(' ')[0],
                method: "SYS",
                path: "",
                status: 200,
                duration: 0,
                model: "",
                upstream: "",
                error: `[Proxy] 配置动态更新成功: Upstream = ${currentConfig.upstreamBaseUrl}, Model = ${currentConfig.upstreamModel}, Backups = ${currentConfig.providers.length}, Failover = ${currentConfig.failoverEnabled}`
            }));
        }
    } catch (err) {
        // Ignore parsing errors of non-config stdin lines
    }
});

const STARTUP_TIME = Date.now();
rl.on('close', () => {
    // If stdin closes immediately on startup, it means it was spawned with 'ignore' or redirection (e.g. in legacy tests).
    // In this case, do not exit the process.
    if (Date.now() - STARTUP_TIME < 200) {
        return;
    }
    console.log(JSON.stringify({
        time: new Date().toTimeString().split(' ')[0],
        method: "SYS",
        path: "",
        status: 200,
        duration: 0,
        model: "",
        upstream: "",
        error: "检测到主应用进程已退出，路由侧车自主终止。"
    }));
    process.exit(0);
});

function enqueue(item) {
    queue.push(item);
    processQueue();
}

function processQueue() {
    if (queue.length === 0) {
        return;
    }

    // Check concurrency limit
    if (currentConfig.maxConcurrency > 0 && activeCount >= currentConfig.maxConcurrency) {
        return;
    }

    // Check min interval limit
    const now = Date.now();
    const elapsed = now - lastRequestStartTime;
    if (currentConfig.minIntervalMs > 0 && elapsed < currentConfig.minIntervalMs) {
        const delay = currentConfig.minIntervalMs - elapsed;
        if (!queueTimeout) {
            queueTimeout = setTimeout(() => {
                queueTimeout = null;
                processQueue();
            }, delay);
        }
        return;
    }

    // Dequeue next item
    const item = queue.shift();

    // If client already closed, skip it
    if (item.clientClosed || item.res.writableEnded || item.res.finished) {
        processQueue();
        return;
    }

    // Execute
    activeCount++;
    lastRequestStartTime = Date.now();

    item.run(() => {
        activeCount--;
        processQueue();
    });

    // Try processing next item immediately if concurrency allows
    processQueue();
}

async function acquirePermit(req, res, start) {
    return new Promise((resolve) => {
        const queueItem = {
            req,
            res,
            clientClosed: false,
            started: false,
            run: (done) => {
                queueItem.started = true;
                if (queueItem.clientClosed) {
                    done();
                    resolve(null);
                    return;
                }

                let released = false;
                const release = () => {
                    if (released) return;
                    released = true;
                    done();
                };

                res.on('finish', release);
                res.on('close', release);

                resolve(release);
            }
        };

        res.on('close', () => {
            queueItem.clientClosed = true;
            if (!queueItem.started) {
                logRequest('POST', req.url, 499, Date.now() - start, ROUTE_MODEL, UPSTREAM_MODEL, 'Client closed request while queued');
                resolve(null);
            }
        });

        enqueue(queueItem);
    });
}

// Log helper to output formatted JSON for Swift RouterManager to parse
function logRequest(method, path, statusCode, durationMs, model, upstreamModel, errorMsg = null) {
    const logEntry = {
        time: new Date().toISOString(),
        method,
        path,
        status: statusCode,
        duration: durationMs,
        model,
        upstream: upstreamModel,
        error: errorMsg
    };
    console.log(JSON.stringify(logEntry));
}

// Helper to send JSON error
function sendJSONError(res, statusCode, message, type = 'proxy_error', code = 500) {
    if (res.headersSent) {
        // If headers already sent (streaming), write standard Responses API response.failed event then end.
        try {
            res.write(`event: response.failed\ndata: ${JSON.stringify({
                type: 'response.failed',
                error: {
                    message,
                    type,
                    code: String(code),
                    param: null
                }
            })}\n\n`);
            res.end();
        } catch (_) {}
        return;
    }
    res.writeHead(statusCode, {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
    });
    res.end(JSON.stringify({
        error: {
            message,
            type,
            code
        }
    }));
}

function normalizeUsage(usage, fallbackInputTokens = 0, fallbackOutputTokens = 0) {
    const inputTokens = usage?.input_tokens ?? usage?.prompt_tokens ?? fallbackInputTokens;
    const outputTokens = usage?.output_tokens ?? usage?.completion_tokens ?? fallbackOutputTokens;
    return {
        input_tokens: inputTokens,
        output_tokens: outputTokens,
        total_tokens: usage?.total_tokens ?? (inputTokens + outputTokens)
    };
}

function makeOutputTextPart(text) {
    return {
        type: 'output_text',
        text,
        annotations: []
    };
}

function makeMessageItem(itemId, status, text) {
    return {
        id: itemId,
        type: 'message',
        status,
        role: 'assistant',
        content: status === 'completed' ? [makeOutputTextPart(text)] : []
    };
}

function makeFunctionCallItem(itemId, callId, status, name, args) {
    return {
        id: itemId,
        type: 'function_call',
        status,
        call_id: callId,
        name,
        arguments: args
    };
}

function makeResponseObject(respId, createdAt, status, output, outputText, usage = null) {
    return {
        id: respId,
        object: 'response',
        created_at: createdAt,
        status,
        model: ROUTE_MODEL,
        output,
        output_text: outputText,
        usage,
        error: null,
        incomplete_details: null,
        instructions: null,
        metadata: {},
        parallel_tool_calls: true,
        previous_response_id: null,
        store: true,
        temperature: null,
        tool_choice: 'auto',
        tools: [],
        top_p: null,
        truncation: 'disabled',
        max_output_tokens: null
    };
}

function rememberReasoningContent(callId, reasoningContent) {
    if (!callId || !reasoningContent) {
        return;
    }
    reasoningContentByCallId.set(callId, reasoningContent);
    if (reasoningContentByCallId.size > 200) {
        const oldestKey = reasoningContentByCallId.keys().next().value;
        reasoningContentByCallId.delete(oldestKey);
    }
}

function rememberToolResult(callId, content) {
    if (!callId || content === undefined || content === null) {
        return;
    }
    toolResultByCallId.set(callId, String(content));
    if (toolResultByCallId.size > 200) {
        const oldestKey = toolResultByCallId.keys().next().value;
        toolResultByCallId.delete(oldestKey);
    }
}

function makeToolMessage(toolCallId, content) {
    return {
        role: 'tool',
        tool_call_id: toolCallId,
        content
    };
}

function makeSyntheticMissingToolMessage(toolCallId) {
    return makeToolMessage(toolCallId, JSON.stringify({
        error: 'missing_from_restored_history',
        message: 'The tool result for this call was not present in restored conversation history. Continue without relying on the missing result.',
        tool_call_id: toolCallId
    }));
}

function normalizeResponsesTool(tool) {
    if (!tool || typeof tool !== 'object' || tool.type !== 'function') {
        return null;
    }
    if (tool.function && typeof tool.function === 'object') {
        return {
            type: 'function',
            function: {
                name: tool.function.name,
                description: tool.function.description || '',
                parameters: tool.function.parameters || {}
            }
        };
    }
    return {
        type: 'function',
        function: {
            name: tool.name,
            description: tool.description || '',
            parameters: tool.parameters || {}
        }
    };
}

function normalizeToolChoice(toolChoice) {
    if (!toolChoice || toolChoice === 'auto' || toolChoice === 'none' || toolChoice === 'required') {
        return toolChoice;
    }
    if (toolChoice.type === 'function' && toolChoice.name) {
        return { type: 'function', function: { name: toolChoice.name } };
    }
    if (toolChoice.type === 'function' && toolChoice.function?.name) {
        return toolChoice;
    }
    return undefined;
}

function repairToolCallMessageOrder(messages) {
    const consumed = new Set();
    const repaired = [];
    const toolMessageIndexesById = new Map();

    for (let i = 0; i < messages.length; i += 1) {
        const message = messages[i];
        if (message.role === 'tool' && message.tool_call_id) {
            if (!toolMessageIndexesById.has(message.tool_call_id)) {
                toolMessageIndexesById.set(message.tool_call_id, []);
            }
            toolMessageIndexesById.get(message.tool_call_id).push(i);
            rememberToolResult(message.tool_call_id, message.content);
        }
    }

    function findAnyUnconsumedToolMessage(toolCallId) {
        const indexes = toolMessageIndexesById.get(toolCallId) || [];
        return indexes.find((index) => !consumed.has(index)) ?? -1;
    }

    for (let i = 0; i < messages.length; i += 1) {
        if (consumed.has(i)) {
            continue;
        }
        const message = messages[i];
        const toolCalls = Array.isArray(message.tool_calls) ? message.tool_calls : [];

        if (message.role === 'assistant' && toolCalls.length) {
            repaired.push(message);
            consumed.add(i);

            for (const toolCall of toolCalls) {
                const toolCallId = toolCall.id;
                let matchingToolIndex = -1;
                for (let j = i + 1; j < messages.length; j += 1) {
                    if (consumed.has(j)) {
                        continue;
                    }
                    const candidate = messages[j];
                    if (candidate.role === 'assistant' && Array.isArray(candidate.tool_calls) && candidate.tool_calls.length) {
                        break;
                    }
                    if (candidate.role === 'tool' && candidate.tool_call_id === toolCallId) {
                        matchingToolIndex = j;
                        break;
                    }
                }

	                if (matchingToolIndex === -1) {
	                    matchingToolIndex = findAnyUnconsumedToolMessage(toolCallId);
	                }
	
	                if (matchingToolIndex !== -1) {
	                    repaired.push(messages[matchingToolIndex]);
	                    consumed.add(matchingToolIndex);
	                } else if (toolResultByCallId.has(toolCallId)) {
	                    repaired.push(makeToolMessage(toolCallId, toolResultByCallId.get(toolCallId)));
	                } else {
	                    repaired.push(makeSyntheticMissingToolMessage(toolCallId));
	                }
	            }
	            continue;
	        }
	
	        if (message.role === 'tool') {
	            consumed.add(i);
	            continue;
	        }

        repaired.push(message);
        consumed.add(i);
    }

    return { messages: repaired };
}

function isFailoverableStatus(statusCode) {
    return statusCode === 429 || (statusCode >= 500 && statusCode <= 599);
}

function isDeepseekOrReasoningModel(modelName, url) {
    const lowerModel = String(modelName || '').toLowerCase();
    const lowerUrl = String(url || '').toLowerCase();
    return lowerModel.includes('deepseek') || 
           lowerModel.includes('reasoner') || 
           lowerModel.includes('-r1') || 
           lowerUrl.includes('deepseek');
}

function dispatchWithFailover(candidates, candidateIndex, chatPayload, stream, res, req, parsedUrl, start, routeModel, onFinish, lastStatusCode = 502, lastErrorMsg = 'All upstream providers failed', lastUpstreamModel = '') {
    if (candidateIndex >= candidates.length) {
        // All candidates failed
        console.error(`[Proxy] All candidates failed. Returning error: ${lastErrorMsg}`);
        sendJSONError(res, lastStatusCode, lastErrorMsg, 'upstream_error', lastStatusCode);
        logRequest('POST', parsedUrl.pathname, lastStatusCode, Date.now() - start, routeModel, lastUpstreamModel, lastErrorMsg);
        onFinish();
        return;
    }

    const candidate = candidates[candidateIndex];
    
    // Log SYS message for Swift RouterManager to parse and show
    console.log(JSON.stringify({
        time: new Date().toTimeString().split(' ')[0],
        method: "SYS",
        path: "",
        status: 200,
        duration: 0,
        model: "",
        upstream: "",
        error: `[Proxy] 正在将请求发送至渠道 ${candidateIndex + 1}/${candidates.length}: ${candidate.id} (${candidate.url})`
    }));

    // Construct target payload specifically for this candidate, removing reasoning_content/reasoning_effort if not supported
    const isReasoning = isDeepseekOrReasoningModel(candidate.model, candidate.url);
    const requestPayload = {
        ...chatPayload,
        model: candidate.model
    };
    if (!isReasoning) {
        delete requestPayload.reasoning_effort;
    }
    if (Array.isArray(chatPayload.messages)) {
        requestPayload.messages = chatPayload.messages.map(m => {
            if (m.role === 'assistant' && m.reasoning_content !== undefined) {
                const newMsg = { ...m };
                if (!isReasoning) {
                    delete newMsg.reasoning_content;
                }
                return newMsg;
            }
            return m;
        });
    }

    let targetUrlStr = candidate.url;
    if (!targetUrlStr.endsWith('/chat/completions')) {
        targetUrlStr = targetUrlStr.replace(/\/$/, '') + '/chat/completions';
    }

    const parsedTargetUrl = new URL(targetUrlStr);
    const isHttps = parsedTargetUrl.protocol === 'https:';
    const requester = isHttps ? https : http;
    const payloadStr = JSON.stringify(requestPayload);

    const headers = {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payloadStr)
    };
    if (candidate.key) {
        headers['Authorization'] = `Bearer ${candidate.key}`;
    }

    const requestOptions = {
        hostname: parsedTargetUrl.hostname,
        port: parsedTargetUrl.port || (isHttps ? 443 : 80),
        path: parsedTargetUrl.pathname + parsedTargetUrl.search,
        method: 'POST',
        headers: headers,
        timeout: 300000 // 5 minutes timeout
    };

    let streamEnded = false;
    let upstreamReq;

    const clientCloseHandler = () => {
        if (!res.writableFinished && !streamEnded) {
            streamEnded = true;
            console.log(`[Proxy] Client connection closed. Aborting request to candidate ${candidate.id}.`);
            if (upstreamReq) {
                upstreamReq.destroy();
            }
        }
    };
    res.on('close', clientCloseHandler);

    upstreamReq = requester.request(requestOptions, (upstreamRes) => {
        const statusCode = upstreamRes.statusCode;

        if (stream) {
            // Streaming response conversion
            if (statusCode >= 400) {
                let errorBody = '';
                upstreamRes.on('data', d => { errorBody += d; });
                upstreamRes.on('end', () => {
                    let errorMsg = `Upstream streaming error: ${statusCode}`;
                    try {
                        const parsedError = JSON.parse(errorBody);
                        errorMsg = parsedError.error?.message || errorMsg;
                    } catch (_) {}

                    if (isFailoverableStatus(statusCode) && candidateIndex + 1 < candidates.length) {
                        console.log(JSON.stringify({
                            time: new Date().toTimeString().split(' ')[0],
                            method: "SYS",
                            path: "",
                            status: 200,
                            duration: 0,
                            model: "",
                            upstream: "",
                            error: `[Proxy] 渠道 ${candidate.id} 请求失败 (状态码 ${statusCode}: ${errorMsg})，正在自动尝试备用渠道...`
                        }));
                        res.off('close', clientCloseHandler);
                        dispatchWithFailover(candidates, candidateIndex + 1, chatPayload, stream, res, req, parsedUrl, start, routeModel, onFinish, statusCode, errorMsg, candidate.model);
                    } else {
                        sendJSONError(res, statusCode, errorMsg, 'upstream_error', statusCode);
                        logRequest('POST', parsedUrl.pathname, statusCode, Date.now() - start, routeModel, candidate.model, errorMsg);
                        onFinish();
                    }
                });
                return;
            }

            res.writeHead(200, {
                'Content-Type': 'text/event-stream',
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive',
                'Transfer-Encoding': 'chunked',
                'X-Accel-Buffering': 'no',
                'Access-Control-Allow-Origin': '*'
            });

            const respId = 'resp_' + Math.random().toString(36).substring(2, 15);
            const createdTime = Math.floor(Date.now() / 1000);
            const itemId = 'msg_' + Math.random().toString(36).substring(2, 15);
            let sequenceNumber = 0;

            function writeResponseEvent(eventType, payload) {
                const eventData = {
                    type: eventType,
                    sequence_number: sequenceNumber++,
                    ...payload
                };
                res.write(`event: ${eventType}
data: ${JSON.stringify(eventData)}

`);
            }

            let nextOutputIndex = 0;
            let textOutputIndex = null;
            let textItemStarted = false;
            const toolCallStates = new Map();

            function ensureTextItemStarted() {
                if (textItemStarted) {
                    return;
                }
                textItemStarted = true;
                textOutputIndex = nextOutputIndex++;
                writeResponseEvent('response.output_item.added', {
                    response_id: respId,
                    output_index: textOutputIndex,
                    item: makeMessageItem(itemId, 'in_progress', '')
                });
                writeResponseEvent('response.content_part.added', {
                    response_id: respId,
                    item_id: itemId,
                    output_index: textOutputIndex,
                    content_index: 0,
                    part: makeOutputTextPart('')
                });
            }

            function ensureToolCallState(toolCall) {
                const index = toolCall.index ?? 0;
                if (toolCallStates.has(index)) {
                    const existing = toolCallStates.get(index);
                    if (toolCall.id) existing.callId = toolCall.id;
                    if (toolCall.function?.name) existing.name = toolCall.function.name;
                    return existing;
                }
                const callId = toolCall.id || `call_${Math.random().toString(36).substring(2, 12)}`;
                const state = {
                    itemId: `fc_${Math.random().toString(36).substring(2, 15)}`,
                    callId,
                    name: toolCall.function?.name || '',
                    arguments: '',
                    outputIndex: nextOutputIndex++
                };
                toolCallStates.set(index, state);
                writeResponseEvent('response.output_item.added', {
                    response_id: respId,
                    output_index: state.outputIndex,
                    item: makeFunctionCallItem(state.itemId, state.callId, 'in_progress', state.name, '')
                });
                return state;
            }

            // Initial event for Responses API
            writeResponseEvent('response.created', {
                response: makeResponseObject(respId, createdTime, 'in_progress', [], '', null)
            });

            let buffer = '';
            const decoder = new StringDecoder('utf8');
            let completionTokens = 0;
            let promptTokens = 0;
            let receivedUsage = false;
            let accumulatedText = '';
            let accumulatedReasoningContent = '';
            let thinkBuffer = '';

            function processSSELines(lines) {
                for (let line of lines) {
                    line = line.trim();
                    if (!line) continue;
                    if (line.startsWith('data:')) {
                        const dataStr = line.substring(5).trim();
                        if (dataStr === '[DONE]') {
                            continue;
                        }
                        try {
                            const json = JSON.parse(dataStr);

                            // Extract usage info if present
                            if (json.usage) {
                                promptTokens = json.usage.prompt_tokens || promptTokens;
                                completionTokens = json.usage.completion_tokens || completionTokens;
                                receivedUsage = true;
                            }

                            const choice = json.choices && json.choices[0];
                            if (choice && choice.delta) {
                                if (choice.delta.reasoning_content) {
                                    accumulatedReasoningContent += choice.delta.reasoning_content;
                                }
                                // Handle regular content
                                if (choice.delta.content) {
                                    const text = choice.delta.content;
                                    thinkBuffer += text;

                                    while (thinkBuffer.length > 0) {
                                        const thinkStartIndex = thinkBuffer.indexOf('<think>');
                                        if (thinkStartIndex !== -1) {
                                            const thinkEndIndex = thinkBuffer.indexOf('</think>', thinkStartIndex);
                                            if (thinkEndIndex !== -1) {
                                                // We found the complete think block.
                                                const reasoning = thinkBuffer.substring(thinkStartIndex + 7, thinkEndIndex);
                                                accumulatedReasoningContent += reasoning;

                                                // Extract the text before <think> and after </think>
                                                const beforeText = thinkBuffer.substring(0, thinkStartIndex);
                                                if (beforeText) {
                                                    ensureTextItemStarted();
                                                    accumulatedText += beforeText;
                                                    if (!receivedUsage) {
                                                        completionTokens += Math.max(1, Math.ceil(beforeText.length / 3));
                                                    }
                                                    writeResponseEvent('response.output_text.delta', {
                                                        response_id: respId,
                                                        item_id: itemId,
                                                        output_index: textOutputIndex,
                                                        content_index: 0,
                                                        delta: beforeText
                                                    });
                                                }

                                                // Keep the remaining buffer after </think>
                                                thinkBuffer = thinkBuffer.substring(thinkEndIndex + 8);
                                            } else {
                                                // <think> is found, but </think> is not yet. We must wait for more data.
                                                // Send anything before <think> to the client immediately.
                                                const beforeText = thinkBuffer.substring(0, thinkStartIndex);
                                                if (beforeText) {
                                                    ensureTextItemStarted();
                                                    accumulatedText += beforeText;
                                                    if (!receivedUsage) {
                                                        completionTokens += Math.max(1, Math.ceil(beforeText.length / 3));
                                                    }
                                                    writeResponseEvent('response.output_text.delta', {
                                                        response_id: respId,
                                                        item_id: itemId,
                                                        output_index: textOutputIndex,
                                                        content_index: 0,
                                                        delta: beforeText
                                                    });
                                                }
                                                // The buffer now starts from <think>
                                                thinkBuffer = thinkBuffer.substring(thinkStartIndex);
                                                break;
                                            }
                                        } else {
                                            // No <think> in buffer.
                                            // Check if the end of the buffer could be a partial start of "<think>"
                                            let partialMatchIndex = -1;
                                            for (let i = 1; i < 7; i++) {
                                                const suffix = thinkBuffer.substring(thinkBuffer.length - i);
                                                if ('<think>'.startsWith(suffix)) {
                                                    partialMatchIndex = thinkBuffer.length - i;
                                                    break;
                                                }
                                            }

                                            if (partialMatchIndex !== -1) {
                                                // Flush everything except the potential partial match
                                                const flushText = thinkBuffer.substring(0, partialMatchIndex);
                                                if (flushText) {
                                                    ensureTextItemStarted();
                                                    accumulatedText += flushText;
                                                    if (!receivedUsage) {
                                                        completionTokens += Math.max(1, Math.ceil(flushText.length / 3));
                                                    }
                                                    writeResponseEvent('response.output_text.delta', {
                                                        response_id: respId,
                                                        item_id: itemId,
                                                        output_index: textOutputIndex,
                                                        content_index: 0,
                                                        delta: flushText
                                                    });
                                                }
                                                thinkBuffer = thinkBuffer.substring(partialMatchIndex);
                                                break;
                                            } else {
                                                // No partial match, flush the entire buffer
                                                ensureTextItemStarted();
                                                accumulatedText += thinkBuffer;
                                                if (!receivedUsage) {
                                                    completionTokens += Math.max(1, Math.ceil(thinkBuffer.length / 3));
                                                }
                                                writeResponseEvent('response.output_text.delta', {
                                                    response_id: respId,
                                                    item_id: itemId,
                                                    output_index: textOutputIndex,
                                                    content_index: 0,
                                                    delta: thinkBuffer
                                                });
                                                thinkBuffer = '';
                                            }
                                        }
                                    }
                                }
                                if (Array.isArray(choice.delta.tool_calls)) {
                                    for (const toolCall of choice.delta.tool_calls) {
                                        const state = ensureToolCallState(toolCall);
                                        if (toolCall.function?.name) {
                                            state.name = toolCall.function.name;
                                        }
                                        const argDelta = toolCall.function?.arguments || '';
                                        if (argDelta) {
                                            state.arguments += argDelta;
                                            writeResponseEvent('response.function_call_arguments.delta', {
                                                response_id: respId,
                                                item_id: state.itemId,
                                                output_index: state.outputIndex,
                                                delta: argDelta
                                            });
                                        }
                                    }
                                }
                            }
                        } catch (_) {}
                    }
                }
            }

            upstreamRes.on('data', (chunk) => {
                buffer += decoder.write(chunk);
                const lines = buffer.split('\n');
                buffer = lines.pop(); // keep last incomplete line
                processSSELines(lines);
            });

            upstreamRes.on('end', () => {
                if (streamEnded) return;
                streamEnded = true;

                // Flush remaining buffer
                buffer += decoder.end();
                if (buffer.trim()) {
                    processSSELines(buffer.split('\n'));
                }

                // Estimate prompt tokens if not provided by upstream
                if (!promptTokens) {
                    promptTokens = Math.ceil(chatPayload.messages.reduce((acc, m) => {
                        if (typeof m.content === 'string') {
                            return acc + m.content.length / 3;
                        } else if (Array.isArray(m.content)) {
                            const textLength = m.content.reduce((sum, part) => {
                                if (part && part.text) {
                                    return sum + part.text.length;
                                }
                                return sum;
                            }, 0);
                            return acc + textLength / 3;
                        }
                        return acc;
                    }, 0));
                }
                if (!completionTokens && accumulatedText) {
                    completionTokens = Math.ceil(accumulatedText.length / 3);
                }

                const usage = normalizeUsage(null, promptTokens, completionTokens);
                const completedOutput = [];

                if (textItemStarted) {
                    rememberReasoningContent(itemId, accumulatedReasoningContent);
                    const finalPart = makeOutputTextPart(accumulatedText);
                    const finalItem = makeMessageItem(itemId, 'completed', accumulatedText);
                    completedOutput[textOutputIndex] = finalItem;

                    writeResponseEvent('response.output_text.done', {
                        response_id: respId,
                        item_id: itemId,
                        output_index: textOutputIndex,
                        content_index: 0,
                        text: accumulatedText
                    });

                    writeResponseEvent('response.content_part.done', {
                        response_id: respId,
                        item_id: itemId,
                        output_index: textOutputIndex,
                        content_index: 0,
                        part: finalPart
                    });

                    writeResponseEvent('response.output_item.done', {
                        response_id: respId,
                        output_index: textOutputIndex,
                        item: finalItem
                    });
                }

                for (const state of Array.from(toolCallStates.values()).sort((a, b) => a.outputIndex - b.outputIndex)) {
                    rememberReasoningContent(state.callId, accumulatedReasoningContent);
                    const finalToolItem = makeFunctionCallItem(state.itemId, state.callId, 'completed', state.name, state.arguments);
                    completedOutput[state.outputIndex] = finalToolItem;
                    writeResponseEvent('response.function_call_arguments.done', {
                        response_id: respId,
                        item_id: state.itemId,
                        output_index: state.outputIndex,
                        arguments: state.arguments
                    });
                    writeResponseEvent('response.output_item.done', {
                        response_id: respId,
                        output_index: state.outputIndex,
                        item: finalToolItem
                    });
                }

                // Send response.completed last.
                writeResponseEvent('response.completed', {
                    response: makeResponseObject(
                        respId,
                        createdTime,
                        'completed',
                        completedOutput.filter(Boolean),
                        accumulatedText,
                        usage
                    )
                });

                res.end();
                logRequest('POST', parsedUrl.pathname, 200, Date.now() - start, routeModel, candidate.model);
                onFinish();
            });

            // Handle upstream connection errors during streaming
            upstreamRes.on('error', (err) => {
                if (streamEnded) return;
                streamEnded = true;
                console.error('[Proxy] Upstream response error during streaming:', err.message);
                sendJSONError(res, 502, 'Upstream stream error: ' + err.message, 'upstream_stream_error', 502);
                logRequest('POST', parsedUrl.pathname, 502, Date.now() - start, routeModel, candidate.model, 'Stream error: ' + err.message);
                onFinish();
            });

        } else {
            // Non-streaming response conversion
            let responseData = '';
            upstreamRes.on('data', chunk => {
                responseData += chunk;
            });

            upstreamRes.on('end', () => {
                let json;
                try {
                    json = JSON.parse(responseData || '{}');
                } catch (err) {
                    if (candidateIndex + 1 < candidates.length) {
                        console.log(JSON.stringify({
                            time: new Date().toTimeString().split(' ')[0],
                            method: "SYS",
                            path: "",
                            status: 200,
                            duration: 0,
                            model: "",
                            upstream: "",
                            error: `[Proxy] 渠道 ${candidate.id} 返回非 JSON 数据，正在尝试下一个备用渠道...`
                        }));
                        res.off('close', clientCloseHandler);
                        dispatchWithFailover(candidates, candidateIndex + 1, chatPayload, stream, res, req, parsedUrl, start, routeModel, onFinish, 500, 'JSON parse failed', candidate.model);
                    } else {
                        sendJSONError(res, 500, 'Failed to parse upstream response: ' + err.message, 'upstream_parse_error', 500);
                        logRequest('POST', parsedUrl.pathname, 500, Date.now() - start, routeModel, candidate.model, 'Upstream response not JSON');
                        onFinish();
                    }
                    return;
                }

                if (statusCode >= 400) {
                    const errorMsg = json.error?.message || 'Upstream server returned error';
                    if (isFailoverableStatus(statusCode) && candidateIndex + 1 < candidates.length) {
                        console.log(JSON.stringify({
                            time: new Date().toTimeString().split(' ')[0],
                            method: "SYS",
                            path: "",
                            status: 200,
                            duration: 0,
                            model: "",
                            upstream: "",
                            error: `[Proxy] 渠道 ${candidate.id} 请求失败 (状态码 ${statusCode}: ${errorMsg})，正在自动尝试备用渠道...`
                        }));
                        res.off('close', clientCloseHandler);
                        dispatchWithFailover(candidates, candidateIndex + 1, chatPayload, stream, res, req, parsedUrl, start, routeModel, onFinish, statusCode, errorMsg, candidate.model);
                    } else {
                        sendJSONError(res, statusCode, errorMsg, 'upstream_error', statusCode);
                        logRequest('POST', parsedUrl.pathname, statusCode, Date.now() - start, routeModel, candidate.model, errorMsg);
                        onFinish();
                    }
                    return;
                }

                const message = json.choices && json.choices[0] && json.choices[0].message || {};
                let content = message.content || '';
                let reasoningContent = message.reasoning_content || '';
                if (content.includes('<think>')) {
                    const match = content.match(/<think>([\s\S]*?)<\/think>/);
                    if (match) {
                        reasoningContent = match[1];
                        content = content.replace(/<think>[\s\S]*?<\/think>\n?/g, '');
                    }
                }
                const usage = normalizeUsage(json.usage, 0, 0);
                const respId = 'resp_' + Math.random().toString(36).substring(2, 15);
                const itemId = 'msg_' + Math.random().toString(36).substring(2, 15);
                const createdTime = Math.floor(Date.now() / 1000);
                const output = [];
                if (content) {
                    if (reasoningContent) {
                        rememberReasoningContent(itemId, reasoningContent);
                    }
                    output.push(makeMessageItem(itemId, 'completed', content));
                }
                if (Array.isArray(message.tool_calls)) {
                    for (const toolCall of message.tool_calls) {
                        rememberReasoningContent(toolCall.id, message.reasoning_content || reasoningContent);
                        output.push(makeFunctionCallItem(
                            `fc_${Math.random().toString(36).substring(2, 15)}`,
                            toolCall.id || `call_${Math.random().toString(36).substring(2, 12)}`,
                            'completed',
                            toolCall.function?.name || '',
                            toolCall.function?.arguments || ''
                        ));
                    }
                }

                const responsesJson = {
                    ...makeResponseObject(respId, createdTime, 'completed', output, content, usage)
                };

                res.writeHead(200, {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                });
                res.end(JSON.stringify(responsesJson));
                logRequest('POST', parsedUrl.pathname, 200, Date.now() - start, routeModel, candidate.model);
                onFinish();
            });
        }
    });

    upstreamReq.on('error', (err) => {
        if (streamEnded) return;
        streamEnded = true;

        if (candidateIndex + 1 < candidates.length) {
            console.log(JSON.stringify({
                time: new Date().toTimeString().split(' ')[0],
                method: "SYS",
                path: "",
                status: 200,
                duration: 0,
                model: "",
                upstream: "",
                error: `[Proxy] 渠道 ${candidate.id} 连接失败 (${err.message})，正在自动尝试备用渠道...`
            }));
            res.off('close', clientCloseHandler);
            dispatchWithFailover(candidates, candidateIndex + 1, chatPayload, stream, res, req, parsedUrl, start, routeModel, onFinish, 502, err.message, candidate.model);
        } else {
            sendJSONError(res, 502, 'Upstream connection error: ' + err.message, 'upstream_connection_error', 502);
            logRequest('POST', parsedUrl.pathname, 502, Date.now() - start, routeModel, candidate.model, err.message);
            onFinish();
        }
    });

    upstreamReq.on('timeout', () => {
        upstreamReq.destroy(new Error('Request timeout'));
    });

    upstreamReq.write(payloadStr);
    upstreamReq.end();
}

const server = http.createServer((req, res) => {
    res.on('error', (err) => {
        console.error('[Proxy] Client response error:', err.message);
    });
    req.on('error', (err) => {
        console.error('[Proxy] Client request error:', err.message);
    });

    const parsedUrl = new URL(req.url, 'http://127.0.0.1');
    const start = Date.now();

    // CORS preflight
    if (req.method === 'OPTIONS') {
        res.writeHead(200, {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '86400'
        });
        res.end();
        return;
    }

    // GET /health
    if (req.method === 'GET' && parsedUrl.pathname === '/health') {
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        });
        res.end(JSON.stringify({ status: 'ok' }));
        return;
    }

    // GET /v1/models
    if (req.method === 'GET' && parsedUrl.pathname === '/v1/models') {
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        });
        res.end(JSON.stringify({
            object: 'list',
            data: [
                {
                    id: ROUTE_MODEL,
                    object: 'model',
                    created: Math.floor(Date.now() / 1000) - 86400 * 30, // 30 days ago
                    owned_by: 'custom'
                }
            ]
        }));
        logRequest('GET', parsedUrl.pathname, 200, Date.now() - start, ROUTE_MODEL, UPSTREAM_MODEL);
        return;
    }

    // POST /v1/responses
    if (req.method === 'POST' && parsedUrl.pathname === '/v1/responses') {
        let bodyData = '';
        req.on('data', chunk => {
            bodyData += chunk;
        });

        req.on('end', async () => {
            let reqBody;
            try {
                reqBody = JSON.parse(bodyData || '{}');
            } catch (err) {
                sendJSONError(res, 400, 'Invalid JSON body: ' + err.message, 'invalid_request_error', 400);
                logRequest('POST', parsedUrl.pathname, 400, Date.now() - start, ROUTE_MODEL, UPSTREAM_MODEL, 'Invalid JSON body');
                return;
            }

            const input = reqBody.input;
            if (!input) {
                sendJSONError(res, 400, 'Missing required parameter: input', 'invalid_request_error', 400);
                logRequest('POST', parsedUrl.pathname, 400, Date.now() - start, ROUTE_MODEL, UPSTREAM_MODEL, 'Missing parameter: input');
                return;
            }

            const release = await acquirePermit(req, res, start);
            if (!release) {
                return;
            }

            // Translate Responses "input" to Chat Completions "messages"
	            let messages = [];
            if (typeof reqBody.instructions === 'string' && reqBody.instructions.trim()) {
                messages.push({ role: 'system', content: reqBody.instructions.trim() });
            }
            if (typeof input === 'string') {
                messages.push({ role: 'user', content: input });
            } else if (Array.isArray(input)) {
                for (const item of input) {
	                    if (typeof item === 'string') {
	                        messages.push({ role: 'user', content: item });
	                    } else if (item && typeof item === 'object') {
	                        if (item.type === 'function_call_output') {
	                            const toolOutput = typeof item.output === 'string' ? item.output : JSON.stringify(item.output ?? '');
	                            rememberToolResult(item.call_id, toolOutput);
	                            messages.push(makeToolMessage(item.call_id, toolOutput));
	                            continue;
	                        }
	                        if (item.type === 'function_call') {
	                            const callId = item.call_id || item.id;
	                            const assistantToolMessage = {
	                                role: 'assistant',
	                                content: null,
	                                tool_calls: [
	                                    {
	                                        id: callId,
	                                        type: 'function',
	                                        function: {
	                                            name: item.name,
	                                            arguments: item.arguments || ''
	                                        }
	                                    }
	                                ]
	                            };
	                            const reasoningContent = item.reasoning_content || reasoningContentByCallId.get(callId);
	                            if (reasoningContent) {
	                                assistantToolMessage.reasoning_content = reasoningContent;
	                            }
	                            messages.push(assistantToolMessage);
	                            continue;
	                        }
	                        let role = item.role || 'user';
                        if (role === 'developer') {
                            role = 'system';
                        }
                        let content = item.content || '';
                        if (Array.isArray(content)) {
                            content = content.map(part => {
                                if (part && typeof part === 'object') {
                                    const newPart = { ...part };
                                    if (newPart.type === 'input_text') {
                                        newPart.type = 'text';
                                    }
                                    if (newPart.type === 'output_text') {
                                        newPart.type = 'text';
                                    }
                                    if (newPart.input_text !== undefined) {
                                        if (newPart.text === undefined) {
                                            newPart.text = newPart.input_text;
                                        }
                                        delete newPart.input_text;
                                    }
                                    // Also clean up any other Responses-only fields
                                    delete newPart.input_audio;
                                    delete newPart.input_image;
                                    return newPart;
                                }
                                return part;
                            });
                            // Flatten content arrays with single text part to plain string
                            if (content.length === 1 && content[0].type === 'text' && typeof content[0].text === 'string') {
                                content = content[0].text;
                            }
                        }
                        const msgObj = { role, content };
                        if (role === 'assistant') {
                            const reasoningContent = item.reasoning_content || (item.id && reasoningContentByCallId.get(item.id));
                            if (reasoningContent) {
                                msgObj.reasoning_content = reasoningContent;
                            }
                        }
                        messages.push(msgObj);
                    }
                }
	            } else {
	                sendJSONError(res, 400, 'Parameter input must be a string or array', 'invalid_request_error', 400);
	                logRequest('POST', parsedUrl.pathname, 400, Date.now() - start, ROUTE_MODEL, UPSTREAM_MODEL, 'Invalid input type');
	                return;
	            }

	            const repairedMessages = repairToolCallMessageOrder(messages);
	            if (repairedMessages.error) {
	                sendJSONError(res, 400, repairedMessages.error, 'invalid_request_error', 400);
	                logRequest('POST', parsedUrl.pathname, 400, Date.now() - start, ROUTE_MODEL, UPSTREAM_MODEL, repairedMessages.error);
	                return;
	            }
	            messages = repairedMessages.messages;

	            // Construct Chat Completions Payload
            const stream = !!reqBody.stream;
            const chatPayload = {
                model: UPSTREAM_MODEL,
                messages: messages,
                stream: stream
            };

            // When streaming, request usage info for proper termination
            if (stream) {
                chatPayload.stream_options = { include_usage: true };
            }

            // Optional mappings
            if (reqBody.temperature !== undefined) chatPayload.temperature = reqBody.temperature;
            if (reqBody.max_output_tokens !== undefined) chatPayload.max_tokens = reqBody.max_output_tokens;
            else if (reqBody.max_tokens !== undefined) chatPayload.max_tokens = reqBody.max_tokens;
            if (Array.isArray(reqBody.tools)) {
                const tools = reqBody.tools.map(normalizeResponsesTool).filter(Boolean);
                if (tools.length) {
                    chatPayload.tools = tools;
                }
            }
            const normalizedToolChoice = normalizeToolChoice(reqBody.tool_choice);
            // 思考模式映射: Responses 的 reasoning.effort → Chat Completions reasoning_effort
            if (reqBody.reasoning?.effort) {
                let effort = reqBody.reasoning.effort;
                if (effort === 'xhigh') {
                    effort = 'high';
                }
                chatPayload.reasoning_effort = effort;
                console.log('[Proxy] reasoning_effort=' + chatPayload.reasoning_effort);
            }

            if (normalizedToolChoice !== undefined) {
                chatPayload.tool_choice = normalizedToolChoice;
            }

            // 未识别参数透传（如 xhigh、thinking_budget 等自定义字段），需过滤 Responses API 专属参数
            const knownKeys = ['input','model','stream','tools','tool_choice','temperature','max_output_tokens','max_tokens','instructions','metadata','reasoning','messages'];
            const excludeKeys = ['store', 'include', 'prompt_cache_key', 'text', 'client_metadata'];
            const extraKeys = [];
            for (const key of Object.keys(reqBody)) {
                if (!knownKeys.includes(key) && !excludeKeys.includes(key)) {
                    chatPayload[key] = reqBody[key];
                    extraKeys.push(key);
                }
            }
            if (extraKeys.length > 0) {
                console.log('[Proxy] extra_passthrough_params=' + JSON.stringify(extraKeys));
            }

            // Build candidates array
            const candidates = [];
            candidates.push({
                id: currentConfig.activeProviderId || 'primary',
                url: currentConfig.upstreamBaseUrl,
                key: currentConfig.upstreamApiKey,
                model: currentConfig.upstreamModel
            });
            if (currentConfig.failoverEnabled !== false && Array.isArray(currentConfig.providers)) {
                for (const p of currentConfig.providers) {
                    candidates.push({
                        id: p.providerID || 'backup',
                        url: p.url,
                        key: p.key,
                        model: p.model
                    });
                }
            }
            dispatchWithFailover(candidates, 0, chatPayload, stream, res, req, parsedUrl, start, currentConfig.routeModel, release);
        });
    } else {
        // Not Found
        sendJSONError(res, 404, `Endpoint ${req.method} ${parsedUrl.pathname} not found`, 'invalid_request_error', 404);
    }
});

let listenRetries = 0;
const MAX_LISTEN_RETRIES = 5;

server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
        if (listenRetries < MAX_LISTEN_RETRIES) {
            listenRetries++;
            console.warn(`[Proxy] 端口 ${PORT} 被占用，将在 500ms 后重试... (第 ${listenRetries}/${MAX_LISTEN_RETRIES} 次尝试)`);
            setTimeout(() => {
                server.close();
                server.listen(PORT, '127.0.0.1');
            }, 500);
        } else {
            console.error(`[Proxy] 绑定端口 ${PORT} 失败，已重试 ${MAX_LISTEN_RETRIES} 次，端口已被其他进程占用。`);
            process.exit(1);
        }
    } else {
        console.error('[Proxy] 服务器发生错误:', err.message);
        process.exit(1);
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[Proxy] Server listening on http://127.0.0.1:${PORT}`);
});
