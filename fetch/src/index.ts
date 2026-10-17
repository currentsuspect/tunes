import { TelegramClient } from "teleproto";
import { StringSession } from "teleproto/sessions/index.js";
import { PromisedWebSockets } from "teleproto/extensions/PromisedWebSockets.js";
import { Logger } from "teleproto/extensions/Logger.js";
import { verifyMediaUrl } from "./grant.js";
import { pickVictims, sniffMime } from "./policy.js";
import { Flight, Gate, runDownload } from "./flight.js";
import { parseRange, serveHit, type R2Like } from "./hit.js";

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

/** 8 GB. ORIGIN §4 sized this at 3 GB for two listeners; with four people on
 * different music a 12 GB library misses far more often, and every miss is a
 * slow Telegram fetch. R2 egress is free and the free tier is 10 GB, so 8 GB
 * (evicting down to 7.2 GB) keeps the bill at zero. */
const CACHE_BUDGET = 8 * 1024 * 1024 * 1024;

const CONNECT_MS = 15_000;
const LOCATE_MS = 10_000;
/** No data for this long means the connection is dead, not slow. */
const STALL_MS = 15_000;
/** 1 MB, Telegram's ceiling per request. The default is far smaller, which
 * is a round trip per few hundred KB. */
const CHUNK = 1024 * 1024;

