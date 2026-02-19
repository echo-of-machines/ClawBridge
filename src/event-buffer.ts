import type { EventFrame } from "./gateway-client.js";

export type BufferedEvent = {
  ts: number;
  frame: EventFrame;
};

const DEFAULT_CAPACITY = 1000;

export class EventBuffer {
  private buf: BufferedEvent[] = [];
  private capacity: number;

  constructor(capacity = DEFAULT_CAPACITY) {
    this.capacity = capacity;
  }

  push(frame: EventFrame): void {
    if (this.buf.length >= this.capacity) {
      this.buf.shift();
    }
    this.buf.push({ ts: Date.now(), frame });
  }

  query(opts?: {
    eventType?: string;
    since?: number;
    limit?: number;
  }): BufferedEvent[] {
    let results = this.buf;

    if (opts?.eventType) {
      results = results.filter((e) => e.frame.event === opts.eventType);
    }
    if (opts?.since) {
      const cutoff = opts.since;
      results = results.filter((e) => e.ts >= cutoff);
    }
    if (opts?.limit && opts.limit > 0) {
      results = results.slice(-opts.limit);
    }

    return results;
  }

  clear(): void {
    this.buf = [];
  }

  get size(): number {
    return this.buf.length;
  }
}
