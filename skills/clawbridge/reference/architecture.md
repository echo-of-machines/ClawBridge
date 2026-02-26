# ClawBridge Architecture

## Communication Model

```
OpenClaw → Claude Desktop:  UIA (inject message by pasting into closed Electron app)
Claude Desktop → OpenClaw:  MCP tools (openclaw_agent, openclaw_send, openclaw_rpc, etc.)
```

## Overview

```
User Channels         OpenClaw Gateway        ClawBridge MCP         Claude Desktop
(WhatsApp, Telegram,  ←→  (ws://127.0.0.1:18789) ←→  (Node.js)     ←→  (Electron/MSIX)
 Discord, Web UI...)
```

- **OpenClaw → Claude Desktop**: UIA injection via PowerShell scripts (send-message.ps1)
- **Claude Desktop → OpenClaw**: MCP tools over gateway WebSocket (no UIA needed)

## Components

### MCP Server (`dist/index.js`)
Exposes 6 tools to Claude Desktop:
- `openclaw_agent` — Delegate tasks to the OpenClaw agent (75+ tools, multi-step workflows)
- `openclaw_send` — Send messages to channel users (WhatsApp, Telegram, Slack, etc.)
- `openclaw_rpc` — Call any gateway RPC method (cron, config, sessions, skills, etc.)
- `openclaw_status` — Snapshot of channels, sessions, agents, cron jobs
- `openclaw_events` — Query recent events (messages, agent responses, cron triggers)
- `openclaw_node_invoke` — Execute commands on connected devices (macOS, iOS, Android)

### PowerShell Bridge Scripts (`scripts/bridge/`)
Used for the OpenClaw → Claude Desktop direction (UIA injection):

| Script | Purpose |
|--------|---------|
| `preamble.ps1` | Shared Win32/UIA helpers |
| `ensure-accessibility.ps1` | Triggers Chromium accessibility tree |
| `silent-narrator-trigger.ps1` | Fallback accessibility trigger |
| `send-message.ps1` | Sends text via clipboard paste |
| `switch-mode.ps1` | Switches Chat/Cowork/Code |
| `screenshot.ps1` | Captures window |
| `dump-tree.ps1` | Dumps main-content subtree |
| `dump-all.ps1` | Full tree (depth 5) |
| `dump-deep-all.ps1` | Full tree (depth 12) |

Debugging scripts (not part of primary flow):
| `read-response.ps1` | Reads latest assistant response |
| `is-responding.ps1` | Checks if Claude is generating |

### Setup CLI (`dist/setup.js` / `clawbridge` bin)
Installs MCP config, extension files, bridge scripts, and launcher.

## UIA Element Map
| Element | Identifier |
|---------|-----------|
| Main chat area | `AutomationId='main-content'` |
| Text input | `ClassName` contains `tiptap` |
| Submit button | `Button Name='Submit'` |
| Message boundaries | `Button Name='Copy message'` |
| Mode selector | `RadioButton Name='Chat\|Cowork\|Code'` |
| Assistant messages | `ClassName` contains `font-claude-response` |

## AI Model Providers
| Provider | Env Var | Key URL |
|----------|---------|---------|
| Anthropic | `ANTHROPIC_API_KEY` | https://console.anthropic.com/settings/keys |
| OpenAI | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| Google | `GOOGLE_API_KEY` | https://aistudio.google.com/apikey |
| Ollama | `OLLAMA_API_BASE` | No key — https://ollama.com |

## Config Paths (Windows)
| Config | Path |
|--------|------|
| Claude Desktop config | `%APPDATA%\Claude\claude_desktop_config.json` |
| OpenClaw config | `~/.openclaw/openclaw.json` |
| Device identity | `~/.openclaw/device-identity.json` |
| Extension files | `~/.openclaw/extensions/claude-desktop/` |
| Bridge scripts | `~/.openclaw/extensions/claude-desktop/scripts/bridge/` |

## UIA Quirks
- Chromium accessibility is lazy — must trigger via `SPI_SETSCREENREADER=true`
- `InvokePattern.Invoke()` fails on Chromium — use keyboard
- DPI mismatch between UIA coords and `SetCursorPos` — avoid mouse clicks
- TipTap input `Name` property is stale — don't use for verification
