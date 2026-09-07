import { describe, expect, it } from "vitest";
import { loadEnv } from "../src/env.js";

/**
 * The bind host decides who can reach the library.
 *
 * There is no authentication on any route in serve.ts, so this value *is* the
 * access control. That makes its default worth pinning: a change from 0.0.0.0
 * to something narrower would quietly cut off every existing setup, and a
 * change the other way would quietly expose one.
 */
describe("loadEnv host", () => {
  const base = {
    TUNESD_API_ID: "12345",
    TUNESD_API_HASH: "hash",
  };

  it("defaults to every interface, as it always has", () => {
    expect(loadEnv({ ...base }).host).toBe("0.0.0.0");
  });

  it("honours TUNESD_HOST", () => {
    // The tailnet case: bind the one address the intended clients arrive on.
    expect(loadEnv({ ...base, TUNESD_HOST: "100.100.235.90" }).host).toBe(
      "100.100.235.90",
    );
  });

  it("can be pinned to loopback", () => {
    expect(loadEnv({ ...base, TUNESD_HOST: "127.0.0.1" }).host).toBe("127.0.0.1");
  });

  it("leaves the port alone", () => {
    // Host and port are read from different variables; a mix-up between them
    // would bind the right interface on the wrong port and look like the
    // daemon simply not starting.
    const env = loadEnv({ ...base, TUNESD_HOST: "127.0.0.1" });
    expect(env.port).toBe(4780);
    expect(loadEnv({ ...base, TUNESD_PORT: "5000" }).host).toBe("0.0.0.0");
  });
});
