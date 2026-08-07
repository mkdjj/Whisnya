import { describe, expect, it } from "vitest";

import { parsePrivateMessage } from "../src/onebot/events.js";

describe("parsePrivateMessage", () => {
  it("parses a private text message and preserves every id as a string", () => {
    const message = parsePrivateMessage({
      post_type: "message",
      message_type: "private",
      message_id: 9007199254740993000n.toString(),
      user_id: "1000123456",
      self_id: 22334455,
      sender: { nickname: "Alice" },
      raw_message: " hello ",
      time: 1786110000,
    });

    expect(message).toEqual({
      messageId: "9007199254740993000",
      userId: "1000123456",
      selfId: "22334455",
      nickname: "Alice",
      text: "hello",
      time: 1786110000,
    });
  });

  it("joins only text segments and ignores unsupported media", () => {
    const message = parsePrivateMessage({
      post_type: "message",
      message_type: "private",
      message_id: "42",
      user_id: "7",
      self_id: "8",
      sender: {},
      message: [
        { type: "text", data: { text: "one" } },
        { type: "image", data: { file: "secret.jpg" } },
        { type: "text", data: { text: " two" } },
      ],
      time: 5,
    });

    expect(message?.text).toBe("one two");
  });

  it("ignores groups and empty non-text messages", () => {
    expect(
      parsePrivateMessage({ post_type: "message", message_type: "group" }),
    ).toBeNull();
    expect(
      parsePrivateMessage({
        post_type: "message",
        message_type: "private",
        message_id: "1",
        user_id: "2",
        self_id: "3",
        message: [{ type: "image", data: { file: "x" } }],
      }),
    ).toBeNull();
  });
});
