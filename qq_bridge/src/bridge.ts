import type { OneBotPrivateMessage, OneBotSendResult } from "./onebot/types.js";
import { Allowlist } from "./security/allowlist.js";
import { Deduplicator } from "./utils/dedup.js";
import { Logger } from "./utils/logger.js";
import type { WhisnyaClient } from "./whisnya/client.js";
import type { WhisnyaConfig, WhisnyaReply } from "./whisnya/types.js";

type WhisnyaRouterClient = Pick<WhisnyaClient, "getConfig" | "sendMessage">;
type SendPrivateMessage = (userId: string, text: string) => Promise<OneBotSendResult>;

export class BridgeMessageRouter {
  private readonly allowlist = new Allowlist();
  private readonly dedup = new Deduplicator();

  constructor(
    private readonly client: WhisnyaRouterClient,
    private readonly sendPrivateMessage: SendPrivateMessage,
    private readonly logger = new Logger("error"),
  ) {}

  async syncConfig(): Promise<WhisnyaConfig | null> {
    try {
      const config = await this.client.getConfig();
      this.allowlist.update(config);
      return config;
    } catch (error) {
      this.allowlist.clear();
      this.logger.warn("config_sync_failed", { error: errorName(error) });
      return null;
    }
  }

  async handle(message: OneBotPrivateMessage): Promise<void> {
    if (!this.allowlist.allows(message.userId)) return;
    if (this.dedup.seen(`${message.selfId}:${message.messageId}`)) return;
    this.logger.info("private_message", {
      user: redactId(message.userId),
      messageId: message.messageId,
      textLength: message.text.length,
    });
    try {
      const reply = await this.client.sendMessage({
        source: "onebot",
        messageId: message.messageId,
        userId: message.userId,
        nickname: message.nickname,
        text: message.text,
        timestamp: message.time,
      });
      if (reply === null) return;
      const replies = validReplies(reply);
      for (const text of replies) {
        const sent = await this.sendPrivateMessage(message.userId, text);
        this.logger.info("private_reply_sent", {
          user: redactId(message.userId),
          messageId: sent.messageId,
          textLength: text.length,
        });
      }
    } catch (error) {
      this.logger.warn("private_reply_failed", {
        user: redactId(message.userId),
        messageId: message.messageId,
        error: errorName(error),
      });
    }
  }
}

function validReplies(value: WhisnyaReply): string[] {
  const chunks = Array.isArray(value.replies)
    ? value.replies.filter((item) => typeof item === "string" && item.trim().length > 0)
    : [];
  if (chunks.length > 0) return chunks;
  return typeof value.reply === "string" && value.reply.trim().length > 0
    ? [value.reply]
    : [];
}

function redactId(value: string): string {
  return value.length <= 4 ? "****" : `***${value.slice(-4)}`;
}

function errorName(error: unknown): string {
  return error instanceof Error ? error.constructor.name : "UnknownError";
}
