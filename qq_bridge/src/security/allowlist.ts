export interface AllowlistConfig {
  enabled: boolean;
  allowUsers: string[];
}

export class Allowlist {
  private enabled = false;
  private users = new Set<string>();

  update(config: AllowlistConfig): void {
    this.enabled = config.enabled;
    this.users = new Set(
      config.allowUsers.map((value) => value.trim()).filter((value) => value.length > 0),
    );
  }

  clear(): void {
    this.enabled = false;
    this.users.clear();
  }

  allows(userId: string): boolean {
    return this.enabled && this.users.size > 0 && this.users.has(userId);
  }
}
