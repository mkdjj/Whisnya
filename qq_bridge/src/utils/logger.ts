export type LogLevel = "debug" | "info" | "warn" | "error";

const LEVELS: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

export class Logger {
  constructor(private readonly level: LogLevel = "info") {}

  debug(event: string, details: Record<string, unknown> = {}): void {
    this.write("debug", event, details);
  }

  info(event: string, details: Record<string, unknown> = {}): void {
    this.write("info", event, details);
  }

  warn(event: string, details: Record<string, unknown> = {}): void {
    this.write("warn", event, details);
  }

  error(event: string, details: Record<string, unknown> = {}): void {
    this.write("error", event, details);
  }

  private write(level: LogLevel, event: string, details: Record<string, unknown>): void {
    if (LEVELS[level] < LEVELS[this.level]) return;
    const line = JSON.stringify({ time: new Date().toISOString(), level, event, ...details });
    (level === "error" ? console.error : level === "warn" ? console.warn : console.log)(line);
  }
}
