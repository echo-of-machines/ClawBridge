import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import json5 from "json5";
import type { DetectResult } from "./detect.js";

const PLUGIN_ID = "claude-desktop";
const DEST_DIR = path.join(os.homedir(), ".openclaw", "extensions", PLUGIN_ID);

const DEFAULT_PLUGIN_CONFIG = {
  enabled: true,
  config: {
    enabled: true,
    cdpPort: 19222,
    cdpHost: "127.0.0.1",
    interceptAll: true,
    responseTimeoutMs: 120000,
    messagePrefix: true,
  },
};

type OpenClawJson = {
  plugins?: {
    entries?: Record<string, unknown>;
    [k: string]: unknown;
  };
  [k: string]: unknown;
};

function resolveExtensionSource(): string {
  // At runtime this file is dist/setup/extension.js — walk up two levels
  // to the repo root, then into the extension/ directory.
  return path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
    "..",
    "extension",
  );
}

function copyDir(src: string, dest: string): void {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function readOpenClawJson(configPath: string): OpenClawJson {
  if (!fs.existsSync(configPath)) return {};
  try {
    return json5.parse(fs.readFileSync(configPath, "utf8")) as OpenClawJson;
  } catch {
    return {};
  }
}

function writeOpenClawJson(configPath: string, config: OpenClawJson): void {
  const dir = path.dirname(configPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", "utf8");
}

export function installExtension(env: DetectResult): { extensionDir: string } {
  // 1. Copy extension files
  const src = resolveExtensionSource();
  if (fs.existsSync(src)) {
    copyDir(src, DEST_DIR);
  }

  // 2. Update OpenClaw config
  const configPath = env.openclaw.configPath!;
  const config = readOpenClawJson(configPath);

  if (!config.plugins) config.plugins = {};
  if (!config.plugins.entries) config.plugins.entries = {};

  // Deep merge: preserve any existing config keys
  const existing = (config.plugins.entries[PLUGIN_ID] ?? {}) as Record<string, unknown>;
  const existingConfig = (existing.config ?? {}) as Record<string, unknown>;
  config.plugins.entries[PLUGIN_ID] = {
    ...existing,
    ...DEFAULT_PLUGIN_CONFIG,
    config: {
      ...DEFAULT_PLUGIN_CONFIG.config,
      ...existingConfig,
      enabled: true,
    },
  };

  writeOpenClawJson(configPath, config);
  return { extensionDir: DEST_DIR };
}

export function removeExtension(env: DetectResult): { removed: boolean } {
  let changed = false;

  // 1. Remove from OpenClaw config
  const configPath = env.openclaw.configPath!;
  if (fs.existsSync(configPath)) {
    const config = readOpenClawJson(configPath);
    if (config.plugins?.entries?.[PLUGIN_ID]) {
      const entry = config.plugins.entries[PLUGIN_ID] as Record<string, unknown>;
      entry.enabled = false;
      writeOpenClawJson(configPath, config);
      changed = true;
    }
  }

  // 2. Remove copied extension files
  if (fs.existsSync(DEST_DIR)) {
    fs.rmSync(DEST_DIR, { recursive: true, force: true });
    changed = true;
  }

  return { removed: changed };
}
