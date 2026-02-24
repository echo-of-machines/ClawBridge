# Setup Flow — Full First-Time Install

Walk the user through each phase conversationally. Explain what each step does and why.

## Phase 1: Prerequisites

Check each. **Stop** if any critical prerequisite is missing.

1. **Windows**: UIA bridge requires Windows
2. **Node.js >= 22.12**: `node --version`. If missing → https://nodejs.org
3. **pnpm**: `pnpm --version`. If missing → `npm install -g pnpm`
4. **Git**: `git --version`. If missing → https://git-scm.com
5. **Claude Desktop**: Check if `Claude.exe` is installed. If missing → https://claude.ai/download

## Phase 2: Clone and Build

1. Check if `package.json` has `"name": "openclaw"` — if so, already in repo, skip cloning.
   Otherwise:
   ```bash
   git clone https://github.com/nicobailon/openclaw.git openclaw
   cd openclaw
   ```
   All subsequent `node scripts/...` commands run from the repo root.

2. Install and build:
   ```bash
   pnpm install && pnpm build
   ```

## Phase 3: OpenClaw Initialization

1. Create config directory and workspace:
   ```bash
   node scripts/run-node.mjs setup
   ```
   Follow interactive prompts (choose "QuickStart" for local setup).

2. Proceed to API key setup — see [Auth Flow](#auth-flow) below.

## Phase 4: Gateway Configuration & Start

The gateway must run **before** ClawBridge setup so the auth token is available.

1. Set `gateway.mode=local` (gateway refuses to start without it):
   ```bash
   node scripts/run-node.mjs config set gateway.mode local
   ```
   If that fails, read `~/.openclaw/openclaw.json` and add `"mode": "local"` inside the `gateway` object.

2. Install as background service + start:
   ```bash
   node scripts/run-node.mjs daemon install
   node scripts/run-node.mjs daemon start
   ```
   `daemon install` registers a Windows Scheduled Task and auto-generates an auth token at `gateway.auth.token` in `~/.openclaw/openclaw.json`.

3. Verify:
   ```bash
   node scripts/run-node.mjs daemon status
   node scripts/run-node.mjs health
   ```
   Gateway runs on `ws://127.0.0.1:18789`. It survives Claude Desktop restarts and auto-starts on login.

## Phase 5: ClawBridge Installation

Run **after** the gateway daemon is running:

```bash
npx -y clawbridge
```

This automatically: sets `gateway.mode=local` if unset, reads the auth token, writes MCP config to `claude_desktop_config.json`, deploys bridge scripts, installs the Claude Code skill, registers the plugin, and creates a launcher.

## Phase 6: Inject Auth Token (if missing)

Check if `npx clawbridge` output said "Auth token included in MCP config". If yes, skip this phase.

Otherwise:
1. Read `~/.openclaw/openclaw.json` → extract `gateway.auth.token`
2. Read `%APPDATA%\Claude\claude_desktop_config.json`
3. Patch `mcpServers.openclaw.env.OPENCLAW_AUTH_TOKEN` with the token value. Preserve all other config.

## Phase 7: Final Steps

Tell the user:
1. **Restart Claude Desktop** to load the new MCP server config (first time only)
2. Gateway is a background service — auto-starts on login, survives restarts
3. MCP server auto-reconnects within 30 seconds if connection drops

---

# Auth Flow

Guide the user through API key setup conversationally.

## Available providers

| Provider | Env Var | Get key at |
|----------|---------|-----------|
| Anthropic | `ANTHROPIC_API_KEY` | https://console.anthropic.com/settings/keys |
| OpenAI | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| Google | `GOOGLE_API_KEY` | https://aistudio.google.com/apikey |
| Ollama | — (no key) | https://ollama.com |
| AWS Bedrock | AWS credentials | — |

## For each selected provider

Ask for the key, then add it to the `env.vars` section of `~/.openclaw/openclaw.json`:

```json5
{
  "env": {
    "vars": {
      "ANTHROPIC_API_KEY": "sk-ant-...",
      "OPENAI_API_KEY": "sk-..."
    }
  }
}
```

Read the config first, then edit to add/update only the env vars. Preserve all existing config.

Verify: `node scripts/run-node.mjs config get env.vars`

**NEVER** display API keys back to the user after they provide them.

---

# Gateway Management

## Prerequisites

Gateway requires `gateway.mode=local` in `~/.openclaw/openclaw.json`:
```bash
node scripts/run-node.mjs config set gateway.mode local
```

## Daemon (recommended)

```bash
node scripts/run-node.mjs daemon install   # Register as Windows Scheduled Task
node scripts/run-node.mjs daemon start     # Start
node scripts/run-node.mjs daemon status    # Check status
node scripts/run-node.mjs daemon stop      # Stop
node scripts/run-node.mjs daemon restart   # Restart
```

## Foreground (alternative)

```bash
node scripts/run-node.mjs gateway              # Blocks
node scripts/run-node.mjs gateway --allow-unconfigured  # Skip mode check
```

## Health check

```bash
node scripts/run-node.mjs health
```

## Config reference

In `~/.openclaw/openclaw.json` under `gateway`:
- `gateway.mode` — "local" or "remote" (**required**)
- `gateway.port` — default 18789
- `gateway.auth.mode` — "token" (default), "password", or "trusted-proxy"
- `gateway.auth.token` — auto-generated on first daemon install or gateway start
