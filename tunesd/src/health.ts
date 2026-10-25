import { readFileSync } from "node:fs";

/**
 * GET /health: is this box up, and which box is it (docs/BYOB.md). Unauthenticated and harmless: the box id, the
 * daemon's version and how long it has been running, nothing about the library. The box's owner checks it locally;
 * the Tunes owner checks it end to end through the Worker (/internal/boxes/<id>/health), which is the only way
 * through a box's tunnel.
 */
const version: string = (() => {
  try {
    const pkg = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")) as { version?: string };
    return pkg.version ?? "unknown";
  } catch {
    return "unknown";
  }
})();

const startedAt = Date.now();

export interface Health {
  ok: true;
  box: string | null;
  version: string;
  uptimeSec: number;
}

export function health(env: NodeJS.ProcessEnv = process.env, now: number = Date.now()): Health {
  const box = env["TUNESD_BOX_ID"]?.trim();
  return { ok: true, box: box ? box : null, version, uptimeSec: Math.floor((now - startedAt) / 1000) };
}
