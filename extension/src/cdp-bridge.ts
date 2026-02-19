import WebSocket from "ws";

export type CdpTarget = {
  id: string;
  type: string;
  title: string;
  url: string;
  webSocketDebuggerUrl?: string;
};

type Pending = {
  resolve: (value: unknown) => void;
  reject: (err: Error) => void;
};

export type CdpEventListener = (params: Record<string, unknown>) => void;

export type InputSelectors = {
  dataTestId?: string;
  role?: string;
  contentEditable?: boolean;
  fallbackTag?: string;
};

const DEFAULT_SELECTORS: InputSelectors = {
  dataTestId: "composer-input",
  role: "textbox",
  contentEditable: true,
  fallbackTag: "textarea",
};

export class CdpBridge {
  private ws: WebSocket | null = null;
  private nextId = 1;
  private readonly pending = new Map<number, Pending>();
  private readonly eventListeners = new Map<string, Set<CdpEventListener>>();
  selectors: InputSelectors = { ...DEFAULT_SELECTORS };

  private closed = false;
  private backoffMs = 1000;
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private connectHost = "127.0.0.1";
  private connectPort = 19222;
  private responseCallback:
    | ((data: { type: string; text: string }) => void)
    | null = null;

  isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  async connect(host: string, port: number): Promise<void> {
    this.closed = false;
    this.connectHost = host;
    this.connectPort = port;

    const targets = await this.discoverTargets(host, port);
    const target = targets.find((t) => t.type === "page") ?? targets[0];
    if (!target?.webSocketDebuggerUrl) {
      throw new Error("No CDP target with webSocketDebuggerUrl found");
    }

    const wsUrl = normalizeCdpWsUrl(target.webSocketDebuggerUrl, host, port);
    await this.openWebSocket(wsUrl);
    this.backoffMs = 1000;
    this.startHealthPing();
  }

