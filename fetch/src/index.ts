import { TelegramClient } from "teleproto";
import { StringSession } from "teleproto/sessions/index.js";
import { PromisedWebSockets } from "teleproto/extensions/PromisedWebSockets.js";
import { Logger } from "teleproto/extensions/Logger.js";
import { verifyMediaUrl } from "./grant.js";
import { pickVictims } from "./policy.js";

interface Env {
  TG_API_ID: string;
  TG_API_HASH: string;
  TG_SESSION: string;
  FETCHER: DurableObjectNamespace;
  CACHE: R2Bucket;
  DB: D1Database;
  MEDIA_SECRET?: string;
  /** Daily Telegram-fetch budget for the cloud path, separate from the box
   * cap: different session, different risk surface, same conservatism. */
  FETCH_DAILY_CAP?: string;
}

/** 3 GB: ORIGIN §4. R2 free tier is 10 GB; the cache stays well inside it. */
const CACHE_BUDGET = 3 * 1024 * 1024 * 1024;

// Every production DC fronted through a web host that answers /apiws.
// Measured 2026-09-08: venus 404s, pluto + flora upgrade clean. Bare DC IPs
// carry no SNI, so they are rewritten to a fronted host here.
const DC_HOSTS: Record<string, string> = {
  "149.154.175.50": "pluto.web.telegram.org",
  "149.154.167.51": "pluto.web.telegram.org",
  "149.154.175.100": "pluto.web.telegram.org",
  "149.154.167.91": "pluto.web.telegram.org",
  "149.154.171.5": "pluto.web.telegram.org",
};

class FrontedWebSocket extends WebSocket {
  constructor(url: string | URL, protocols?: string | string[]) {
    const u = new URL(url.toString());
    const host = DC_HOSTS[u.hostname];
    if (host) u.hostname = host;
    super(u.toString(), protocols);
  }
}

(PromisedWebSockets as any).webSocketImpl = FrontedWebSocket;

/** Parses a single `bytes=start-end` range. Suffix and open ranges are
 * answered from the whole object: mpv always sends the closed form, and
 * anything else is rare enough that a full 200 beats a wrong 206. */
function parseRange(
  header: string | null
): { start: number; end: number } | null {
  if (!header) return null;
  const m = /^bytes=(\d+)-(\d+)$/.exec(header.trim());
  if (!m) return null;
  const start = Number(m[1]);
  const end = Number(m[2]);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end) {
    return null;
  }
  return { start, end };
}

function fullHeaders(total: number, src: string): Record<string, string> {
  return {
    "content-type": "audio/mpeg",
    "accept-ranges": "bytes",
    "content-length": String(total),
    "x-tunes-src": src,
  };
}

function rangeHeaders(
  start: number,
  end: number,
  total: number,
  src: string
): Record<string, string> {
  return {
    "content-type": "audio/mpeg",
    "accept-ranges": "bytes",
    "content-range": `bytes ${start}-${end}/${total}`,
    "content-length": String(end - start + 1),
    "x-tunes-src": src,
  };
}

function rangeEmpty(total: number): Response {
  return new Response(null, {
    status: 416,
    headers: {
      "content-type": "audio/mpeg",
      "accept-ranges": "bytes",
      "content-range": `bytes */${total}`,
    },
  });
}

