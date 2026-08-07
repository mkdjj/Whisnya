import { describe, expect, it, vi } from "vitest";

import { Allowlist } from "../src/security/allowlist.js";
import { Deduplicator } from "../src/utils/dedup.js";

describe("sidecar security", () => {
  it("fails closed until a non-empty allowlist has been synchronized", () => {
    const allowlist = new Allowlist();
    expect(allowlist.allows("123")).toBe(false);
    allowlist.update({ enabled: true, allowUsers: [] });
    expect(allowlist.allows("123")).toBe(false);
    allowlist.update({ enabled: true, allowUsers: ["123"] });
    expect(allowlist.allows("123")).toBe(true);
    expect(allowlist.allows("124")).toBe(false);
    allowlist.clear();
    expect(allowlist.allows("123")).toBe(false);
  });

  it("deduplicates self/message pairs with TTL and a hard size limit", () => {
    vi.useFakeTimers();
    const dedup = new Deduplicator({ ttlMs: 30 * 60_000, maxEntries: 2 });
    expect(dedup.seen("self:1")).toBe(false);
    expect(dedup.seen("self:1")).toBe(true);
    expect(dedup.seen("self:2")).toBe(false);
    expect(dedup.seen("self:3")).toBe(false);
    expect(dedup.size).toBe(2);
    vi.advanceTimersByTime(30 * 60_000 + 1);
    expect(dedup.seen("self:3")).toBe(false);
    vi.useRealTimers();
  });
});
