import { randomUUID } from "node:crypto";

import type { JsonObject } from "./types.js";

interface PendingAction {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
  action: string;
}

export class OneBotActionError extends Error {}

export class OneBotActions {
  private readonly pending = new Map<string, PendingAction>();

  constructor(
    private readonly sendJson: (payload: JsonObject) => void,
    private readonly timeoutMs = 15_000,
  ) {}

  get pendingCount(): number {
    return this.pending.size;
  }

  call(action: string, params: JsonObject): Promise<unknown> {
    const echo = randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(echo);
        reject(new OneBotActionError(`OneBot action ${action} timed out`));
      }, this.timeoutMs);
      this.pending.set(echo, { resolve, reject, timer, action });
      try {
        this.sendJson({ action, params, echo });
      } catch (error) {
        clearTimeout(timer);
        this.pending.delete(echo);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  handlePayload(payload: unknown): boolean {
    if (typeof payload !== "object" || payload === null) return false;
    const value = payload as JsonObject;
    if (typeof value.echo !== "string") return false;
    const pending = this.pending.get(value.echo);
    if (pending === undefined) return false;

    clearTimeout(pending.timer);
    this.pending.delete(value.echo);
    if (value.retcode === 0) {
      pending.resolve(value.data);
    } else {
      const message = typeof value.message === "string"
        ? value.message
        : typeof value.msg === "string"
          ? value.msg
          : "action failed";
      pending.reject(
        new OneBotActionError(
          `OneBot action ${pending.action} failed (retcode=${String(value.retcode)}): ${message}`,
        ),
      );
    }
    return true;
  }

  rejectAll(error: Error): void {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pending.clear();
  }
}
