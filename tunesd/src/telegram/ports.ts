export class RetryableError extends Error {
  constructor(message: string, public readonly retryAfterMs?: number) {
    super(message);
    this.name = "RetryableError";
  }
}

export class PermanentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PermanentError";
  }
}

/** The source message is gone for good: deleted, or no longer audio. Not a
 * transport failure, so nothing about it improves by trying again. */
export class SourceGoneError extends PermanentError {
  constructor(message: string) {
    super(message);
    this.name = "SourceGoneError";
  }
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}