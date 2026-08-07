export interface DeduplicatorOptions {
  ttlMs?: number;
  maxEntries?: number;
}

export class Deduplicator {
  private readonly entries = new Map<string, number>();
  private readonly ttlMs: number;
  private readonly maxEntries: number;

  constructor(options: DeduplicatorOptions = {}) {
    this.ttlMs = options.ttlMs ?? 30 * 60_000;
    this.maxEntries = options.maxEntries ?? 1000;
  }

  get size(): number {
    return this.entries.size;
  }

  seen(key: string, now = Date.now()): boolean {
    this.prune(now);
    const expiresAt = this.entries.get(key);
    if (expiresAt !== undefined && expiresAt > now) return true;
    this.entries.delete(key);
    this.entries.set(key, now + this.ttlMs);
    while (this.entries.size > this.maxEntries) {
      const oldest = this.entries.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      this.entries.delete(oldest);
    }
    return false;
  }

  prune(now = Date.now()): void {
    for (const [key, expiresAt] of this.entries) {
      if (expiresAt <= now) this.entries.delete(key);
    }
  }
}
