import { authenticatedHeaders, BRIDGE_PROTOCOL_VERSION } from "../security/auth.js";
import type {
  WhisnyaBridgeStatus,
  WhisnyaConfig,
  WhisnyaMessage,
  WhisnyaReply,
} from "./types.js";

export interface WhisnyaClientConfig {
  url: string;
  token: string;
}

export class WhisnyaHttpError extends Error {
  constructor(public readonly status: number, path: string) {
    super(`Whisnya ${path} returned HTTP ${status}`);
  }
}

function localBaseUrl(raw: string): URL {
  const url = new URL(raw);
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (url.protocol !== "http:" || !["127.0.0.1", "localhost", "::1"].includes(host)) {
    throw new Error("Whisnya URL must use loopback HTTP");
  }
  url.pathname = url.pathname.replace(/\/$/, "");
  return url;
}

export class WhisnyaClient {
  private readonly baseUrl: URL;
  private readonly token: string;

  constructor(config: WhisnyaClientConfig) {
    this.baseUrl = localBaseUrl(config.url);
    this.token = config.token.trim();
    if (!this.token) throw new Error("Whisnya bridge token is required");
  }

  async health(): Promise<{ service: string; qqBridgeApi: number }> {
    const response = await this.request("/health", { authenticated: false });
    return await response.json() as { service: string; qqBridgeApi: number };
  }

  async getConfig(): Promise<WhisnyaConfig> {
    const response = await this.request("/v1/qq/config");
    const value = await response.json() as Partial<WhisnyaConfig>;
    return {
      enabled: value.enabled === true,
      allowUsers: Array.isArray(value.allowUsers)
        ? value.allowUsers.filter((item): item is string => typeof item === "string")
        : [],
    };
  }

  async sendMessage(message: WhisnyaMessage): Promise<WhisnyaReply | null> {
    const response = await this.request("/v1/qq/message", {
      method: "POST",
      body: message,
    });
    if (response.status === 204) return null;
    return await response.json() as WhisnyaReply;
  }

  async reportStatus(status: WhisnyaBridgeStatus): Promise<void> {
    await this.request("/v1/qq/status", { method: "POST", body: status });
  }

  private async request(
    path: string,
    options: {
      method?: "GET" | "POST";
      body?: unknown;
      authenticated?: boolean;
    } = {},
  ): Promise<Response> {
    const authenticated = options.authenticated ?? true;
    const headers: Record<string, string> = {
      accept: "application/json",
      ...(authenticated ? authenticatedHeaders(this.token) : {}),
    };
    if (options.body !== undefined) headers["content-type"] = "application/json";
    const response = await fetch(new URL(path, this.baseUrl), {
      method: options.method ?? "GET",
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status === 426) {
      throw new Error(`Unsupported Whisnya bridge protocol ${BRIDGE_PROTOCOL_VERSION}`);
    }
    if (!response.ok) throw new WhisnyaHttpError(response.status, path);
    return response;
  }
}
