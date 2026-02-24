#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { detect } from "./setup/detect.js";
import { installExtension } from "./setup/extension.js";
import { createLauncher } from "./setup/launcher.js";
import { installMcpConfig } from "./setup/mcp-config.js";
import { uninstall, printUninstallSummary } from "./setup/uninstall.js";
import { validate } from "./setup/validate.js";

const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const RED = "\x1b[31m";
const CYAN = "\x1b[36m";
const RESET = "\x1b[0m";

const ok = (msg: string) => console.log(`${GREEN}  ✓${RESET} ${msg}`);
const warn = (msg: string) => console.log(`${YELLOW}  ⚠${RESET} ${msg}`);
const fail = (msg: string) => console.log(`${RED}  ✗${RESET} ${msg}`);
const step = (n: number, total: number, msg: string) =>
  console.log(`\n${CYAN}[${n}/${total}]${RESET} ${msg}`);

const { values } = parseArgs({
  options: {
    status: { type: "boolean", default: false },
    uninstall: { type: "boolean", default: false },
    reinstall: { type: "boolean", default: false },
  },
  strict: false,
});

function printCheck(c: { pass: boolean; severity: string; message: string }): void {
  if (c.pass) {
    ok(c.message);
  } else if (c.severity === "warning") {
    warn(c.message);
  } else {
    fail(c.message);
  }
}

// ---------------------------------------------------------------------------
// Skill installation — copies SKILL.md + reference to ~/.claude/skills/
// ---------------------------------------------------------------------------

function resolvePackageRoot(): string {
  // setup.js is at dist/setup.js → package root is one level up
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
}

function installSkill(): { skillDir: string; installed: boolean } {
  const packageRoot = resolvePackageRoot();
  const skillSource = path.join(packageRoot, "skills", "clawbridge");
  const skillDest = path.join(os.homedir(), ".claude", "skills", "clawbridge");

  if (!fs.existsSync(skillSource) || !fs.existsSync(path.join(skillSource, "SKILL.md"))) {
    return { skillDir: skillDest, installed: false };
  }

  // Copy skill files (SKILL.md + reference/)
  copySkillDir(skillSource, skillDest);
  return { skillDir: skillDest, installed: true };
}

