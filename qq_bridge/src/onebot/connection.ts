import WebSocket from "ws";

import { OneBotActions } from "./actions.js";
import { parsePrivateMessage } from "./events.js";
import { ReconnectPolicy } from "./reconnect.js";
import type {
  JsonObject,
  OneBotConfig,
  OneBotConnectionStatus,
  OneBotLoginInfo,
  OneBotPrivateMessage,
  OneBotSendResult,
} from "./types.js";

export interface OneBotConnectionOptions {
  reconnectPolicy?: ReconnectPolicy;
}

type MessageHandler = (message: OneBotPrivateMessage) => Promise<void>;
type StatusHandler = (status: OneBotConnectionStatus) => void;

export class OneBotConnection {
  private socket: WebSocket | null = null;
  private actions: OneBotActions | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private connectAttempt: Promise<void> | null = null;
  private stopped = true;
  private readonly messageHandlers = new Set<MessageHandler>();
  private readonly statusHandlers = new Set<StatusHandler>();
  private readonly reconnectPolicy: ReconnectPolicy;
  private loginInfo: OneBotLoginInfo | null = null;

  constructor(
    private readonly config: OneBotConfig,
    options: OneBotConnectionOptions = {},
  ) {
    const url = new URL(config.url);
    if (url.protocol !== "ws:" && url.protocol !== "wss:") {
      throw new Error("OneBot URL must use ws or wss");
    }
    this.reconnectPolicy = options.reconnectPolicy ?? new ReconnectPolicy();
  }

  onPrivateMessage(handler: MessageHandler): void {
    this.messageHandlers.add(handler);
  }

  onStatus(handler: StatusHandler): void {
    this.statusHandlers.add(handler);
  }

  async start(): Promise<void> {
    if (!this.stopped) {
      await this.connectAttempt;
      return;
    }
    this.stopped = false;
    await this.connect();
  }

  async stop(): Promise<void> {
    this.stopped = true;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.actions?.rejectAll(new Error("OneBot disconnected"));
    this.actions = null;
    const socket = this.socket;
    this.socket = null;
    this.loginInfo = null;
    if (socket !== null && socket.readyState !== WebSocket.CLOSED) {
      await new Promise<void>((resolve) => {
        const timeout = setTimeout(resolve, 1000);
        socket.once("close", () => {
          clearTimeout(timeout);
          resolve();
        });
        socket.close();
      });
    }
    this.emitStatus(false, null);
  }

  async sendPrivateMessage(userId: string, text: string): Promise<OneBotSendResult> {
    const data = await this.call("send_private_msg", { user_id: userId, message: text });
    const value = asObject(data);
    return { messageId: stringId(value.message_id) };
  }

  async getLoginInfo(): Promise<OneBotLoginInfo> {
    const data = asObject(await this.call("get_login_info", {}));
    const info = {
      userId: stringId(data.user_id),
      nickname: typeof data.nickname === "string" ? data.nickname.trim() : "",
    };
    if (!info.userId) throw new Error("get_login_info returned no user id");
    this.loginInfo = info;
    return info;
  }

  private async call(action: string, params: JsonObject): Promise<unknown> {
    const actions = this.actions;
    if (actions === null || this.socket?.readyState !== WebSocket.OPEN) {
      throw new Error("OneBot WebSocket is not connected");
    }
    return actions.call(action, params);
  }

  private async connect(): Promise<void> {
    if (this.connectAttempt !== null) return this.connectAttempt;
    this.connectAttempt = this.connectOnce()
      .catch((error: unknown) => {
        this.emitStatus(false, errorMessage(error));
        this.scheduleReconnect();
      })
      .finally(() => {
        this.connectAttempt = null;
      });
    return this.connectAttempt;
  }

  private async connectOnce(): Promise<void> {
    if (this.stopped) return;
    const headers: Record<string, string> = {};
    if (this.config.accessToken.trim()) {
      headers.authorization = `Bearer ${this.config.accessToken.trim()}`;
    }
    const socket = new WebSocket(this.config.url, { headers });
    const actions = new OneBotActions((payload) => {
      if (socket.readyState !== WebSocket.OPEN) {
        throw new Error("OneBot WebSocket is not connected");
      }
      socket.send(JSON.stringify(payload));
    });
    this.socket = socket;
    this.actions = actions;

    socket.on("message", (raw) => {
      let payload: unknown;
      try {
        payload = JSON.parse(raw.toString());
      } catch {
        return;
      }
      if (actions.handlePayload(payload)) return;
      const message = parsePrivateMessage(payload);
      if (message !== null) void this.dispatchMessage(message);
    });
    socket.on("close", () => this.handleClose(socket, actions));

    await new Promise<void>((resolve, reject) => {
      const onOpen = (): void => {
        socket.off("error", onError);
        resolve();
      };
      const onError = (error: Error): void => {
        socket.off("open", onOpen);
        reject(error);
      };
      socket.once("open", onOpen);
      socket.once("error", onError);
    });
    if (this.stopped || this.socket !== socket) return;
    const login = await this.getLoginInfo();
    this.reconnectPolicy.reset();
    this.emitStatus(true, null, login);
  }

  private handleClose(socket: WebSocket, actions: OneBotActions): void {
    actions.rejectAll(new Error("OneBot disconnected"));
    if (this.socket !== socket) return;
    this.socket = null;
    this.actions = null;
    this.loginInfo = null;
    this.emitStatus(false, this.stopped ? null : "OneBot disconnected");
    this.scheduleReconnect();
  }

  private scheduleReconnect(): void {
    if (this.stopped || this.reconnectTimer !== null) return;
    const delay = this.reconnectPolicy.nextDelay();
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      void this.connect();
    }, delay);
  }

  private async dispatchMessage(message: OneBotPrivateMessage): Promise<void> {
    for (const handler of this.messageHandlers) {
      try {
        await handler(message);
      } catch {
        // Handler failures are isolated from the WebSocket read loop.
      }
    }
  }

  private emitStatus(
    connected: boolean,
    lastError: string | null,
    login = this.loginInfo,
  ): void {
    const status: OneBotConnectionStatus = {
      connected,
      selfId: login?.userId ?? "",
      nickname: login?.nickname ?? "",
      lastError,
    };
    for (const handler of this.statusHandlers) handler(status);
  }
}

function asObject(value: unknown): JsonObject {
  return typeof value === "object" && value !== null ? value as JsonObject : {};
}

function stringId(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "bigint") return String(value);
  return "";
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