  async send(
    method: string,
    params?: Record<string, unknown>,
  ): Promise<unknown> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error("CDP WebSocket not connected");
    }
    const id = this.nextId++;
    const msg = JSON.stringify({ id, method, params });
    this.ws.send(msg);
    return new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }

  on(event: string, listener: CdpEventListener): void {
    let set = this.eventListeners.get(event);
    if (!set) {
      set = new Set();
      this.eventListeners.set(event, set);
    }
    set.add(listener);
  }

  off(event: string, listener: CdpEventListener): void {
    this.eventListeners.get(event)?.delete(listener);
  }

  disconnect(): void {
    this.closed = true;
    this.stopHealthPing();
    this.rejectAllPending(new Error("CDP bridge disconnected"));
    if (this.ws) {
      try {
        this.ws.close();
      } catch {
        // ignore
      }
      this.ws = null;
    }
  }

  async observeResponses(
    callback: (data: { type: string; text: string }) => void,
  ): Promise<void> {
    this.responseCallback = callback;

    // Step 1: Register binding
    await this.send("Runtime.addBinding", { name: "__clawbridge" });

    // Step 2: Install MutationObserver to watch for new assistant messages
    await this.send("Runtime.evaluate", {
      expression: `(() => {
        if (window.__clawbridgeObserver) return;
        const container = document.querySelector('[class*="conversation"]')
          || document.querySelector('main')
          || document.body;
        const observer = new MutationObserver(() => {
          const messages = document.querySelectorAll(
            '[data-testid*="assistant"], [data-message-author-role="assistant"], .agent-turn'
          );
          const last = messages[messages.length - 1];
          if (!last) return;
          const text = (last.innerText || last.textContent || "").trim();
          if (text && text !== window.__clawbridgeLastText) {
            window.__clawbridgeLastText = text;
            window.__clawbridge(JSON.stringify({ type: "response", text }));
          }
        });
        observer.observe(container, { childList: true, subtree: true, characterData: true });
        window.__clawbridgeObserver = observer;
      })()`,
      awaitPromise: false,
      returnByValue: true,
    });

    // Step 3: Listen for binding calls via CDP events
    await this.send("Runtime.enable");
    this.on("Runtime.bindingCalled", (params) => {
      if (params.name !== "__clawbridge") return;
      try {
        const payload = JSON.parse(String(params.payload)) as {
          type: string;
          text: string;
        };
        callback(payload);
      } catch {
        // ignore parse errors
      }
    });
  }

  async readLastResponse(): Promise<string> {
    const result = (await this.send("Runtime.evaluate", {
      expression: `(() => {
        const messages = document.querySelectorAll(
          '[data-testid*="assistant"], [data-message-author-role="assistant"], .agent-turn'
        );
        const last = messages[messages.length - 1];
        return last ? (last.innerText || last.textContent || "").trim() : "";
      })()`,
      awaitPromise: false,
      returnByValue: true,
    })) as { result?: { value?: unknown } };
    const value = result?.result?.value;
    return typeof value === "string" ? value : "";
  }

  async injectMessage(text: string): Promise<void> {
    const s = this.selectors;
    const selectorChain = [
      s.dataTestId ? `[data-testid="${s.dataTestId}"]` : "",
      s.role ? `[role="${s.role}"]` : "",
      s.contentEditable ? "[contenteditable]" : "",
      s.fallbackTag ?? "",
    ]
      .filter(Boolean)
      .map((sel) => JSON.stringify(sel));

    const expression = `(() => {
      const selectors = [${selectorChain.join(",")}];
      let el = null;
      for (const sel of selectors) {
        el = document.querySelector(sel);
        if (el) break;
      }
      if (!el) throw new Error("Input element not found");
      el.focus();
      if (el.tagName === "TEXTAREA" || el.tagName === "INPUT") {
        const nativeSetter = Object.getOwnPropertyDescriptor(
          Object.getPrototypeOf(el), "value"
        )?.set;
        if (nativeSetter) nativeSetter.call(el, ${JSON.stringify(text)});
        else el.value = ${JSON.stringify(text)};
      } else {
        el.textContent = ${JSON.stringify(text)};
      }
      el.dispatchEvent(new InputEvent("input", { bubbles: true, data: ${JSON.stringify(text)} }));
      return true;
    })()`;

    await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: false,
      returnByValue: true,
      userGesture: true,
    });

    // Press Enter via CDP Input domain
    await this.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 13,
    });
    await this.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 13,
    });
  }

  private async discoverTargets(
    host: string,
    port: number,
  ): Promise<CdpTarget[]> {
    const url = `http://${host}:${port}/json/list`;
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 5000);
    try {
      const res = await fetch(url, { signal: ctrl.signal });
      if (!res.ok) {
        throw new Error(`CDP target discovery failed: HTTP ${res.status}`);
      }
      return (await res.json()) as CdpTarget[];
    } finally {
      clearTimeout(t);
    }
  }

  private openWebSocket(wsUrl: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const ws = new WebSocket(wsUrl, { handshakeTimeout: 5000 });

      ws.once("open", () => {
        this.ws = ws;
        this.attachHandlers(ws);
        resolve();
      });

      ws.once("error", (err) => {
        reject(err instanceof Error ? err : new Error(String(err)));
      });
    });
  }

  private attachHandlers(ws: WebSocket): void {
    ws.on("message", (data) => {
      try {
        const raw =
          typeof data === "string"
            ? data
            : data instanceof Buffer
              ? data.toString("utf8")
              : Buffer.from(data as ArrayBuffer).toString("utf8");
        const parsed = JSON.parse(raw) as {
          id?: number;
          method?: string;
          params?: Record<string, unknown>;
          result?: unknown;
          error?: { message?: string };
        };

        if (typeof parsed.id === "number") {
          const p = this.pending.get(parsed.id);
          if (!p) return;
          this.pending.delete(parsed.id);
          if (parsed.error?.message) {
            p.reject(new Error(parsed.error.message));
          } else {
            p.resolve(parsed.result);
          }
        } else if (typeof parsed.method === "string") {
          const listeners = this.eventListeners.get(parsed.method);
          if (listeners) {
            for (const listener of listeners) {
              try {
                listener(parsed.params ?? {});
              } catch {
                // ignore listener errors
              }
            }
          }
        }
      } catch {
        // ignore parse errors
      }
    });

    ws.on("close", () => {
      this.rejectAllPending(new Error("CDP WebSocket closed"));
      this.ws = null;
      this.stopHealthPing();
      this.scheduleReconnect();
    });

    ws.on("error", (err) => {
      this.rejectAllPending(
        err instanceof Error ? err : new Error(String(err)),
      );
    });
  }

  private scheduleReconnect(): void {
    if (this.closed) return;
    const delay = this.backoffMs;
    this.backoffMs = Math.min(this.backoffMs * 2, 30_000);
    setTimeout(() => {
      if (this.closed) return;
      this.connect(this.connectHost, this.connectPort)
        .then(() => this.reinstallObserver())
        .catch(() => {
          // connect failure triggers another close → scheduleReconnect
        });
    }, delay).unref();
  }

  private async reinstallObserver(): Promise<void> {
    if (!this.responseCallback) return;
    try {
      await this.observeResponses(this.responseCallback);
    } catch {
      // will retry on next reconnect
    }
  }

  private startHealthPing(): void {
    this.stopHealthPing();
    this.pingTimer = setInterval(() => {
      if (!this.isConnected()) return;
      this.send("Runtime.evaluate", { expression: "1" }).catch(() => {
        // ping failed — close will trigger reconnect
        try {
          this.ws?.close();
        } catch {
          // ignore
        }
      });
    }, 10_000);
    this.pingTimer.unref();
  }

  private stopHealthPing(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  private rejectAllPending(err: Error): void {
    for (const [, p] of this.pending) {
      p.reject(err);
    }
    this.pending.clear();
  }
}

function normalizeCdpWsUrl(
  wsUrl: string,
  host: string,
  port: number,
): string {
  const ws = new URL(wsUrl);
  if (isLoopback(ws.hostname) && !isLoopback(host)) {
    ws.hostname = host;
    ws.port = String(port);
  }
  return ws.toString();
}

function isLoopback(hostname: string): boolean {
  return (
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "::1" ||
    hostname === "[::1]"
  );
}
