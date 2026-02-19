export interface ClaudeDesktopConfig {
  enabled: boolean;
  cdpPort: number;
  cdpHost: string;
  responseTimeoutMs: number;
  messagePrefix: boolean;
}
