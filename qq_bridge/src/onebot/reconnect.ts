const DEFAULT_DELAYS = [1000, 2000, 5000, 10_000, 30_000] as const;

export class ReconnectPolicy {
  private attempt = 0;

  constructor(private readonly delays: readonly number[] = DEFAULT_DELAYS) {
    if (delays.length === 0 || delays.some((delay) => delay < 1)) {
      throw new Error("Reconnect delays must contain positive values");
    }
  }

  nextDelay(): number {
    const index = Math.min(this.attempt, this.delays.length - 1);
    this.attempt += 1;
    return this.delays[index];
  }

  reset(): void {
    this.attempt = 0;
  }
}
