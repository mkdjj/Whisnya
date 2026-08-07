import { describe, expect, it } from "vitest";

import { ReconnectPolicy } from "../src/onebot/reconnect.js";

describe("ReconnectPolicy", () => {
  it("backs off without entering a high-frequency loop and resets", () => {
    const policy = new ReconnectPolicy([1000, 2000, 5000, 10000, 30000]);
    expect([
      policy.nextDelay(),
      policy.nextDelay(),
      policy.nextDelay(),
      policy.nextDelay(),
      policy.nextDelay(),
      policy.nextDelay(),
    ]).toEqual([1000, 2000, 5000, 10000, 30000, 30000]);
    policy.reset();
    expect(policy.nextDelay()).toBe(1000);
  });
});
