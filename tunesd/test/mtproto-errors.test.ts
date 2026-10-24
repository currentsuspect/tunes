import { describe, expect, it } from "vitest";
import { mapMtprotoError } from "../src/telegram/mtproto.js";
import { PermanentError, RetryableError } from "../src/telegram/ports.js";

describe("mapMtprotoError", () => {
  it.each([
    "Media request deadline exceeded",
    "Could not reconnect to dc 4",
    "Request timed out",
    "connect ETIMEDOUT 149.154.167.91:443",
    "Cannot send requests while disconnected",
    "The provided authorization is invalid. (caused by InvokeWithLayer)",
  ])("retries %s", (msg) => {
    expect(mapMtprotoError(new Error(msg))).toBeInstanceOf(RetryableError);
  });

  it.each(["AUTH_KEY_UNREGISTERED", "SESSION_REVOKED", "USER_DEACTIVATED"])("stops on %s", (msg) => {
    expect(mapMtprotoError(new Error(msg))).toBeInstanceOf(PermanentError);
  });

  it("waits on an error it has never seen rather than stopping", () => {
    const e = mapMtprotoError(new Error("SOMETHING_NEW_FROM_TELEGRAM"));
    expect(e).toBeInstanceOf(RetryableError);
    expect((e as RetryableError).retryAfterMs).toBe(60_000);
  });
});
