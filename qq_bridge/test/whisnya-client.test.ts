import { createServer } from "node:http";
import type { AddressInfo } from "node:net";

import { afterEach, describe, expect, it } from "vitest";

import { WhisnyaClient, WhisnyaHttpError } from "../src/whisnya/client.js";

describe("WhisnyaClient", () => {
  const servers: ReturnType<typeof createServer>[] = [];

  afterEach(async () => {
    await Promise.all(
      servers.splice(0).map(
        (server) => new Promise<void>((resolve) => server.close(() => resolve())),
      ),
    );
  });

  it("sends auth and protocol headers and parses a reply", async () => {
    const server = createServer((request, response) => {
      expect(request.headers.authorization).toBe("Bearer local-secret");
      expect(request.headers["x-whisnya-bridge-version"]).toBe("1");
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({ reply: "hi", sessionId: "s", bindingId: "b" }));
    });
    servers.push(server);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as AddressInfo).port;
    const client = new WhisnyaClient({
      url: `http://127.0.0.1:${port}`,
      token: "local-secret",
    });

    await expect(
      client.sendMessage({
        source: "onebot",
        messageId: "1",
        userId: "2",
        nickname: "Alice",
        text: "hello",
        timestamp: 3,
      }),
    ).resolves.toEqual({ reply: "hi", sessionId: "s", bindingId: "b" });
  });

  it("treats 204 as an intentional no-reply", async () => {
    const server = createServer((_request, response) => {
      response.statusCode = 204;
      response.end();
    });
    servers.push(server);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as AddressInfo).port;
    const client = new WhisnyaClient({
      url: `http://127.0.0.1:${port}`,
      token: "token",
    });

    await expect(
      client.sendMessage({
        source: "onebot",
        messageId: "1",
        userId: "2",
        nickname: "",
        text: "hello",
        timestamp: 3,
      }),
    ).resolves.toBeNull();
  });

  it.each([401, 500])("reports HTTP %s without manufacturing a QQ reply", async (status) => {
    const server = createServer((_request, response) => {
      response.statusCode = status;
      response.end("failure");
    });
    servers.push(server);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as AddressInfo).port;
    const client = new WhisnyaClient({
      url: `http://127.0.0.1:${port}`,
      token: "token",
    });

    await expect(
      client.sendMessage({
        source: "onebot",
        messageId: "1",
        userId: "2",
        nickname: "",
        text: "hello",
        timestamp: 3,
      }),
    ).rejects.toEqual(expect.objectContaining<Partial<WhisnyaHttpError>>({ status }));
  });
});
