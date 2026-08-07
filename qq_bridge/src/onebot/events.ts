import type { JsonObject, OneBotPrivateMessage } from "./types.js";

function stringId(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "bigint") return String(value);
  return "";
}

function textFromSegments(value: unknown): string {
  if (!Array.isArray(value)) return "";
  return value
    .map((item) => {
      if (typeof item !== "object" || item === null) return "";
      const segment = item as JsonObject;
      if (segment.type !== "text") return "";
      const data = segment.data;
      if (typeof data !== "object" || data === null) return "";
      const text = (data as JsonObject).text;
      return typeof text === "string" ? text : "";
    })
    .join("");
}

export function parsePrivateMessage(payload: unknown): OneBotPrivateMessage | null {
  if (typeof payload !== "object" || payload === null) return null;
  const value = payload as JsonObject;
  if (value.post_type !== "message" || value.message_type !== "private") return null;

  const messageId = stringId(value.message_id);
  const userId = stringId(value.user_id);
  const selfId = stringId(value.self_id);
  if (!messageId || !userId || !selfId) return null;

  const message = value.message;
  const text = (
    Array.isArray(message)
      ? textFromSegments(message)
      : typeof value.raw_message === "string" && value.raw_message.length > 0
        ? value.raw_message
        : typeof message === "string"
          ? message
          : ""
  ).trim();
  if (!text) return null;

  const sender = typeof value.sender === "object" && value.sender !== null
    ? value.sender as JsonObject
    : {};
  const nickname = typeof sender.nickname === "string" ? sender.nickname.trim() : "";
  const time = typeof value.time === "number" && Number.isFinite(value.time)
    ? Math.trunc(value.time)
    : Math.trunc(Date.now() / 1000);
  return { messageId, userId, selfId, nickname, text, time };
}
