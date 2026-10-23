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
  ])("retries %s", (msg) => {
    expect(mapMtprotoError(new Error(msg))).toBeInstanceOf(RetryableError);
  });

  it.each(["AUTH_KEY_UNREGISTERED", "SESSION_REVOKED", "USER_DEACTIVATED"])("stops on %s", (msg) => {
    expect(mapMtprotoError(new Error(msg))).toBeInstanceOf(PermanentError);
  });
});
