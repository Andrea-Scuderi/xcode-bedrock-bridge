# swift-open-llm-proxy — Technical Specification

Vapor HTTP proxy that bridges **Xcode 26.3 AI features** to **Amazon Bedrock** (Claude models).
Last updated: February 2026.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Xcode Integration Modes](#2-xcode-integration-modes)
3. [OpenAI-Compatible API (Xcode Intelligence)](#3-openai-compatible-api-xcode-intelligence)
4. [Anthropic Messages API (Xcode Coding Agent)](#4-anthropic-messages-api-xcode-coding-agent)
5. [Amazon Bedrock Converse API](#5-amazon-bedrock-converse-api)
6. [Model IDs & Mapping](#6-model-ids--mapping)
7. [Authentication & Configuration](#7-authentication--configuration)
8. [Error Handling](#8-error-handling)
9. [Configuration Reference](#9-configuration-reference)
10. [References](#10-references)

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    Xcode 26.3                                            │
│                                                                          │
│  ┌───────────────────┐     ┌─────────────────────────┐                   │
│  │ Xcode Intelligence│     │   Claude Coding Agent   │                   │
│  │ (code completion, │     │ (agentic coding, tools, │                   │
│  │  inline chat)     │     │  file read/write/run)   │                   │
│  └────────┬──────────┘     └────────────┬────────────┘                   │
│           │ OpenAI format               │ Anthropic format               │   
│           │ /v1/chat/completions        │ /v1/messages                   │
│           │ /v1/models                  │ /v1/messages/count_tokens      │
└───────────┼─────────────────────────────┼────────────────────────────────┘
            │                             │
            ▼                             ▼
┌───────────────────────────────────────────────────────┐
│              swift-open-llm-proxy (Vapor)             │
│                                                       │
│  APIKeyMiddleware   ·   ModelMapper                   │
│                                                       │
│  ChatController         MessagesController            │
│  RequestTranslator      AnthropicRequestTranslator    │
│  ResponseTranslator     AnthropicResponseTranslator   │
│                                                       │
│                   BedrockService (actor)              │
│                   converse() / converseStream()       │
│                   converseStreamRaw()                 │
│                   listFoundationModels()              │
└───────────────────────────────┬───────────────────────┘
                                │ AWS SigV4 (Soto)
                                ▼
                   ┌────────────────────────┐
                   │    Amazon Bedrock      │
                   │   Converse API         │
                   │  (Claude models)       │
                   └────────────────────────┘
```

---

## 2. Xcode Integration Modes

Xcode 26.3 exposes **two separate AI integration points** that use different wire formats.

### 2.1 Xcode Intelligence (Custom Provider)

Accessed via **Settings → Intelligence → Add Model Provider**.

- Uses the **OpenAI Chat Completions API** format
- Base URL is entered by the user (Xcode appends `/v1` automatically — do **not** include `/v1` in the URL)
- API key is sent as `x-api-key` header or `Authorization: Bearer <key>`
- Endpoints called:
  - `GET /v1/models` — model discovery
  - `POST /v1/chat/completions` — inference (streaming and non-streaming)

### 2.2 Xcode Coding Agent (Claude Agent)

Accessed via the **agentic coding panel** introduced in Xcode 26.3.

- Uses the **Anthropic Messages API** format (not OpenAI)
- Configured via environment variables in:
  ```
  ~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/settings.json
  ```
- The bundled agent binary lives at:
  ```
  ~/Library/Developer/Xcode/CodingAssistant/Agents/Versions/26.3/
  ```
  and accepts the same env vars as Claude Code CLI.
- Endpoints called:
  - `POST /v1/messages` — inference (streaming and non-streaming, with tool use)
  - `POST /v1/messages/count_tokens` — token preflight before large requests

**Settings file example:**
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8080",
    "ANTHROPIC_AUTH_TOKEN": "any-placeholder-value"
  }
}
```

To bypass Xcode's auth requirement when using a third-party endpoint:
```bash
defaults write com.apple.dt.Xcode IDEChatClaudeAgentAPIKeyOverride ' '
```

---

## 3. OpenAI-Compatible API (Xcode Intelligence)

### 3.1 GET /v1/models

Returns the list of available models in OpenAI format.

**Dynamic vs. static behaviour:**

| Condition | Behaviour |
|---|---|
| Real AWS credentials (default/profile) | Calls `Bedrock.listFoundationModels()` — returns all models available in the region |
| Bedrock API key (`BEDROCK_API_KEY`) | Management API not supported with Bearer auth → static fallback |
| Network/auth error from management API | Warning logged, static fallback returned |
| No `BedrockService` (unit tests) | Static fallback immediately |

`owned_by` is derived from the model ID prefix: `anthropic.*` / `us.anthropic.*` → `"anthropic"`, `amazon.*` / `us.amazon.*` → `"amazon"`, etc.

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
      "object": "model",
      "created": 1234567890,
      "owned_by": "anthropic"
    },
    {
      "id": "us.amazon.nova-pro-v1:0",
      "object": "model",
      "created": 1234567890,
      "owned_by": "amazon"
    }
  ]
}
```

### 3.2 POST /v1/chat/completions

**Request:**
```json
{
  "model": "claude-sonnet-4-5",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello"}
  ],
  "max_tokens": 4096,
  "temperature": 0.7,
  "top_p": 0.9,
  "stream": false,
  "stop": ["END"]
}
```

> **Note:** Xcode sends `content` as an **array of content-part objects** rather than a plain string:
> ```json
> "content": [{"type": "text", "text": "Hello"}]
> ```
> The proxy normalises both forms to a plain string before forwarding.

**Non-streaming response:**
```json
{
  "id": "chatcmpl-<uuid>",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "claude-sonnet-4-5",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "Hi there!"},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 12,
    "completion_tokens": 5,
    "total_tokens": 17
  }
}
```

**Streaming response** — Server-Sent Events (SSE), `Content-Type: text/event-stream`:
```
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"...","choices":[{"index":0,"delta":{"role":"assistant","content":null},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"...","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"...","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

Required SSE response headers:
```
Content-Type: text/event-stream
Cache-Control: no-cache
X-Accel-Buffering: no
```

---

## 4. Anthropic Messages API (Xcode Coding Agent)

### 4.1 POST /v1/messages

**Request:**
```json
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 8096,
  "system": "You are a helpful coding assistant.",
  "messages": [
    {
      "role": "user",
      "content": [{"type": "text", "text": "Read file main.swift"}]
    },
    {
      "role": "assistant",
      "content": [
        {"type": "text", "text": "I'll read that file."},
        {
          "type": "tool_use",
          "id": "toolu_01",
          "name": "read_file",
          "input": {"path": "main.swift"}
        }
      ]
    },
    {
      "role": "user",
      "content": [
        {
          "type": "tool_result",
          "tool_use_id": "toolu_01",
          "content": "import Vapor\n..."
        }
      ]
    }
  ],
  "tools": [
    {
      "name": "read_file",
      "description": "Read a file from disk",
      "input_schema": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "File path"}
        },
        "required": ["path"]
      }
    }
  ],
  "tool_choice": {"type": "auto"},
  "stream": true,
  "temperature": 1.0
}
```

Key differences from OpenAI format:
- `max_tokens` is **required** (not optional)
- `system` is a top-level field (not a message with `role: "system"`)
- `system` can be a string or an array of `{"type":"text","text":"..."}` blocks
- `content` is always an **array of typed blocks**
- Tool use is native: `tool_use` blocks in assistant messages, `tool_result` blocks in user messages

**Non-streaming response:**
```json
{
  "id": "msg_<id>",
  "type": "message",
  "role": "assistant",
  "content": [
    {"type": "text", "text": "Here is the file content..."},
    {
      "type": "tool_use",
      "id": "toolu_02",
      "name": "write_file",
      "input": {"path": "out.swift", "content": "..."}
    }
  ],
  "model": "claude-sonnet-4-5-20250929",
  "stop_reason": "tool_use",
  "usage": {
    "input_tokens": 245,
    "output_tokens": 83
  }
}
```

`stop_reason` values: `"end_turn"` | `"tool_use"` | `"max_tokens"` | `"stop_sequence"`

**Streaming SSE event sequence:**
```
event: message_start
data: {"type":"message_start","message":{"id":"msg_...","type":"message","role":"assistant","content":[],"model":"...","stop_reason":null,"usage":{"input_tokens":0,"output_tokens":0}}}

event: ping
data: {"type":"ping"}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01","name":"read_file","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"main.swift\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":47}}

event: message_stop
data: {"type":"message_stop"}
```

### 4.2 POST /v1/messages/count_tokens

Called by the agent as a preflight before large requests to estimate context usage.

**Request:** same fields as `/v1/messages` minus `stream` and `max_tokens`

**Response:**
```json
{
  "input_tokens": 1247
}
```

> Bedrock has no native count-tokens API. The proxy returns a character-based estimate (~4 chars per token).

---

## 5. Amazon Bedrock Converse API

The proxy uses two Soto packages:

- **`SotoBedrockRuntime`** — inference plane: `BedrockRuntime.converse()` and `BedrockRuntime.converseStream()`
- **`SotoBedrock`** — management plane: `Bedrock.listFoundationModels()` (used by `GET /v1/models`)

Both share a single `AWSClient` instance inside `BedrockService`.

### 5.1 Key Soto Types

| Soto Type | Description |
|---|---|
| `BedrockRuntime.ConverseRequest` | Non-streaming request (messages, system, inferenceConfig, toolConfig) |
| `BedrockRuntime.ConverseStreamRequest` | Streaming request (same fields) |
| `BedrockRuntime.ConverseResponse` | Non-streaming response (output, stopReason, usage) |
| `BedrockRuntime.ConverseOutput` | Struct with optional `message: Message?` |
| `BedrockRuntime.Message` | role + content array |
| `BedrockRuntime.ContentBlock` | Enum: `.text(String)`, `.toolUse(ToolUseBlock)`, `.toolResult(ToolResultBlock)` |
| `BedrockRuntime.SystemContentBlock` | Enum: `.text(String)` |
| `BedrockRuntime.InferenceConfiguration` | `maxTokens`, `temperature: Float?`, `topP: Float?` |
| `BedrockRuntime.ToolConfiguration` | `tools: [Tool]`, `toolChoice: ToolChoice?` |
| `BedrockRuntime.Tool` | Enum: `.toolSpec(ToolSpecification)` |
| `BedrockRuntime.ToolSpecification` | `name`, `description?`, `inputSchema: ToolInputSchema` |
| `BedrockRuntime.ToolInputSchema` | `json: AWSDocument?` — JSON Schema as `AWSDocument` |
| `BedrockRuntime.ToolUseBlock` | `toolUseId`, `name`, `input: AWSDocument` |
| `BedrockRuntime.ToolResultBlock` | `toolUseId`, `content: [ToolResultContentBlock]` |
| `BedrockRuntime.ToolResultContentBlock` | Enum: `.text(String)`, `.json(AWSDocument)`, ... |
| `BedrockRuntime.ToolChoice` | Enum: `.auto(AutoToolChoice)`, `.any(AnyToolChoice)`, `.tool(SpecificToolChoice)` |
| `BedrockRuntime.StopReason` | Enum: `.endTurn`, `.maxTokens`, `.toolUse`, `.stopSequence`, ... |
| `BedrockRuntime.TokenUsage` | `inputTokens: Int`, `outputTokens: Int`, `totalTokens: Int` |
| `AWSDocument` (SotoCore) | Recursive JSON enum: `.string`, `.integer`, `.double`, `.boolean`, `.array`, `.map`, `.null` |

### 5.2 Streaming Event Types (`ConverseStreamOutput`)

| Case | Associated Type | Contains |
|---|---|---|
| `.messageStart` | `MessageStartEvent` | `role` |
| `.contentBlockStart` | `ContentBlockStartEvent` | `contentBlockIndex`, `start: ContentBlockStart` |
| `.contentBlockDelta` | `ContentBlockDeltaEvent` | `contentBlockIndex`, `delta: ContentBlockDelta` |
| `.contentBlockStop` | `ContentBlockStopEvent` | `contentBlockIndex` |
| `.messageStop` | `MessageStopEvent` | `stopReason: StopReason` (non-optional) |
| `.metadata` | `ConverseStreamMetadataEvent` | `usage: TokenUsage` (non-optional), `metrics` |

`ContentBlockDelta` cases:
- `.text(String)` — text delta
- `.toolUse(ToolUseBlockDelta)` — `input: String` (raw JSON fragment for tool input)

`ContentBlockStart` cases:
- `.toolUse(ToolUseBlockStart)` — `toolUseId: String`, `name: String`

### 5.3 Translation Map

#### Request: Anthropic → Bedrock

| Anthropic field | Bedrock field |
|---|---|
| `system: String` | `[SystemContentBlock.text(s)]` |
| `system: [{type:"text",text:s}]` | `[SystemContentBlock.text(s)]` |
| `messages[].content[{type:"text"}]` | `ContentBlock.text(s)` |
| `messages[].content[{type:"tool_use"}]` | `ContentBlock.toolUse(ToolUseBlock)` |
| `messages[].content[{type:"tool_result"}]` | `ContentBlock.toolResult(ToolResultBlock)` |
| `tools[].input_schema` (JSONValue) | `ToolInputSchema(json: AWSDocument)` |
| `tool_choice.type == "auto"` | `ToolChoice.auto(AutoToolChoice())` |
| `tool_choice.type == "any"` | `ToolChoice.any(AnyToolChoice())` |
| `tool_choice.type == "tool"` | `ToolChoice.tool(SpecificToolChoice(name:))` |
| `tool_choice.type == "none"` | omit `toolConfig` entirely |
| `max_tokens`, `temperature`, `top_p` | `InferenceConfiguration` |

#### Response: Bedrock → Anthropic

| Bedrock field | Anthropic field |
|---|---|
| `ConverseOutput.message.content[.text(s)]` | `content[{type:"text",text:s}]` |
| `ConverseOutput.message.content[.toolUse(b)]` | `content[{type:"tool_use",id:...,name:...,input:...}]` |
| `stopReason == .endTurn` | `"end_turn"` |
| `stopReason == .maxTokens` | `"max_tokens"` |
| `stopReason == .toolUse` | `"tool_use"` |
| `usage.inputTokens` / `.outputTokens` | `usage.input_tokens` / `.output_tokens` |

---

## 6. Model IDs & Mapping

The proxy supports both **Anthropic Claude** and **Amazon Nova** models. All static fallback IDs use **cross-region inference profiles** (`us.` prefix) for on-demand throughput without provisioning. Bare `anthropic.*` IDs for older models (Claude 3 Opus, Claude 3 Sonnet) no longer support on-demand throughput.

### Static Fallback Models (February 2026)

When the live `listFoundationModels` call is unavailable, the following models are returned.

#### Anthropic Claude

| Display Name | Inference Profile ID |
|---|---|
| Claude Sonnet 4.6 | `us.anthropic.claude-sonnet-4-6` |
| Claude Sonnet 4.5 | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| Claude Sonnet 4 | `us.anthropic.claude-sonnet-4-20250514-v1:0` |
| Claude Haiku 4.5 | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| Claude Opus 4.6 | `us.anthropic.claude-opus-4-6-v1` |
| Claude Opus 4.5 | `us.anthropic.claude-opus-4-5-20251101-v1:0` |
| Claude Opus 4.1 | `us.anthropic.claude-opus-4-1-20250805-v1:0` |
| Claude 3.7 Sonnet | `us.anthropic.claude-3-7-sonnet-20250219-v1:0` |
| Claude 3.5 Sonnet v2 | `us.anthropic.claude-3-5-sonnet-20241022-v2:0` |
| Claude 3.5 Sonnet | `us.anthropic.claude-3-5-sonnet-20240620-v1:0` |
| Claude 3.5 Haiku | `us.anthropic.claude-3-5-haiku-20241022-v1:0` |
| Claude 3 Opus | `us.anthropic.claude-3-opus-20240229-v1:0` |
| Claude 3 Sonnet | `us.anthropic.claude-3-sonnet-20240229-v1:0` |
| Claude 3 Haiku | `us.anthropic.claude-3-haiku-20240307-v1:0` |

#### Amazon Nova

| Display Name | Inference Profile ID |
|---|---|
| Amazon Nova Pro | `us.amazon.nova-pro-v1:0` |
| Amazon Nova Lite | `us.amazon.nova-lite-v1:0` |
| Amazon Nova Micro | `us.amazon.nova-micro-v1:0` |

> **Note:** `us.` inference profiles are for `us-east-1` / `us-west-2`. For EU or AP regions, use the `eu.` or `ap.` prefix respectively.

### Alias Mapping

| Alias (sent by client) | Bedrock Inference Profile ID |
|---|---|
| `gpt-4`, `gpt-4o`, `gpt-4-turbo` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `gpt-3.5-turbo` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `claude-sonnet-4-6` | `us.anthropic.claude-sonnet-4-6` |
| `claude-sonnet-4-5` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `claude-sonnet-4` | `us.anthropic.claude-sonnet-4-20250514-v1:0` |
| `claude-haiku-4-5` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `claude-opus-4-6` | `us.anthropic.claude-opus-4-6-v1` |
| `claude-opus-4-5` | `us.anthropic.claude-opus-4-5-20251101-v1:0` |
| `claude-opus-4-1` | `us.anthropic.claude-opus-4-1-20250805-v1:0` |
| `claude-3-7-sonnet` | `us.anthropic.claude-3-7-sonnet-20250219-v1:0` |
| `claude-3-5-sonnet`, `claude-3-5-sonnet-v2` | `us.anthropic.claude-3-5-sonnet-20241022-v2:0` |
| `claude-3-5-haiku` | `us.anthropic.claude-3-5-haiku-20241022-v1:0` |
| `claude-3-opus` | `us.anthropic.claude-3-opus-20240229-v1:0` |
| `claude-3-sonnet` | `us.anthropic.claude-3-sonnet-20240229-v1:0` |
| `claude-3-haiku` | `us.anthropic.claude-3-haiku-20240307-v1:0` |
| `nova-pro` | `us.amazon.nova-pro-v1:0` |
| `nova-lite` | `us.amazon.nova-lite-v1:0` |
| `nova-micro` | `us.amazon.nova-micro-v1:0` |
| IDs containing `anthropic.` or `amazon.` | passed through as-is |

---

## 7. Authentication & Configuration

### Bedrock API Key (Bearer Token)

When `BEDROCK_API_KEY` is set, the proxy authenticates to Bedrock using a Bearer token instead of AWS SigV4 signing. The key is sent as `Authorization: Bearer <key>` on every request, and the SigV4 signing step is skipped entirely (empty credentials cause Soto's `signHeaders` to return early).

`BEDROCK_API_KEY` takes precedence over `PROFILE` and the default AWS credential chain.

### AWS Credentials

When `BEDROCK_API_KEY` is **not** set, Soto's `AWSClient` resolves credentials in this order:
1. `PROFILE` env var → `~/.aws/credentials` named profile
2. `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` env vars
3. `~/.aws/credentials` default profile
4. EC2/ECS instance metadata (IAM role)

### Proxy API Key (Xcode Intelligence)

When `PROXY_API_KEY` is set, all OpenAI-format requests (`/v1/models`, `/v1/chat/completions`) require authentication via either:
- `x-api-key: <key>` header
- `Authorization: Bearer <key>` header

The Anthropic-format endpoints (`/v1/messages`, `/v1/messages/count_tokens`) are **not** protected by the proxy key because the Claude Agent authenticates independently via `ANTHROPIC_AUTH_TOKEN`.

### Xcode Intelligence Setup

1. Xcode → Settings → Intelligence → Add Model Provider → Internet Hosted
2. Base URL: `http://localhost:8080` (no `/v1` suffix — Xcode appends it)
3. API Key: value of `PROXY_API_KEY`
4. API Key Header: `x-api-key`

### Xcode Coding Agent Setup

```json
// ~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/settings.json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8080",
    "ANTHROPIC_AUTH_TOKEN": "placeholder"
  }
}
```

---

## 8. Error Handling

### HTTP Status Mapping

| Bedrock / Soto Error | HTTP Status |
|---|---|
| `ThrottlingException` | 429 Too Many Requests |
| `ValidationException` | 400 Bad Request |
| `AccessDeniedException` | 401 Unauthorized |
| `ResourceNotFoundException` / `ModelNotFoundException` | 404 Not Found |
| `ServiceUnavailableException` | 503 Service Unavailable |
| All others | 500 Internal Server Error |

### Common Errors

**`ResourceNotFoundException: Model use case details have not been submitted`**
→ Go to AWS Bedrock Console → Model Access → request access for the specific model.

**`ValidationException: Invocation of model ID ... with on-demand throughput isn't supported`**
→ The model requires a cross-region inference profile. Use the `us.anthropic.*` ID instead of `anthropic.*`.

**`AccessDeniedException`**
→ AWS credentials lack `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` permissions.

### Streaming Error Recovery

For streaming responses, errors that occur **before** the first SSE byte is sent are returned as a proper HTTP error (status code + JSON body). Errors that occur **mid-stream** (after `200 OK` is committed) are sent as a final SSE error event:

OpenAI format:
```
event: error
data: {"error":"<message>"}
```

Anthropic format:
```
event: error
data: {"type":"error","error":{"type":"api_error","message":"<message>"}}
```

---

## 9. Configuration Reference

| Environment Variable | Required | Default | Description |
|---|---|---|---|
| `BEDROCK_API_KEY` | No† | — | Bedrock API key; sent as `Authorization: Bearer <key>`. Overrides all AWS credential options. |
| `AWS_ACCESS_KEY_ID` | No* | — | AWS access key (*or use `PROFILE` or `BEDROCK_API_KEY`) |
| `AWS_SECRET_ACCESS_KEY` | No* | — | AWS secret key |
| `AWS_SESSION_TOKEN` | No | — | For temporary / assumed-role credentials |
| `AWS_REGION` | No | `us-east-1` | Bedrock service region |
| `PROFILE` | No | — | Named profile in `~/.aws/credentials` |
| `DEFAULT_BEDROCK_MODEL` | No | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Fallback model when alias not found |
| `PROXY_API_KEY` | No | — | Key required on `/v1/models` and `/v1/chat/completions`. Auth disabled if unset. |
| `PORT` | No | `8080` | HTTP listen port |
| `LOG_LEVEL` | No | `info` | Vapor log level (`debug`, `info`, `warning`, `error`) |

† Setting `BEDROCK_API_KEY` disables SigV4 signing and all `AWS_*` credential env vars are ignored.

**Run (AWS credentials):**
```bash
export AWS_REGION=us-east-1
export PROFILE=bedrock-dev          # or use AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
export PROXY_API_KEY=my-secret-key  # optional
export LOG_LEVEL=debug              # shows raw Xcode payloads
swift run Run
```

**Run (Bedrock API key):**
```bash
export AWS_REGION=us-east-1
export BEDROCK_API_KEY=your-bedrock-api-key
export PROXY_API_KEY=my-secret-key  # optional
swift run Run
```

---

## 10. References

### Xcode 26.3 AI Features

- [Xcode 26.3 unlocks the power of agentic coding — Apple Newsroom](https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/)
- [Xcode 26.3 Brings Integrated Agentic Coding for Anthropic Claude Agent and OpenAI Codex — InfoQ](https://www.infoq.com/news/2026/02/xcode-26-3-agentic-coding/)
- [Xcode 26.3 + Claude Agent: Model Swapping, MCP, Skills, and Adaptive Configuration — fatbobman.com](https://fatbobman.com/en/posts/xcode-263-claude)
- [Xcode Claude Code integration with third-party APIs — GitHub Gist](https://gist.github.com/zoltan-magyar/be846eb36cf5ee33c882ef5f932b754b)
- [How can I use private AI agents in Xcode 26.3? — Apple Developer Forums](https://developer.apple.com/forums/thread/814587)
- [Use any OpenAI-compatible LLM provider in Xcode 26 — Carlo Zottmann](https://zottmann.org/2025/06/11/use-any-openaicompatible-llm-provider.html)
- [Use Custom Models in Xcode 26 Intelligence — Wendy Liga](https://wendyliga.com/blog/xcode-26-custom-model/)
- [ProxyPilot — Xcode 26.3 Agent Mode technical details](https://micah.chat/proxypilot)
- [Xcode Integration — OpenRouter documentation](https://openrouter.ai/docs/guides/community/xcode)

### Amazon Bedrock

- [Supported foundation models in Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html)
- [Supported Regions and models for inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html)
- [Anthropic Claude models — Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-claude.html)
- [Generate responses using OpenAI APIs — Amazon Bedrock (Mantle)](https://docs.aws.amazon.com/bedrock/latest/userguide/bedrock-mantle.html)
- [AWS Samples: Bedrock Access Gateway (reference implementation)](https://github.com/aws-samples/bedrock-access-gateway)

### Anthropic API

- [Anthropic Messages API reference](https://platform.claude.com/docs/en/api/messages)
- [Claude Code LLM Gateway / ANTHROPIC_BASE_URL documentation](https://platform.claude.com/docs/en/api/messages)

### Swift / Vapor / Soto

- [Vapor web framework](https://github.com/vapor/vapor)
- [Soto — AWS SDK for Swift](https://github.com/soto-project/soto)
- [SotoBedrockRuntime shapes source](https://github.com/soto-project/soto/blob/main/Sources/Soto/Services/BedrockRuntime/BedrockRuntime_shapes.swift)
- [SotoBedrock shapes source](https://github.com/soto-project/soto/blob/main/Sources/Soto/Services/Bedrock/Bedrock_shapes.swift)
- [SotoCore AWSDocument type](https://github.com/soto-project/soto-core/blob/main/Sources/SotoCore/AWSShapes/Document.swift)