function withTimeout<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const t = new Promise<never>((_, rej) => {
    timer = setTimeout(() => rej(new Error(`${what} timed out`)), ms);
  });
  return Promise.race([p, t]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

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

function fullHeaders(
  total: number,
  src: string,
  type: string
): Record<string, string> {
  return {
    "content-type": type,
    "accept-ranges": "bytes",
    "content-length": String(total),
    "x-tunes-src": src,
  };
}

function rangeHeaders(
  start: number,
  end: number,
  total: number,
  src: string,
  type: string
): Record<string, string> {
  return {
    "content-type": type,
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
  /** Downloads in progress, by sha. A second request joins the first. */
  private readonly flights = new Map<string, Promise<Flight | { err: string }>>();
  /** Telegram multiplexes requests on one connection; more than a few at once
   * just makes each of them slower. Extra cold tracks wait their turn. */
  private readonly gate = new Gate(3);

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env
  ) {}

  private async connected(): Promise<TelegramClient> {
    if (this.client) return this.client;
    if (!this.connecting) {
      const attempt = (async () => {
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
        await withTimeout(fresh.connect(), CONNECT_MS, "connect");
        this.client = fresh;
        return fresh;
      })();
      // A failed connect must not stay cached, or every later request awaits
      // the same rejected promise.
      this.connecting = attempt.finally(() => {
        this.connecting = null;
      });
    }
    return this.connecting;
  }

  /** Throws the client away. A connection that dropped mid-download ("Network
   * connection lost") used to stay cached for good, and the next request
   * waited on it for two minutes. */
  private async resetClient(): Promise<void> {
    const old = this.client;
    this.client = null;
    this.connecting = null;
    if (old) {
      try {
        await withTimeout(old.disconnect(), 3000, "disconnect");
      } catch {
        /* already dead */
      }
    }
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

  /** Finds the Telegram message for [sha] and its size, resetting the
   * connection once if it turns out to be dead. */
  private async locate(
    sha: string
  ): Promise<{ msg: any; size: number } | { err: string }> {
    const rows = await this.sources(sha);
    if (rows.length === 0) return { err: "unknown" };
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const c = await this.connected();
        for (const { chat, msg } of rows) {
          const peer = await withTimeout(c.getInputEntity(chat), LOCATE_MS, "entity");
          const found = await withTimeout(
            c.getMessages(peer, { ids: [msg] }),
            LOCATE_MS,
            "message"
          );
          const m = (found as any[]).find((x) => x && x.id === msg);
          const size = Number(m?.media?.document?.size ?? 0);
          if (m && size > 0) return { msg: m, size };
        }
        return { err: "unreachable" };
      } catch {
        await this.resetClient();
      }
    }
    return { err: "unreachable" };
  }

  /** The shared download for [sha]: started once, joined by everyone else. */
  private flightFor(
    sha: string,
    opts: { warm: boolean }
  ): Promise<Flight | { err: string }> | null {
    const existing = this.flights.get(sha);
    if (existing) return existing;
    // A warm-up is a hint, never a reason to queue behind real playback.
    if (opts.warm && this.gate.busy) return null;
    const p = this.startFlight(sha);
    this.flights.set(sha, p);
    void p.then(
      (f) => {
        if ("err" in f) this.flights.delete(sha);
      },
      () => this.flights.delete(sha)
    );
    return p;
  }

  private async startFlight(sha: string): Promise<Flight | { err: string }> {
    if (!(await this.takeCap())) return { err: "cap" };
    const found = await this.gate.run(() => this.locate(sha));
    if ("err" in found) return found;
    const flight = new Flight(found.size);
    // The download outlives the request that started it, so the cache fills
    // even when the listener skips ahead.
    const job = this.gate
      .run(() =>
        runDownload(
          flight,
          async (offset) => {
            const c = await this.connected();
            return c.iterDownload(found.msg, {
              offset,
              requestSize: CHUNK,
            }) as AsyncIterable<Uint8Array>;
          },
          {
            stallMs: STALL_MS,
            attempts: 3,
            onRetry: () => this.resetClient(),
          }
        )
      )
      .then(() => this.finishFlight(sha, flight))
      .finally(() => this.flights.delete(sha));
    this.state.waitUntil(job);
    return flight;
  }

  /** Verifies and caches a finished download. The listener already has the
   * bytes; a bad hash only means this copy is not kept. */
  private async finishFlight(sha: string, flight: Flight): Promise<void> {
    if (flight.error) return;
    const bytes = flight.bytes();
    const digest = await crypto.subtle.digest("SHA-256", bytes as any);
    const got = [...new Uint8Array(digest)]
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    if (got !== sha) {
      console.warn(`tunes-fetch: hash mismatch for ${sha}, not cached`);
      return;
    }
    await this.env.CACHE.put(sha, bytes as any, {
      httpMetadata: { contentType: sniffMime(bytes) },
    });
    await this.noteAccess(sha, bytes.byteLength);
  }

  /** One storage key per track. The old single map was read and rewritten
   * whole on every request, which gets slower with every track and serialises
   * every listener behind it. */
  private async noteAccess(sha: string, size: number): Promise<void> {
    await this.state.storage.put(`a:${sha}`, { size, at: Date.now() });
  }

  /** Full size recorded at put time. Null means unseen: serve whole and learn
   * it, rather than guessing from a ranged read. Falls back to the legacy map
   * so tracks cached before this change keep their sizes. */
  private async knownSize(sha: string): Promise<number | null> {
    const one = await this.state.storage.get<{ size: number; at: number }>(
      `a:${sha}`
    );
    if (one) return one.size;
    const legacy = await this.state.storage.get<
      Record<string, { size: number; at: number }>
    >("access");
    return legacy?.[sha]?.size ?? null;
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
    const times = new Map<string, number>();
    const legacy = await this.state.storage.get<
      Record<string, { size: number; at: number }>
    >("access");
    for (const [sha, v] of Object.entries(legacy ?? {})) times.set(sha, v.at);
    const per = await this.state.storage.list<{ size: number; at: number }>({
      prefix: "a:",
    });
    for (const [k, v] of per) times.set(k.slice(2), v.at);
    // Hits are served off the DO and record recency in D1.
    const { results } = await this.env.DB.prepare(
      "SELECT sha, at FROM fetch_access"
    ).all<{ sha: string; at: number }>();
    for (const r of results ?? []) {
      times.set(r.sha, Math.max(times.get(r.sha) ?? 0, r.at));
    }

    const entries: { sha: string; size: number; accessed?: number }[] = [];
    let cursor: string | undefined;
    do {
      const page = await this.env.CACHE.list({ limit: 1000, cursor });
      for (const o of page.objects) {
        entries.push({ sha: o.key, size: o.size, accessed: times.get(o.key) });
      }
      cursor = page.truncated ? page.cursor : undefined;
    } while (cursor);

    const { victims, remaining } = pickVictims(
      entries,
      CACHE_BUDGET,
      new Set(this.flights.keys())
    );
    await Promise.all(victims.map((sha) => this.env.CACHE.delete(sha)));
    await this.state.storage.delete(victims.map((sha) => `a:${sha}`));
    for (let i = 0; i < victims.length; i += 50) {
      const batch = victims.slice(i, i + 50);
      await this.env.DB.prepare(
        `DELETE FROM fetch_access WHERE sha IN (${batch.map(() => "?").join(",")})`
      )
        .bind(...batch)
        .run();
    }
    if (legacy) {
      for (const sha of victims) delete legacy[sha];
      await this.state.storage.put("access", legacy);
    }
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
        // from a ranged read, whose size is the range, not the object. Types
        // come from R2 metadata, sniffed once at put time.
        const warm = url.searchParams.get("warm") === "1";
        if (warm && (await this.env.CACHE.head(sha))) {
          return new Response(null, { status: 204 });
        }
        // mpv (ffmpeg) seeks with the open form, `bytes=N-`. The parser here
        // used to take only `bytes=N-M`, so every seek in a streamed song was
        // answered with the whole file from byte 0: the playhead moved on
        // over silence. Both paths now share hit.ts's parser.
        const rangeHeader = req.headers.get("range");
        const known = await this.knownSize(sha);
        const range = known !== null ? parseRange(rangeHeader, known) : null;
        if (range === "unsatisfiable" && known !== null) {
          return rangeEmpty(known);
        }
        if (range && range !== "unsatisfiable" && known !== null) {
          const end = range.end;
          const hit = await this.env.CACHE.get(sha, {
            range: { offset: range.start, length: end - range.start + 1 },
          });
          if (hit) {
            await this.noteAccess(sha, known);
            return new Response(hit.body, {
              status: 206,
              headers: rangeHeaders(
                range.start,
                end,
                known,
                "r2",
                hit.httpMetadata?.contentType ?? "application/octet-stream"
              ),
            });
          }
        } else {
          const hit = await this.env.CACHE.get(sha);
          if (hit) {
            await this.noteAccess(sha, hit.size);
            return new Response(hit.body, {
              headers: fullHeaders(
                hit.size,
                "r2",
                hit.httpMetadata?.contentType ?? "application/octet-stream"
              ),
            });
          }
        }
        // Miss. `?warm=1` means "have this ready", not "play this": it joins
        // or starts the download, waits for it, and sends no audio.
        const pending = this.flightFor(sha, { warm });
        if (!pending) {
          return Response.json({ ok: true, skipped: "busy" }, { status: 202 });
        }
        const flight = await pending;
        if ("err" in flight) {
          const status =
            flight.err === "unknown" ? 404 : flight.err === "cap" ? 429 : 502;
          return Response.json({ ok: false, err: flight.err }, { status });
        }
        if (warm) {
          try {
            await flight.complete();
          } catch (e) {
            return Response.json(
              { ok: false, err: String(e).slice(0, 200) },
              { status: 502 }
            );
          }
          return new Response(null, { status: 204 });
        }
        // Sniff needs the first bytes; everything after streams as it lands.
        await flight.ready(Math.min(16, flight.total));
        const total = flight.total;
        const type = sniffMime(flight.head(16));
        const live = parseRange(rangeHeader, total);
        if (live === "unsatisfiable") return rangeEmpty(total);
        if (live) {
          const end = live.end;
          return new Response(flight.stream(live.start, end), {
            status: 206,
            headers: rangeHeaders(live.start, end, total, "telegram", type),
          });
        }
        return new Response(flight.stream(0, total - 1), {
          headers: fullHeaders(total, "telegram", type),
        });
      }
      return new Response("tunes-fetch", { status: 404 });
    } catch (e) {
      return Response.json({ ok: false, err: String(e).slice(0, 200) }, { status: 500 });
    }
  }
}

