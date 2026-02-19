import type { CdpBridge } from "./cdp-bridge.js";

type PendingMessage = {
  channelId: string;
  from: string;
  injectedAt: number;
};

const CONTEXT_TIMEOUT_MS = 300_000; // 5 min

export class ResponseRouter {
  private pendingMessages: PendingMessage[] = [];
  private responseCallback:
    | ((channelId: string, from: string, text: string) => void)
    | null = null;

  /**
   * Set the callback that delivers responses back to originating channels.
   * Called by the plugin entry when wiring up the outbound pipeline.
   */
  onResponse(
    callback: (channelId: string, from: string, text: string) => void,
  ): void {
    this.responseCallback = callback;
  }

  /**
   * Record that a message from channelId:from was injected into Claude Desktop.
   * Called by the message_received hook.
   */
  trackInjection(channelId: string, from: string): void {
    this.pendingMessages.push({
      channelId,
      from,
      injectedAt: Date.now(),
    });
    this.pruneStale();
  }

  /**
   * Start observing CDP bridge responses and routing them back.
   */
  startObserving(bridge: CdpBridge): void {
    bridge.observeResponses((data) => {
      if (data.type !== "response" || !data.text) return;
      this.routeResponse(data.text);
    }).catch(() => {
      // observer setup failure — will retry on reconnect
    });
  }

  private routeResponse(text: string): void {
    this.pruneStale();
    const pending = this.pendingMessages.shift();
    if (!pending) return;
    if (!this.responseCallback) return;
    this.responseCallback(pending.channelId, pending.from, text);
  }

  private pruneStale(): void {
    const cutoff = Date.now() - CONTEXT_TIMEOUT_MS;
    while (
      this.pendingMessages.length > 0 &&
      this.pendingMessages[0]!.injectedAt < cutoff
    ) {
      this.pendingMessages.shift();
    }
  }
}
