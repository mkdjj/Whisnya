export interface OneBotConfig {
  url: string;
  accessToken: string;
}

export interface OneBotPrivateMessage {
  messageId: string;
  userId: string;
  selfId: string;
  nickname: string;
  text: string;
  time: number;
}

export interface OneBotLoginInfo {
  userId: string;
  nickname: string;
}

export interface OneBotSendResult {
  messageId: string;
}

export interface OneBotConnectionStatus {
  connected: boolean;
  selfId: string;
  nickname: string;
  lastError: string | null;
}

export type JsonObject = Record<string, unknown>;
