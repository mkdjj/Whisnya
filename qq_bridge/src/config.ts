import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { LogLevel } from "./utils/logger.js";

export interface BridgeConfig {
  onebot: {
    url: string;
    accessToken: string;
  };
  whisnya: {
    url: string;
    token: string;
  };
  logLevel: LogLevel;
}

export async function loadConfig(path = process.env.WHISNYA_QQ_BRIDGE_CONFIG ?? "config.json"):
Promise<BridgeConfig> {
  const parsed = JSON.parse(await readFile(resolve(path), "utf8")) as unknown;
  if (typeof parsed !== "object" || parsed === null) throw new Error("Invalid config.json");
  const value = parsed as Record<string, unknown>;
  const onebot = objectAt(value, "onebot");
  const whisnya = objectAt(value, "whisnya");
  const onebotUrl = stringAt(onebot, "url", "ws://127.0.0.1:3001");
  const whisnyaUrl = stringAt(whisnya, "url", "http://127.0.0.1:17891");
  const token = stringAt(whisnya, "token", "").trim();
  if (!token) throw new Error("whisnya.token is required");
  const logLevel = stringAt(value, "logLevel", "info");
  if (!["debug", "info", "warn", "error"].includes(logLevel)) {
    throw new Error("logLevel must be debug, info, warn, or error");
  }
  return {
    onebot: {
      url: onebotUrl,
      accessToken: stringAt(onebot, "accessToken", ""),
    },
    whisnya: { url: whisnyaUrl, token },
    logLevel: logLevel as LogLevel,
  };
}

function objectAt(value: Record<string, unknown>, key: string): Record<string, unknown> {
  const item = value[key];
  return typeof item === "object" && item !== null ? item as Record<string, unknown> : {};
}

function stringAt(value: Record<string, unknown>, key: string, fallback: string): string {
  return typeof value[key] === "string" ? value[key] as string : fallback;
}
