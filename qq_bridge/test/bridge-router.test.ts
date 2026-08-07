import { describe, expect, it, vi } from "vitest";

import { BridgeMessageRouter } from "../src/bridge.js";
import type { OneBotPrivateMessage } from "../src/onebot/types.js";
import { WhisnyaHttpError } from "../src/whisnya/client.js";

const message: OneBotPrivateMessage = {
  messageId: "message-1",
  userId: "allowed",
  selfId: "self",
  nickname: "Alice",
  text: "hello",
  time: 1786110000,
};

describe("BridgeMessageRouter", () => {
  it("does not call Whisnya for users absent from its synchronized allowlist", async () => {
    const client = {
      getConfig: vi.fn(async () => ({ enabled: true, allowUsers: ["allowed"] })),
      sendMessage: vi.fn(),
    };
    const send = vi.fn();
    const router = new BridgeMessageRouter(client, send);
    await router.syncConfig();

    await router.handle({ ...message, userId: "unknown" });

    expect(client.sendMessage).not.toHaveBeenCalled();
    expect(send).not.toHaveBeenCalled();
  });

  it("forwards an allowed message once and sends the returned reply once", async () => {
    const client = {
      getConfig: vi.fn(async () => ({ enabled: true, allowUsers: ["allowed"] })),
      sendMessage: vi.fn(async () => ({ reply: "hi", sessionId: "s", bindingId: "b" })),
    };
    const send = vi.fn(async () => ({ messageId: "sent" }));
    const router = new BridgeMessageRouter(client, send);
    await router.syncConfig();

    await router.handle(message);
    await router.handle(message);

    expect(client.sendMessage).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledOnce();
    expect(send).toHaveBeenCalledWith("allowed", "hi");
  });

  it.each([401, 500])("does not send or throw when Whisnya returns HTTP %s", async (status) => {
    const client = {
      getConfig: vi.fn(async () => ({ enabled: true, allowUsers: ["allowed"] })),
      sendMessage: vi.fn(async () => {
        throw new WhisnyaHttpError(status, "/v1/qq/message");
      }),
    };
    const send = vi.fn();
    const router = new BridgeMessageRouter(client, send);
    await router.syncConfig();

    await expect(router.handle(message)).resolves.toBeUndefined();
    expect(send).not.toHaveBeenCalled();
  });

  it("fails closed when Whisnya config refresh fails", async () => {
    const client = {
      getConfig: vi
        .fn()
        .mockResolvedValueOnce({ enabled: true, allowUsers: ["allowed"] })
        .mockRejectedValueOnce(new Error("offline")),
      sendMessage: vi.fn(),
    };
    const router = new BridgeMessageRouter(client, vi.fn());
    await router.syncConfig();
    await router.syncConfig();

    await router.handle(message);
    expect(client.sendMessage).not.toHaveBeenCalled();
  });
});
