# swift-open-llm-proxy

> **Work in Progress** — This project is under active development. APIs, configuration, and behaviour may change without notice.

A local Vapor proxy server that connects **Xcode 26.3 AI features** to **Amazon Bedrock** Claude models.

Xcode speaks OpenAI and Anthropic API formats; Bedrock uses its own Converse API with AWS SigV4 auth. This proxy handles the translation transparently so you can use any Claude model on Bedrock as a backend for both Xcode Intelligence (code completions) and the Xcode Coding Agent (agentic coding).

---

## How it works

```
Xcode Intelligence          ──► POST /v1/chat/completions     ─┐
(code completion, chat)         GET  /v1/models                │
                                                               │  swift-open-llm-proxy
Xcode Coding Agent          ──► POST /v1/messages             ─┤  (Vapor + Soto)
(file read/write/run tools)     POST /v1/messages/count_tokens │
                                                               │
                                                               └──► AWS Bedrock
                                                                    Converse API
                                                                    (Claude models)
```

Both Xcode integration modes are covered:

| Xcode feature | Wire format | Endpoints |
|---|---|---|
| **Xcode Intelligence** — inline completions, editor chat | OpenAI | `GET /v1/models`, `POST /v1/chat/completions` |
| **Xcode Coding Agent** — agentic coding with tools | Anthropic Messages | `POST /v1/messages`, `POST /v1/messages/count_tokens` |

---

## Requirements

- macOS 15+
- Swift 6
- Xcode 26.3+
- An AWS account with [Bedrock model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) enabled for the Claude models you want to use

---

## Quick start

### 1. Clone and build

```bash
git clone https://github.com/yourname/swift-open-llm-proxy
cd swift-open-llm-proxy
swift build -c release
```

### 2. Set up AWS credentials

**Option A — AWS profile** (recommended):
```bash
export PROFILE=your-bedrock-profile   # reads from ~/.aws/credentials
```

**Option B — environment variables:**
```bash
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...          # only for temporary credentials
```

The IAM user/role needs these permissions:
```json
{
  "Effect": "Allow",
  "Action": [
    "bedrock:InvokeModel",
    "bedrock:InvokeModelWithResponseStream",
    "bedrock:ListFoundationModels"
  ],
  "Resource": "*"
}
```

> `bedrock:ListFoundationModels` is only needed for the live model list on `GET /v1/models`. If it is missing the endpoint falls back to the built-in static list automatically.

### 3. Run

```bash
export AWS_REGION=us-east-1
export PROXY_API_KEY=my-secret-key    # optional — enables auth on OpenAI endpoints
swift run -c release Run
```

The server listens on `http://localhost:8080` by default.

### 4. Verify

```bash
# List models
curl -H "x-api-key: my-secret-key" http://localhost:8080/v1/models

# Non-streaming chat
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "x-api-key: my-secret-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 64
  }'

# Streaming chat
curl -N -X POST http://localhost:8080/v1/chat/completions \
  -H "x-api-key: my-secret-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "messages": [{"role": "user", "content": "Count to 5"}],
    "max_tokens": 64,
    "stream": true
  }'
```

---

## Xcode setup

### Xcode Intelligence (code completions & chat)

1. Open **Xcode → Settings → Intelligence**
2. Click **Add Model Provider** → choose **Internet Hosted**
3. Fill in:
   - **Base URL:** `http://localhost:8080` *(do not add `/v1` — Xcode appends it)*
   - **API Key:** value of `PROXY_API_KEY` (or leave blank if auth is disabled)
   - **API Key Header:** `x-api-key`
4. Select a model from the list (e.g. `us.anthropic.claude-sonnet-4-5-20250929-v1:0` or `us.amazon.nova-pro-v1:0`)

### Xcode Coding Agent

The Claude Agent uses the Anthropic API format and reads its endpoint from a config file:

```bash
mkdir -p ~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig
```

Create or edit `settings.json` in that directory:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8080",
    "ANTHROPIC_AUTH_TOKEN": "placeholder"
  }
}
```

If Xcode blocks the connection with an auth error, run this once:
```bash
defaults write com.apple.dt.Xcode IDEChatClaudeAgentAPIKeyOverride ' '
```

---

## Available models

When the proxy is running with real AWS credentials, `GET /v1/models` returns a **live list** of all foundation models available in the configured region (fetched from the Bedrock management API). When using a Bedrock API key or when the management API call fails, it falls back to the built-in static list below.

All static fallback IDs use cross-region inference profiles (`us.` prefix) for on-demand throughput.

### Anthropic Claude

| Model | ID |
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
| Claude 3.5 Haiku | `us.anthropic.claude-3-5-haiku-20241022-v1:0` |
| Claude 3 Opus | `us.anthropic.claude-3-opus-20240229-v1:0` |
| Claude 3 Haiku | `us.anthropic.claude-3-haiku-20240307-v1:0` |

### Amazon Nova

| Model | ID |
|---|---|
| Amazon Nova Pro | `us.amazon.nova-pro-v1:0` |
| Amazon Nova Lite | `us.amazon.nova-lite-v1:0` |
| Amazon Nova Micro | `us.amazon.nova-micro-v1:0` |

You can also use short aliases (`claude-sonnet-4-5`, `nova-pro`, `gpt-4`, `gpt-3.5-turbo`, etc.) — see [SPECS.md](SPECS.md) for the full mapping table.

> **Enable model access first.** Go to the [AWS Bedrock console](https://console.aws.amazon.com/bedrock/) → **Model access** and request access for each model you want to use. Without this step requests will fail with a `ResourceNotFoundException`.

---

## Configuration

All configuration is via environment variables.

| Variable | Default | Description |
|---|---|---|
| `AWS_REGION` | `us-east-1` | Bedrock region |
| `PROFILE` | — | AWS credentials profile name (`~/.aws/credentials`) |
| `AWS_ACCESS_KEY_ID` | — | AWS access key (alternative to `PROFILE`) |
| `AWS_SECRET_ACCESS_KEY` | — | AWS secret key |
| `AWS_SESSION_TOKEN` | — | Session token for temporary credentials |
| `DEFAULT_BEDROCK_MODEL` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Fallback when model alias is not found |
| `PROXY_API_KEY` | — | Auth key for OpenAI endpoints. Auth disabled if unset. |
| `PORT` | `8080` | HTTP listen port |
| `LOG_LEVEL` | `info` | Vapor log level (`debug` shows raw Xcode payloads) |

---

## Troubleshooting

**`ResourceNotFoundException: Model use case details have not been submitted`**
→ Request model access in the AWS Bedrock console.

**`ValidationException: on-demand throughput isn't supported`**
→ You are passing a bare `anthropic.*` model ID for an older model. Use the `us.anthropic.*` inference profile ID instead.

**`AccessDeniedException`**
→ Your IAM credentials lack `bedrock:InvokeModel` / `bedrock:InvokeModelWithResponseStream`.

**Xcode doesn't show any models**
→ Check that the proxy is running, the base URL has no `/v1` suffix, and the API key header is set to `x-api-key`.

**Enable debug logging** to see the exact payloads Xcode sends:
```bash
LOG_LEVEL=debug swift run Run
```

---

## Development

```bash
# Build
swift build

# Run tests
swift test

# Run with debug logging
LOG_LEVEL=debug swift run Run
```

For full protocol details, implementation notes, and all web references see [SPECS.md](SPECS.md).

---

## License

Apache 2.0