// One connection, one context. The client is created on the first request
// the DO serves and never leaves: every later request reuses it inside the
// same execution context, which is what keeps the runtime's I/O tracking
// honest. A client cached in the front Worker works once, then stalls --
// its promises leak across request contexts. Do not "simplify" this back.
export class Fetcher {
  private client: TelegramClient | null = null;
  private connecting: Promise<TelegramClient> | null = null;

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env
  ) {}

  private async connected(): Promise<TelegramClient> {
    if (this.client) return this.client;
    if (!this.connecting) {
      this.connecting = (async () => {
        const fresh = new TelegramClient(
          new StringSession(this.env.TG_SESSION),
          Number(this.env.TG_API_ID),
          this.env.TG_API_HASH,
          {
            connectionRetries: 2,
            deviceModel: "cf-worker",
            systemVersion: "workerd",
            appVersion: "tunes-fetch-1",
            baseLogger: new Logger("warn" as any),
          } as any
        );
        await fresh.connect();
        this.client = fresh;
        this.connecting = null;
        return fresh;
      })();
    }
    return this.connecting;
  }

  private async sources(
    sha: string
  ): Promise<{ chat: number; msg: number }[]> {
    const { results } = await this.env.DB.prepare(
      "SELECT chat, msg FROM fetch_map WHERE sha = ? ORDER BY rowid"
    )
      .bind(sha)
      .all<{ chat: number; msg: number }>();
    return results ?? [];
  }

  private async fromTelegram(
    sha: string
  ): Promise<{ bytes: Uint8Array; src: "telegram" } | { err: string }> {
    const rows = await this.sources(sha);
    if (rows.length === 0) return { err: "unknown" };
    const c = await this.connected();
    for (const { chat, msg } of rows) {
      try {
        const peer = await c.getInputEntity(chat);
        const found = await c.getMessages(peer, { ids: [msg] });
        const m = (found as any[]).find((x) => x && x.id === msg);
        if (!m) continue;
        const buf = (await (c as any).downloadMedia(m, {})) as unknown;
        if (!buf) continue;
        const bytes =
          buf instanceof Uint8Array ? buf : new Uint8Array(buf as ArrayBuffer);
        const digest = await crypto.subtle.digest("SHA-256", bytes as any);
        const got = [...new Uint8Array(digest)]
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("");
        if (got !== sha) continue;
        return { bytes, src: "telegram" };
      } catch {
        continue;
      }
    }
    return { err: "unreachable" };
  }

  private async noteAccess(sha: string, size: number): Promise<void> {
    const map =
      (await this.state.storage.get<Record<string, { size: number; at: number }>>(
        "access"
      )) ?? {};
    map[sha] = { size, at: Date.now() };
    await this.state.storage.put("access", map);
  }

  /** Full size from the access map, recorded at put time. Null means unseen:
   * serve whole and learn it, rather than guessing from a ranged read. */
  private async knownSize(sha: string): Promise<number | null> {
    const map =
      (await this.state.storage.get<Record<string, { size: number; at: number }>>(
        "access"
      )) ?? {};
    return map[sha]?.size ?? null;
  }

  private async takeCap(): Promise<boolean> {
    const day = new Date().toISOString().slice(0, 10);
    const cap = Number(this.env.FETCH_DAILY_CAP ?? 500);
    const row = await this.env.DB.prepare(
      "SELECT count FROM fetch_cap WHERE day = ?"
    )
      .bind(day)
      .first<{ count: number }>();
    if ((row?.count ?? 0) >= cap) return false;
    await this.env.DB.prepare(
      "INSERT INTO fetch_cap (day, count) VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET count = count + 1"
    )
      .bind(day)
      .run();
    return true;
  }

  /** Nightly sweep: LRU past budget with hysteresis. Reached by cron, never
   * by listeners. */
  async sweep(): Promise<{ evicted: number; remaining: number }> {
    const map =
      (await this.state.storage.get<Record<string, { size: number; at: number }>>(
        "access"
      )) ?? {};
    const listed = await this.env.CACHE.list({ limit: 1000 });
    const entries = listed.objects.map((o) => ({
      sha: o.key,
      size: o.size,
      accessed: map[o.key]?.at,
    }));
    const { victims, remaining } = pickVictims(entries, CACHE_BUDGET);
    await Promise.all(victims.map((sha) => this.env.CACHE.delete(sha)));
    for (const sha of victims) delete map[sha];
    await this.state.storage.put("access", map);
    return { evicted: victims.length, remaining };
  }

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    try {
      if (url.pathname === "/ping") {
        const c = await this.connected();
        const me = await c.getMe();
        return Response.json({ ok: true, id: String(me.id) });
      }
      if (url.pathname === "/sweep") {
        return Response.json(await this.sweep());
      }
      const track = /^\/t\/([0-9a-f]{64})$/.exec(url.pathname);
      if (track) {
        const sha = track[1]!;
        // Device credential, same shape mpv already carries: the fetch path
        // must not be an open proxy for a Telegram session. Unset secret in
        // tests means deny-all, never allow-all.
        const secret = this.env.MEDIA_SECRET ?? "";
        const verdict =
          secret === ""
            ? { ok: false as const, reason: "missing" as const }
            : await verifyMediaUrl(
                `/t/${sha}`,
                url.searchParams,
                secret,
                Math.floor(Date.now() / 1000)
              );
        if (!verdict.ok) {
          return Response.json(
            { ok: false, err: verdict.reason },
            { status: verdict.reason === "expired" ? 403 : 401 }
          );
        }
        // Audio playback is almost entirely range requests: a seek must come
        // back 206 with exactly the bytes asked for, from either source.
        // Totals come from the access map (full sizes recorded at put), never
        // from a ranged read, whose size is the range, not the object.
        const range = parseRange(req.headers.get("range"));
        const known = await this.knownSize(sha);
        if (range && known !== null) {
          if (range.start >= known) {
            return rangeEmpty(known);
          }
          const end = Math.min(range.end, known - 1);
          const hit = await this.env.CACHE.get(sha, {
            range: { offset: range.start, length: end - range.start + 1 },
          });
          if (hit) {
            await this.noteAccess(sha, known);
            return new Response(hit.body, {
              status: 206,
              headers: rangeHeaders(range.start, end, known, "r2"),
            });
          }
        } else {
          const hit = await this.env.CACHE.get(sha);
          if (hit) {
            await this.noteAccess(sha, hit.size);
            return new Response(hit.body, {
              headers: fullHeaders(hit.size, "r2"),
            });
          }
        }
        if (!(await this.takeCap())) {
          return Response.json({ ok: false, err: "cap" }, { status: 429 });
        }
        const res = await this.fromTelegram(sha);
        if ("err" in res) {
          return Response.json(
            { ok: false, err: res.err },
            { status: res.err === "unknown" ? 404 : 502 }
          );
        }
        const total = res.bytes.byteLength;
        await this.env.CACHE.put(sha, res.bytes as any);
        await this.noteAccess(sha, total);
        if (range) {
          if (range.start >= total) return rangeEmpty(total);
          const end = Math.min(range.end, total - 1);
          return new Response(res.bytes.slice(range.start, end + 1) as any, {
            status: 206,
            headers: rangeHeaders(range.start, end, total, "telegram"),
          });
        }
        return new Response(res.bytes as any, {
          headers: fullHeaders(total, "telegram"),
        });
      }
      return new Response("tunes-fetch", { status: 404 });
    } catch (e) {
      return Response.json({ ok: false, err: String(e).slice(0, 200) }, { status: 500 });
    }
  }
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const stub = env.FETCHER.getByName("live");
    return stub.fetch(req);
  },

  // Nightly eviction. The sweep itself lives on the DO so the map and the
  // deletes share one context; cron just knocks.
  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    const stub = env.FETCHER.getByName("live");
    await stub.fetch("https://do/sweep");
  },
};