function copySkillDir(src: string, dest: string): void {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copySkillDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function removeSkill(): boolean {
  const skillDir = path.join(os.homedir(), ".claude", "skills", "clawbridge");
  if (fs.existsSync(skillDir)) {
    fs.rmSync(skillDir, { recursive: true, force: true });
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Detect if we're running from inside the OpenClaw monorepo
// ---------------------------------------------------------------------------

function resolveRepoRoot(): string | null {
  const packageRoot = resolvePackageRoot();
  // In monorepo: package root is at packages/clawbridge-mcp/
  // Two levels up should have package.json with name "openclaw"
  const repoRoot = path.resolve(packageRoot, "..", "..");
  const repoPackageJson = path.join(repoRoot, "package.json");
  try {
    const raw = fs.readFileSync(repoPackageJson, "utf8");
    const pkg = JSON.parse(raw) as { name?: string };
    return pkg.name === "openclaw" ? repoRoot : null;
  } catch {
    return null;
  }
}

function isInMonorepo(): boolean {
  return resolveRepoRoot() !== null;
}

// ---------------------------------------------------------------------------
// Gateway configuration helpers
// ---------------------------------------------------------------------------

type OpenClawConfig = {
  gateway?: {
    mode?: string;
    auth?: { token?: string; mode?: string };
    [k: string]: unknown;
  };
  [k: string]: unknown;
};

function readOpenClawConfig(configPath: string): OpenClawConfig | null {
  try {
    const raw = fs.readFileSync(configPath, "utf8");
    return JSON.parse(raw) as OpenClawConfig;
  } catch {
    return null;
  }
}

function writeOpenClawConfig(configPath: string, config: OpenClawConfig): void {
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", "utf8");
}

function setGatewayModeIfUnset(
  configPath: string,
): { set: boolean; alreadySet: boolean } {
  const config = readOpenClawConfig(configPath);
  if (!config) return { set: false, alreadySet: false };

  if (config.gateway?.mode) {
    return { set: false, alreadySet: true };
  }

  if (!config.gateway) config.gateway = {};
  config.gateway.mode = "local";
  writeOpenClawConfig(configPath, config);
  return { set: true, alreadySet: false };
}

// ---------------------------------------------------------------------------
// Gateway client-info patch — adds clawbridge-mcp to the allowed client IDs
// ---------------------------------------------------------------------------

const CLAWBRIDGE_ENTRY = '  CLAWBRIDGE: "clawbridge-mcp",';

function patchGatewayClientIds(
  repoRoot: string,
): { patched: boolean; alreadyPresent: boolean; error?: string } {
  const filePath = path.join(repoRoot, "src", "gateway", "protocol", "client-info.ts");
  try {
    const content = fs.readFileSync(filePath, "utf8");

    // Already patched?
    if (content.includes('"clawbridge-mcp"')) {
      return { patched: false, alreadyPresent: true };
    }

    // Insert before the closing `} as const;` of GATEWAY_CLIENT_IDS
    const marker = "} as const;";
    const idx = content.indexOf(marker);
    if (idx === -1) {
      return { patched: false, alreadyPresent: false, error: "Could not find '} as const;' marker" };
    }

    const patched = content.slice(0, idx) + CLAWBRIDGE_ENTRY + "\n" + content.slice(idx);
    fs.writeFileSync(filePath, patched, "utf8");
    return { patched: true, alreadyPresent: false };
  } catch (err) {
    return { patched: false, alreadyPresent: false, error: String(err) };
  }
}

function isAccessDenied(output: string): boolean {
  return /access.is.denied|elevation|privilege|requires.admin/i.test(output);
}

function summarizeDaemonError(raw: string): string {
  // Strip build noise ([openclaw] Building TypeScript...) and keep the real error
  const lines = raw.split("\n").filter(
    (l) =>
      !l.startsWith("[openclaw]") &&
      !l.startsWith("ℹ") &&
      !l.startsWith("✔") &&
      l.trim().length > 0,
  );
  const meaningful = lines.join(" ").trim();
  return meaningful.length > 0 ? meaningful.slice(0, 200) : raw.slice(0, 200);
}

function runDaemonCommand(
  repoRoot: string,
  args: string[],
): { ok: boolean; output: string } {
  const runNode = path.join(repoRoot, "scripts", "run-node.mjs");
  try {
    const output = execFileSync("node", [runNode, ...args], {
      cwd: repoRoot,
      encoding: "utf8",
      timeout: 120000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    return { ok: true, output: output.trim() };
  } catch (err) {
    // Extract stderr from ExecFileSync errors for better diagnostics
    const execErr = err as { stderr?: string; message?: string };
    const stderr = execErr.stderr?.trim();
    const msg = stderr || execErr.message || String(err);
    // Check for common non-error outcomes in output
    const combined = `${(err as { stdout?: string }).stdout ?? ""} ${msg}`;
    if (/already\s+(installed|loaded|running)/i.test(combined)) {
      return { ok: true, output: combined.trim() };
    }
    return { ok: false, output: msg };
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  // --- Serve mode: start the MCP server (used by npx clawbridge serve) ---
  const positionals = process.argv.slice(2).filter((a) => !a.startsWith("-"));
  if (positionals[0] === "serve") {
    await import("./index.js");
    return;
  }

  console.log(`\n${CYAN}ClawBridge Setup${RESET} — Claude Desktop + OpenClaw Bridge\n`);

  const inMonorepo = isInMonorepo();

  // --- Uninstall mode ---
  if (values.uninstall) {
    const env = await detect();
    const result = uninstall(env);
    const skillRemoved = removeSkill();
    printUninstallSummary(result);
    console.log(`  Claude Code skill: ${skillRemoved ? "removed" : "not found (skipped)"}`);
    console.log("");
    return;
  }

  // Always install the skill first
  const skill = installSkill();
  if (skill.installed) {
    ok(`Claude Code skill installed to ${skill.skillDir}`);
    console.log(`  Use ${CYAN}/clawbridge${RESET} in Claude Desktop Code mode`);
  }

  const env = await detect();

  // --- Status mode ---
  if (values.status) {
    const checks = await validate(env);
    for (const c of checks) {
      printCheck(c);
    }
    const hasErrors = checks.some((c) => !c.pass && c.severity === "error");
    process.exitCode = hasErrors ? 1 : 0;
    return;
  }

  // --- Reinstall: uninstall first, then continue to setup ---
  if (values.reinstall) {
    console.log("Removing existing installation...");
    const result = uninstall(env);
    removeSkill();
    printUninstallSummary(result);
    const freshEnv = await detect();
    const freshSkill = installSkill();
    if (freshSkill.installed) {
      ok(`Claude Code skill reinstalled to ${freshSkill.skillDir}`);
    }
    await runBridgeSetup(freshEnv, inMonorepo);
    return;
  }

  // --- Default: bridge setup ---
  await runBridgeSetup(env, inMonorepo);
}

async function runBridgeSetup(
  env: Awaited<ReturnType<typeof detect>>,
  inMonorepo: boolean,
): Promise<void> {
  const TOTAL = 9;
  let stepNum = 0;
  const repoRoot = inMonorepo ? resolveRepoRoot() : null;

  // Step 1: Detect Claude Desktop
  step(++stepNum, TOTAL, "Detecting Claude Desktop...");
  if (env.claudeDesktop.found) {
    ok(`Found at ${env.claudeDesktop.execPath}`);
  } else {
    fail("Claude Desktop not found — install it from https://claude.ai/download");
  }

  // Step 2: Detect OpenClaw
  step(++stepNum, TOTAL, "Detecting OpenClaw...");
  if (env.openclaw.configExists) {
    ok(`Config found at ${env.openclaw.configPath}`);
  } else {
    warn("OpenClaw config not found — run 'openclaw setup' first");
  }
  if (env.openclaw.gatewayReachable) {
    ok(`Gateway reachable at ${env.openclaw.gatewayUrl}`);
  }

  // Step 3: Configure gateway
  step(++stepNum, TOTAL, "Configuring gateway...");
  if (env.openclaw.configPath && env.openclaw.configExists) {
    const gw = setGatewayModeIfUnset(env.openclaw.configPath);
    if (gw.alreadySet) {
      ok("gateway.mode already configured");
    } else if (gw.set) {
      ok("Set gateway.mode=local");
    } else {
      warn("Could not set gateway.mode — set it manually in ~/.openclaw/openclaw.json");
    }
  } else {
    warn("Skipped — OpenClaw config not found");
  }

  // Step 4: Patch gateway to allow clawbridge-mcp client ID
  step(++stepNum, TOTAL, "Patching gateway client allowlist...");
  if (repoRoot) {
    const patch = patchGatewayClientIds(repoRoot);
    if (patch.alreadyPresent) {
      ok("clawbridge-mcp already in GATEWAY_CLIENT_IDS");
    } else if (patch.patched) {
      ok("Added clawbridge-mcp to GATEWAY_CLIENT_IDS");
      // Rebuild so the gateway picks up the new client ID
      try {
        execFileSync("pnpm", ["build"], {
          cwd: repoRoot,
          encoding: "utf8",
          timeout: 120000,
          stdio: ["pipe", "pipe", "pipe"],
        });
        ok("Rebuilt OpenClaw with patched client ID");
      } catch {
        warn("Rebuild failed — run 'pnpm build' manually from the OpenClaw repo");
      }
    } else {
      warn(patch.error ?? "Could not patch client-info.ts — gateway may reject ClawBridge connections");
    }
  } else {
    warn("Not in monorepo — ensure the gateway allows 'clawbridge-mcp' client ID");
  }

  // Step 5: Install & start gateway daemon
  step(++stepNum, TOTAL, "Starting gateway daemon...");
  if (repoRoot) {
    const install = runDaemonCommand(repoRoot, ["daemon", "install"]);
    if (install.ok) {
      ok("Gateway daemon installed (auto-starts on login)");
    } else if (isAccessDenied(install.output)) {
      warn("Daemon install requires admin privileges (schtasks needs elevation)");
      console.log(`    Run as Administrator, or start the gateway in foreground mode:`);
      console.log(`    ${CYAN}node scripts/run-node.mjs gateway${RESET}`);
    } else {
      warn(`Daemon install failed — ${summarizeDaemonError(install.output)}`);
    }

    if (install.ok) {
      const start = runDaemonCommand(repoRoot, ["daemon", "start"]);
      if (start.ok) {
        ok("Gateway daemon started");
      } else {
        warn(`Daemon start failed — ${summarizeDaemonError(start.output)}`);
      }
    }
  } else if (env.openclaw.gatewayReachable) {
    ok("Gateway already running");
  } else {
    warn("Run 'node scripts/run-node.mjs daemon install && daemon start' from the OpenClaw repo");
  }

  // Brief wait for daemon to generate auth token on first start
  if (!env.openclaw.authToken) {
    await new Promise((r) => setTimeout(r, 3000));
  }

  // Re-detect to pick up auth token and fresh gateway status
  const freshEnv = await detect();

  // Step 5: Install MCP server config (with auth token if available)
  step(++stepNum, TOTAL, "Installing MCP server config...");
  const mcp = installMcpConfig(freshEnv, { useNpx: !inMonorepo });
  ok(`Written to ${mcp.configPath}`);
  if (freshEnv.openclaw.authToken) {
    ok("Auth token included in MCP config");
  } else {
    warn("No auth token found — re-run setup after starting the gateway to inject it");
  }

  // Step 6: Install bridge scripts
  step(++stepNum, TOTAL, "Installing bridge scripts...");
  const ext = installExtension(freshEnv);
  ok(`Installed to ${ext.extensionDir}`);

  // Step 7: Create launcher
  step(++stepNum, TOTAL, "Creating launcher script...");
  const launcher = createLauncher(freshEnv);
  ok(`Created at ${launcher.launcherFile}`);

  // Step 8: Validate
  step(++stepNum, TOTAL, "Validating installation...");
  const checks = await validate(freshEnv);
  for (const c of checks) {
    printCheck(c);
  }

  const hasErrors = checks.some((c) => !c.pass && c.severity === "error");
  const hasWarnings = checks.some((c) => !c.pass && c.severity === "warning");
  if (!hasErrors) {
    console.log(`\n${GREEN}Setup complete!${RESET}`);
    if (hasWarnings) {
      console.log(`\n${YELLOW}Note:${RESET} Some optional checks had warnings — see above.`);
    }
    console.log(`\nNext steps:`);
    console.log(`  1. Restart Claude Desktop to load the new MCP server config`);
    console.log(`  2. The gateway runs as a background service — it auto-starts on login`);
    console.log(`  3. Ask Claude to set up OpenClaw and ClawBridge\n`);
  } else {
    console.log(`\n${RED}Setup completed with errors.${RESET} Review the checks above.\n`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(`\n${RED}Setup failed:${RESET} ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
});