/** When each track's last-served time was last written, per isolate. Recency
 * only has to be right to within minutes, so most hits write nothing. */
const touched = new Map<string, number>();
const TOUCH_EVERY_MS = 10 * 60 * 1000;

async function touch(env: Env, sha: string, size: number): Promise<void> {
  const now = Date.now();
  const last = touched.get(sha);
  if (last !== undefined && now - last < TOUCH_EVERY_MS) return;
  touched.set(sha, now);
  if (touched.size > 5000) touched.clear();
  try {
    await env.DB.prepare(
      "INSERT INTO fetch_access (sha, at, size) VALUES (?, ?, ?) ON CONFLICT(sha) DO UPDATE SET at = excluded.at, size = excluded.size"
    )
      .bind(sha, now, size)
      .run();
  } catch {
    // Recency is an optimisation for eviction, never a reason to fail a play.
  }
}

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(req.url);
    // Only the track path is public. /ping (opens a Telegram connection and
    // names the account) and /sweep (evicts the cache) used to be reachable
    // by anyone who found the workers.dev address; they are the DO's own.
    const m = /^\/t\/([0-9a-f]{64})$/.exec(url.pathname);
    if (!m || (req.method !== "GET" && req.method !== "HEAD")) {
      return new Response("not found", { status: 404 });
    }
    const sha = m[1]!;

    const secret = env.MEDIA_SECRET ?? "";
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

    // Cached tracks are served here, off the Durable Object.
    if (url.searchParams.get("warm") === "1") {
      if (await env.CACHE.head(sha)) return new Response(null, { status: 204 });
    } else {
      const hit = await serveHit(
        env.CACHE as unknown as R2Like,
        sha,
        req.headers.get("range"),
        req.method === "HEAD"
      );
      if (hit) {
        ctx.waitUntil(touch(env, sha, hit.size));
        return hit.response;
      }
    }

    // Miss: the DO owns the Telegram connection.
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
