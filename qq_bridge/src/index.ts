import { pathToFileURL } from "node:url";

import { BridgeMessageRouter } from "./bridge.js";
import { loadConfig } from "./config.js";
import { OneBotConnection } from "./onebot/connection.js";
import type { OneBotConnectionStatus } from "./onebot/types.js";
import { Logger } from "./utils/logger.js";
import { WhisnyaClient } from "./whisnya/client.js";

const STATUS_INTERVAL_MS = 30_000;
const CONFIG_INTERVAL_MS = 60_000;

export async function run(): Promise<() => Promise<void>> {
  const config = await loadConfig();
  const logger = new Logger(config.logLevel);
  const whisnya = new WhisnyaClient(config.whisnya);
  const onebot = new OneBotConnection(config.onebot);
  const router = new BridgeMessageRouter(
    whisnya,
    (userId, text) => onebot.sendPrivateMessage(userId, text),
    logger,
  );
  let status: OneBotConnectionStatus = {
    connected: false,
    selfId: "",
    nickname: "",
    lastError: null,
  };
  let lastMessageAt: string | null = null;

  onebot.onStatus((value) => {
    status = value;
    logger.info(value.connected ? "onebot_connected" : "onebot_disconnected", {
      selfId: value.selfId ? `***${value.selfId.slice(-4)}` : "",
      error: value.lastError,
    });
  });
  onebot.onPrivateMessage(async (message) => {
    lastMessageAt = new Date().toISOString();
    await router.handle(message);
  });

  await router.syncConfig();
  await onebot.start();
  const configTimer = setInterval(() => void router.syncConfig(), CONFIG_INTERVAL_MS);
  const reportStatus = async (): Promise<void> => {
    try {
      await whisnya.reportStatus({ ...status, lastMessageAt });
    } catch (error) {
      logger.warn("status_report_failed", {
        error: error instanceof Error ? error.constructor.name : "UnknownError",
      });
    }
  };
  await reportStatus();
  const statusTimer = setInterval(() => void reportStatus(), STATUS_INTERVAL_MS);

  const stop = async (): Promise<void> => {
    clearInterval(configTimer);
    clearInterval(statusTimer);
    await onebot.stop();
  };
  process.once("SIGINT", () => void stop().finally(() => process.exit(0)));
  process.once("SIGTERM", () => void stop().finally(() => process.exit(0)));
  return stop;
}

const entry = process.argv[1] ? pathToFileURL(process.argv[1]).href : "";
if (import.meta.url === entry) {
  run().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
