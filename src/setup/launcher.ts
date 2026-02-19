import { execSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { DetectResult } from "./detect.js";

const CDP_PORT = 19222;
const OPENCLAW_DIR = path.join(os.homedir(), ".openclaw");

function launcherPath(platform: NodeJS.Platform): string {
  const ext = platform === "win32" ? "cmd" : "sh";
  return path.join(OPENCLAW_DIR, `claude-desktop-launcher.${ext}`);
}

function buildWindows(execPath: string): string {
  return `@echo off\r\nstart "" "${execPath}" --remote-debugging-port=${CDP_PORT}\r\n`;
}

function buildMacOS(_execPath: string): string {
  return [
    "#!/bin/bash",
    `open -a Claude --args --remote-debugging-port=${CDP_PORT}`,
    "",
  ].join("\n");
}

function buildLinux(execPath: string): string {
  return [
    "#!/bin/bash",
    `"${execPath}" --remote-debugging-port=${CDP_PORT} &`,
    "",
  ].join("\n");
}

function createWindowsShortcut(execPath: string, launcherFile: string): void {
  const desktop = path.join(os.homedir(), "Desktop");
  const shortcutPath = path.join(desktop, "Claude Desktop (OpenClaw).lnk");
  // Use PowerShell to create a .lnk file
  const ps = [
    `$ws = New-Object -ComObject WScript.Shell;`,
    `$sc = $ws.CreateShortcut('${shortcutPath.replace(/'/g, "''")}');`,
    `$sc.TargetPath = '${launcherFile.replace(/'/g, "''")}';`,
    `$sc.WorkingDirectory = '${OPENCLAW_DIR.replace(/'/g, "''")}';`,
    `$sc.IconLocation = '${execPath.replace(/'/g, "''")},0';`,
    `$sc.Description = 'Claude Desktop with OpenClaw CDP bridge';`,
    `$sc.Save();`,
  ].join(" ");
  try {
    execSync(`powershell -NoProfile -Command "${ps}"`, { stdio: "ignore" });
  } catch {
    // Non-critical — shortcut creation is best-effort
  }
}

export function createLauncher(env: DetectResult): { launcherFile: string } {
  const platform = env.platform;
  const execPath = env.claudeDesktop.execPath ?? "claude";

  if (!fs.existsSync(OPENCLAW_DIR)) {
    fs.mkdirSync(OPENCLAW_DIR, { recursive: true });
  }

  let content: string;
  if (platform === "win32") {
    content = buildWindows(execPath);
  } else if (platform === "darwin") {
    content = buildMacOS(execPath);
  } else {
    content = buildLinux(execPath);
  }

  const file = launcherPath(platform);
  fs.writeFileSync(file, content, "utf8");

  if (platform !== "win32") {
    fs.chmodSync(file, 0o755);
  }

  if (platform === "win32") {
    createWindowsShortcut(execPath, file);
  }

  return { launcherFile: file };
}

export function removeLauncher(env: DetectResult): { removed: boolean } {
  const file = launcherPath(env.platform);
  if (!fs.existsSync(file)) return { removed: false };
  fs.unlinkSync(file);

  // Also remove desktop shortcut on Windows
  if (env.platform === "win32") {
    const shortcut = path.join(
      os.homedir(),
      "Desktop",
      "Claude Desktop (OpenClaw).lnk",
    );
    if (fs.existsSync(shortcut)) {
      try {
        fs.unlinkSync(shortcut);
      } catch {
        // best-effort
      }
    }
  }

  return { removed: true };
}
