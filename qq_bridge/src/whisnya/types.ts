export interface WhisnyaConfig {
  enabled: boolean;
  allowUsers: string[];
}

export interface WhisnyaMessage {
  source: "onebot";
  messageId: string;
  userId: string;
  nickname: string;
  text: string;
  timestamp: number;
}

export interface WhisnyaReply {
  reply: string;
  sessionId: string;
  bindingId: string;
}

export interface WhisnyaBridgeStatus {
  connected: boolean;
  selfId: string;
  nickname: string;
  lastMessageAt: string | null;
  lastError: string | null;
}
