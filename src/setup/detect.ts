import { execSync } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

export type DetectResult = {
  claudeDesktop: {
    found: boolean;
    execPath?: string;
    configPath?: string;
    configExists: boolean;
  };
  openclaw: {
    gatewayReachable: boolean;
    gatewayUrl: string;
    configPath?: string;
    configExists: boolean;
    authToken?: string;
  };
  platform: NodeJS.Platform;
};

function findClaudeDesktopExec(): string | undefined {
  const p = process.platform;
  if (p === "win32") {
    const candidate = path.join(
      process.env.LOCALAPPDATA ?? "",
      "Programs",
      "Claude",
      "Claude.exe",
    );
    if (fs.existsSync(candidate)) return candidate;
  } else if (p === "darwin") {
    const candidate = "/Applications/Claude.app/Contents/MacOS/Claude";
    if (fs.existsSync(candidate)) return candidate;
  } else {
    for (const name of ["claude-desktop", "claude"]) {
      try {
        const result = execSync(`which ${name} 2>/dev/null`, { encoding: "utf8" }).trim();
        if (result) return result;
      } catch {
        // not found
      }
    }
    const candidates = [
      "/usr/bin/claude-desktop",
      "/opt/Claude/claude-desktop",
      path.join(os.homedir(), ".local", "bin", "claude-desktop"),
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return c;
    }
  }
  return undefined;
}

function findClaudeDesktopConfig(): string {
  const p = process.platform;
  if (p === "win32") {
    return path.join(
      process.env.APPDATA ?? "",
      "Claude",
      "claude_desktop_config.json",
    );
  }
  if (p === "darwin") {
    return path.join(
      os.homedir(),
      "Library",
      "Application Support",
      "Claude",
      "claude_desktop_config.json",
    );
  }
  // Linux / fallback
  return path.join(
    process.env.XDG_CONFIG_HOME ?? path.join(os.homedir(), ".config"),
    "Claude",
    "claude_desktop_config.json",
  );
}

function findOpenClawConfig(): string {
  return path.join(os.homedir(), ".openclaw", "openclaw.json");
}

function readAuthToken(configPath: string): string | undefined {
  try {
    const raw = fs.readFileSync(configPath, "utf8");
    const cfg = JSON.parse(raw) as { gateway?: { token?: string } };
    return cfg.gateway?.token;
  } catch {
    return undefined;
  }
}

async function testTcpConnect(
  host: string,
  port: number,
  timeoutMs = 2000,
): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    const timer = setTimeout(() => {
      socket.destroy();
      resolve(false);
    }, timeoutMs);
    socket.connect(port, host, () => {
      clearTimeout(timer);
      socket.destroy();
      resolve(true);
    });
    socket.on("error", () => {
      clearTimeout(timer);
      resolve(false);
    });
  });
}

export async function detect(): Promise<DetectResult> {
  const execPath = findClaudeDesktopExec();
  const configPath = findClaudeDesktopConfig();

  const ocConfigPath = findOpenClawConfig();
  const ocConfigExists = fs.existsSync(ocConfigPath);
  const authToken = ocConfigExists ? readAuthToken(ocConfigPath) : undefined;
  const gatewayUrl =
    process.env.OPENCLAW_GATEWAY_URL ?? "ws://127.0.0.1:18789";

  // Extract host/port from gateway URL for TCP test
  let gwHost = "127.0.0.1";
  let gwPort = 18789;
  try {
    const u = new URL(gatewayUrl.replace(/^ws/, "http"));
    gwHost = u.hostname;
    gwPort = Number(u.port) || 18789;
  } catch {
    // keep defaults
  }
  const gatewayReachable = await testTcpConnect(gwHost, gwPort);

  return {
    claudeDesktop: {
      found: execPath !== undefined,
      execPath,
      configPath,
      configExists: fs.existsSync(configPath),
    },
    openclaw: {
      gatewayReachable,
      gatewayUrl,
      configPath: ocConfigPath,
      configExists: ocConfigExists,
      authToken,
    },
    platform: process.platform,
  };
}
