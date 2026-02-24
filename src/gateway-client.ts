import { randomUUID } from "node:crypto";
import WebSocket from "ws";
import {
  buildDeviceAuthPayload,
  publicKeyRawBase64Url,
  signDevicePayload,
  type DeviceIdentity,
} from "./device-identity.js";

// --- Frame types (loose parsing — no additionalProperties: false) ---

export type EventFrame = {
  type: "event";
  event: string;
  payload?: unknown;
  seq?: number;
  stateVersion?: unknown;
};

export type ResponseFrame = {
  type: "res";
  id: string;
  ok: boolean;
  payload?: unknown;
  error?: { message?: string };
};

export type HelloOk = {
  type: "hello-ok";
  protocol: number;
  server: { version: string; connId: string };
  features: { methods: string[]; events: string[] };
  snapshot?: unknown;
  policy: { maxPayload: number; tickIntervalMs: number };
  auth?: { deviceToken?: string; role?: string; scopes?: string[] };
};

type Pending = {
  resolve: (value: unknown) => void;
  reject: (err: unknown) => void;
};

export type GatewayClientOptions = {
  url?: string;
  token?: string;
  deviceIdentity?: DeviceIdentity;
  onEvent?: (evt: EventFrame) => void;
  onHelloOk?: (hello: HelloOk) => void;
  onClose?: (code: number, reason: string) => void;
  onConnectError?: (err: Error) => void;
};

const PROTOCOL_VERSION = 3;

export class GatewayClient {
  private ws: WebSocket | null = null;
  private opts: GatewayClientOptions;
  private pending = new Map<string, Pending>();
  private backoffMs = 1000;
  private closed = false;
  private connectNonce: string | null = null;
  private connectSent = false;
  private lastTick: number | null = null;
  private tickIntervalMs = 30_000;
  private tickTimer: ReturnType<typeof setInterval> | null = null;

  constructor(opts: GatewayClientOptions) {
    this.opts = opts;
  }

  start(): void {
    if (this.closed) return;
    const url = this.opts.url ?? "ws://127.0.0.1:18789";
    this.ws = new WebSocket(url, { maxPayload: 25 * 1024 * 1024 });

    this.ws.on("open", () => {
      // Do NOT send connect here — wait for connect.challenge.
    });
    this.ws.on("message", (data) => {
      const raw = typeof data === "string" ? data : Buffer.from(data as ArrayBuffer).toString("utf8");
      this.handleMessage(raw);
    });
    this.ws.on("close", (code, reason) => {
      const reasonText = typeof reason === "string" ? reason : Buffer.from(reason).toString("utf8");
      this.ws = null;
      this.flushPendingErrors(new Error(`gateway closed (${code}): ${reasonText}`));
      this.scheduleReconnect();
      this.opts.onClose?.(code, reasonText);
    });
    this.ws.on("error", (err) => {
      if (!this.connectSent) {
        this.opts.onConnectError?.(err instanceof Error ? err : new Error(String(err)));
      }
    });
  }

  stop(): void {
    this.closed = true;
    if (this.tickTimer) {
      clearInterval(this.tickTimer);
      this.tickTimer = null;
    }
    this.ws?.close();
    this.ws = null;
    this.flushPendingErrors(new Error("gateway client stopped"));
  }

  isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN && this.connectSent;
  }

  async request<T = Record<string, unknown>>(
    method: string,
    params?: unknown,
  ): Promise<T> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error("gateway not connected");
    }
    const id = randomUUID();
    const frame = { type: "req" as const, id, method, params };
    const p = new Promise<T>((resolve, reject) => {
      this.pending.set(id, {
        resolve: (v) => resolve(v as T),
        reject,
      });
    });
    this.ws.send(JSON.stringify(frame));
    return p;
  }

  // --- Private ---

  private sendConnect(): void {
    if (this.connectSent) return;
    this.connectSent = true;

    const clientId = "clawbridge-mcp";
    const clientMode = "backend";
    const role = "operator";
    const scopes = ["operator.admin"];
    const nonce = this.connectNonce ?? undefined;
    const authToken = this.opts.token;

    const device = (() => {
      const id = this.opts.deviceIdentity;
      if (!id) return undefined;
      const signedAtMs = Date.now();
      const payload = buildDeviceAuthPayload({
        deviceId: id.deviceId,
        clientId,
        clientMode,
        role,
        scopes,
        signedAtMs,
        token: authToken ?? null,
        nonce,
      });
      const signature = signDevicePayload(id.privateKeyPem, payload);
      return {
        id: id.deviceId,
        publicKey: publicKeyRawBase64Url(id.publicKeyPem),
        signature,
        signedAt: signedAtMs,
        nonce,
      };
    })();

    const params = {
      minProtocol: PROTOCOL_VERSION,
      maxProtocol: PROTOCOL_VERSION,
      client: {
        id: clientId,
        version: "0.3.0",
        platform: process.platform,
        mode: clientMode,
      },
      caps: [],
      auth: authToken ? { token: authToken } : undefined,
      role,
      scopes,
      device,
    };

    void this.request<HelloOk>("connect", params)
      .then((helloOk) => {
        this.backoffMs = 1000;
        this.tickIntervalMs =
          typeof helloOk.policy?.tickIntervalMs === "number"
            ? helloOk.policy.tickIntervalMs
            : 30_000;
        this.lastTick = Date.now();
        this.startTickWatch();
        this.opts.onHelloOk?.(helloOk);
      })
      .catch((err) => {
        this.opts.onConnectError?.(
          err instanceof Error ? err : new Error(String(err)),
        );
        this.ws?.close(1008, "connect failed");
      });
  }

  private handleMessage(raw: string): void {
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return;
    }

    // Event frame
    if (parsed.type === "event") {
      const evt = parsed as unknown as EventFrame;

      // Handle connect.challenge before anything else.
      if (evt.event === "connect.challenge") {
        const payload = evt.payload as { nonce?: unknown } | undefined;
        const nonce =
          payload && typeof payload.nonce === "string" ? payload.nonce : null;
        if (nonce) {
          this.connectNonce = nonce;
          this.sendConnect();
        }
        return;
      }

      if (evt.event === "tick") {
        this.lastTick = Date.now();
      }

      this.opts.onEvent?.(evt);
      return;
    }

    // Response frame
    if (parsed.type === "res") {
      const res = parsed as unknown as ResponseFrame;
      const pending = this.pending.get(res.id);
      if (!pending) return;
      this.pending.delete(res.id);
      if (res.ok) {
        pending.resolve(res.payload);
      } else {
        pending.reject(new Error(res.error?.message ?? "unknown error"));
      }
    }
  }

  private scheduleReconnect(): void {
    if (this.closed) return;
    if (this.tickTimer) {
      clearInterval(this.tickTimer);
      this.tickTimer = null;
    }
    const delay = this.backoffMs;
    this.backoffMs = Math.min(this.backoffMs * 2, 30_000);
    this.connectNonce = null;
    this.connectSent = false;
    setTimeout(() => this.start(), delay).unref();
  }

  private flushPendingErrors(err: Error): void {
    for (const [, p] of this.pending) {
      p.reject(err);
    }
    this.pending.clear();
  }

  private startTickWatch(): void {
    if (this.tickTimer) clearInterval(this.tickTimer);
    const interval = Math.max(this.tickIntervalMs, 1000);
    this.tickTimer = setInterval(() => {
      if (this.closed || !this.lastTick) return;
      if (Date.now() - this.lastTick > this.tickIntervalMs * 2) {
        this.ws?.close(4000, "tick timeout");
      }
    }, interval);
  }
}
