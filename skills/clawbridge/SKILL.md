---
name: clawbridge
description: "Set up and manage OpenClaw + ClawBridge with Claude Desktop on Windows. Use when users want to: (1) install OpenClaw and ClawBridge from scratch, (2) configure API keys for AI models, (3) manage the OpenClaw gateway daemon, (4) send messages to or read responses from Claude Desktop via UIA bridge, (5) switch Claude Desktop modes (Chat/Cowork/Code), (6) capture screenshots or dump UIA trees for debugging, (7) run health checks on the bridge or OpenClaw installation."
disable-model-invocation: true
argument-hint: "<setup|auth|gateway|bridge-status|send|read|mode|screenshot|debug|doctor> [args...]"
allowed-tools: Bash, Read, Write, Glob, Grep
---

# ClawBridge — OpenClaw + Claude Desktop Manager

**Subcommand**: `$0`
**Arguments**: `$ARGUMENTS`

Route to the appropriate command below. If no subcommand is given, show the help menu.

## Bridge Script Invocation

All UIA bridge commands use PowerShell scripts at `<scripts-dir>`:

```
powershell -ExecutionPolicy Bypass -File <scripts-dir>/<script> [params]
```

Resolve `<scripts-dir>` once per session (check in order):
1. `~/.openclaw/extensions/claude-desktop/scripts/bridge/` (default after setup)
2. `${CLAUDE_PLUGIN_ROOT}/scripts/bridge/` (plugin install)
3. `packages/clawbridge-mcp/scripts/bridge/` (monorepo dev)

---

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Full first-time install: clone, build, configure OpenClaw + ClawBridge |
| `auth` | Set up AI model API keys (Anthropic, OpenAI, Google, etc.) |
| `gateway` | Start/stop/check the OpenClaw gateway daemon |
| `bridge-status` | Check ClawBridge installation health |
| `send <msg>` | Send a message to Claude Desktop via UIA |
| `read` | Read the latest response from Claude Desktop |
| `mode <mode>` | Switch Claude Desktop mode (Chat/Cowork/Code) |
| `screenshot` | Capture Claude Desktop window |
| `debug` | Dump UIA tree for troubleshooting |
| `doctor` | Run OpenClaw health check and repairs |

---

## `setup`

Full first-time install. Read [reference/setup-flow.md](reference/setup-flow.md) and follow the 7-phase flow:

1. **Prerequisites** — check Windows, Node.js >= 22.12, pnpm, Git, Claude Desktop
2. **Clone and Build** — clone repo, `pnpm install && pnpm build`
3. **OpenClaw Init** — `node scripts/run-node.mjs setup`, then `auth`
4. **Gateway** — set `gateway.mode=local`, `daemon install`, `daemon start`
5. **ClawBridge** — `npx -y clawbridge` (reads auth token, writes MCP config)
6. **Auth Token** — verify token is in Claude Desktop's MCP config, patch if missing
7. **Final** — restart Claude Desktop (first time only)

---

## `auth`

Guide user through API key setup. See the [Auth Flow in reference/setup-flow.md](reference/setup-flow.md#auth-flow) for provider table and config format.

---

## `gateway`

Manage the OpenClaw gateway. See [Gateway Management in reference/setup-flow.md](reference/setup-flow.md#gateway-management) for full daemon lifecycle commands.

Quick reference:
```bash
node scripts/run-node.mjs daemon install && daemon start  # First time
node scripts/run-node.mjs daemon status                   # Check
node scripts/run-node.mjs health                          # Health check
```

---

## `bridge-status`

```bash
npx -y clawbridge --status
```

Green `✓` = passing, Yellow `⚠` = warning, Red `✗` = error.

---

## `send <message>`

**CRITICAL**: Verify Claude Desktop is open and visible before running.

1. Ensure accessibility tree: `ensure-accessibility.ps1` → expect `OK`
2. Send: `send-message.ps1 -Message "<the message>"` → expect `OK`

---

## `read`

Run `read-response.ps1`. Output starts with `RESPONSE:` — parse and display cleanly.
`NO_RESPONSE` or `EMPTY_RESPONSE` means no response found.

---

## `mode <Chat|Cowork|Code>`

Run `switch-mode.ps1 -Mode <Chat|Cowork|Code>`.

| Output | Meaning |
|--------|---------|
| `OK:<Mode>` | Switched successfully |
| `ALREADY:<Mode>` | Already in that mode |
| `ERROR:MODE_NOT_FOUND:<Mode>` | Radio button not found |
| `ERROR:WINDOW_NOT_FOUND` | Claude Desktop not open |

---

## `screenshot`

Run `screenshot.ps1`. Saves a BMP file — read and display the image from the output path.

---

## `debug`

Dump UIA accessibility tree:

| Script | Scope |
|--------|-------|
| `dump-tree.ps1` | main-content subtree (try first) |
| `dump-all.ps1` | Full tree, depth 5 |
| `dump-deep-all.ps1` | Full tree, depth 12 |

---

## `doctor`

```bash
node scripts/run-node.mjs doctor
```

Checks 35+ items: config validity, gateway health, auth profiles, channel connectivity, plugin status.

---

## No subcommand / help

Display:

```
ClawBridge — OpenClaw + Claude Desktop Bridge

Usage: /clawbridge <command> [args...]

Setup & Configuration:
  setup          Full first-time install (clone, build, configure everything)
  auth           Set up AI model API keys (Anthropic, OpenAI, Google, etc.)
  gateway        Start/stop/check the OpenClaw gateway
  doctor         Run OpenClaw health check and repairs

Bridge Operations:
  send <msg>     Send a message to Claude Desktop
  read           Read latest Claude Desktop response
  mode <mode>    Switch mode (Chat, Cowork, Code)
  screenshot     Capture Claude Desktop window

Diagnostics:
  bridge-status  Check ClawBridge installation health
  debug          Dump UIA tree for troubleshooting
```

---

## References

- [reference/architecture.md](reference/architecture.md) — component diagram, UIA element map, config paths, quirks
- [reference/setup-flow.md](reference/setup-flow.md) — detailed setup phases, auth flow, gateway management

## Safety Rules

1. **NEVER** send keyboard shortcuts without verifying the target window is Claude Desktop (`Chrome_WidgetWin_1` class, title contains "Claude")
2. **NEVER** use `Ctrl+W` or `Alt+F4` — they can kill Claude Code or VSCode
3. UIA bridge uses `SetForegroundWindow` + clipboard paste + Enter — no mouse clicks
4. When editing config files: read first, preserve existing content, only add/modify specific fields
5. **NEVER** log or display API keys back to the user
