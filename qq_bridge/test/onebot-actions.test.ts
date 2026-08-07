import { describe, expect, it, vi } from "vitest";

import { OneBotActions } from "../src/onebot/actions.js";

describe("OneBotActions", () => {
  it("matches concurrent out-of-order responses by echo", async () => {
    const sent: Array<Record<string, unknown>> = [];
    const actions = new OneBotActions((payload) => sent.push(payload));
    const first = actions.call("first", { user_id: "1" });
    const second = actions.call("second", { user_id: "2" });

    actions.handlePayload({ echo: sent[1].echo, retcode: 0, data: "second" });
    actions.handlePayload({ echo: sent[0].echo, retcode: 0, data: "first" });

    await expect(first).resolves.toBe("first");
    await expect(second).resolves.toBe("second");
    expect(actions.pendingCount).toBe(0);
  });

  it("rejects non-zero retcodes", async () => {
    const sent: Array<Record<string, unknown>> = [];
    const actions = new OneBotActions((payload) => sent.push(payload));
    const result = actions.call("send_private_msg", {});
    actions.handlePayload({ echo: sent[0].echo, retcode: 100, message: "bad" });

    await expect(result).rejects.toThrow("retcode=100");
  });

  it("times out pending actions", async () => {
    vi.useFakeTimers();
    const actions = new OneBotActions(() => {}, 15_000);
    const result = actions.call("slow", {});
    const expectation = expect(result).rejects.toThrow("timed out");
    await vi.advanceTimersByTimeAsync(15_001);
    await expectation;
    expect(actions.pendingCount).toBe(0);
    vi.useRealTimers();
  });

  it("rejects and clears every pending action on disconnect", async () => {
    const actions = new OneBotActions(() => {});
    const first = actions.call("first", {});
    const second = actions.call("second", {});
    const firstExpectation = expect(first).rejects.toThrow("disconnected");
    const secondExpectation = expect(second).rejects.toThrow("disconnected");
    actions.rejectAll(new Error("OneBot disconnected"));

    await firstExpectation;
    await secondExpectation;
    expect(actions.pendingCount).toBe(0);
  });
});
