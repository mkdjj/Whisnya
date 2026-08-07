import { createServer } from "node:http";
import type { AddressInfo } from "node:net";

import { afterEach, describe, expect, it } from "vitest";
import { WebSocketServer } from "ws";

import { OneBotConnection } from "../src/onebot/connection.js";
import { ReconnectPolicy } from "../src/onebot/reconnect.js";

describe("OneBotConnection", () => {
  const cleanups: Array<() => Promise<void>> = [];

  afterEach(async () => {
    await Promise.all(cleanups.splice(0).map((cleanup) => cleanup()));
  });

  it("installs the read loop before get_login_info and sends private messages", async () => {
    const server = createServer();
    const webSockets = new WebSocketServer({ server });
    const receivedActions: Array<Record<string, unknown>> = [];
    let authorization: string | undefined;
    webSockets.on("connection", (socket, request) => {
      authorization = request.headers.authorization;
      socket.on("message", (raw) => {
        const action = JSON.parse(raw.toString()) as Record<string, unknown>;
        receivedActions.push(action);
        const data = action.action === "get_login_info"
          ? { user_id: "90001", nickname: "Bot" }
          : { message_id: "sent-1" };
        socket.send(JSON.stringify({ echo: action.echo, retcode: 0, data }));
      });
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as AddressInfo).port;
    const connection = new OneBotConnection({
      url: `ws://127.0.0.1:${port}`,
      accessToken: "napcat-token",
    });
    cleanups.push(async () => {
      await connection.stop();
      await new Promise<void>((resolve) => webSockets.close(() => resolve()));
      await new Promise<void>((resolve) => server.close(() => resolve()));
    });

    await connection.start();
    await expect(connection.getLoginInfo()).resolves.toEqual({
      userId: "90001",
      nickname: "Bot",
    });
    await expect(connection.sendPrivateMessage("123456789", "hello")).resolves.toEqual({
      messageId: "sent-1",
    });

    expect(authorization).toBe("Bearer napcat-token");
    expect(receivedActions.map((action) => action.action)).toEqual([
      "get_login_info",
      "get_login_info",
      "send_private_msg",
    ]);
    expect((receivedActions[2].params as Record<string, unknown>).user_id).toBe("123456789");
  });

  it("reconnects after an unexpected disconnect", async () => {
    const server = createServer();
    const webSockets = new WebSocketServer({ server });
    let connections = 0;
    webSockets.on("connection", (socket) => {
      connections += 1;
      socket.on("message", (raw) => {
        const action = JSON.parse(raw.toString()) as Record<string, unknown>;
        socket.send(JSON.stringify({
          echo: action.echo,
          retcode: 0,
          data: { user_id: "1", nickname: "Bot" },
        }));
        if (connections === 1) setTimeout(() => socket.close(), 5);
      });
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as AddressInfo).port;
    const connection = new OneBotConnection(
      { url: `ws://127.0.0.1:${port}`, accessToken: "" },
      { reconnectPolicy: new ReconnectPolicy([5, 10]) },
    );
    cleanups.push(async () => {
      await connection.stop();
      await new Promise<void>((resolve) => webSockets.close(() => resolve()));
      await new Promise<void>((resolve) => server.close(() => resolve()));
    });

    await connection.start();
    await expect.poll(() => connections).toBeGreaterThanOrEqual(2);
  });
});
