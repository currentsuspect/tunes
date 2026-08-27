import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { extname } from "node:path";
import type { ObjectStore } from "./store.js";
import type { Log } from "./logger.js";
import type { ManifestV1 } from "./manifest.js";

const MIME: Record<string, string> = {
  ".mp3": "audio/mpeg",
  ".flac": "audio/flac",
  ".ogg": "audio/ogg",
  ".opus": "audio/ogg",
  ".m4a": "audio/mp4",
  ".wav": "audio/wav",
  ".aac": "audio/aac",
};

export class ManifestServer {
  private lastManifest: ManifestV1 | null = null;
  private lastBuiltAt = 0;

  constructor(
    private readonly store: ObjectStore,
    private readonly buildManifest: () => Promise<ManifestV1>,
    private readonly port: number,
    private readonly log: Log
  ) {}

  private async getManifest(force = false): Promise<ManifestV1> {
    const now = Date.now();
    if (!force && this.lastManifest && now - this.lastBuiltAt < 30_000) {
      return this.lastManifest;
    }
    const m = await this.buildManifest();
    this.lastManifest = m;
    this.lastBuiltAt = now;
    return m;
  }

  async start(): Promise<void> {
    const server = createServer(async (req, res) => {
      try {
        const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
        if (url.pathname === "/manifest") {
          const manifest = await this.getManifest();
          res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
          res.end(JSON.stringify(manifest));
          return;
        }

        const trackMatch = /^\/track\/([0-9a-f]{64})$/.exec(url.pathname);
        if (trackMatch) {
          const sha = trackMatch[1] ?? "";
          const path = this.store.pathOf(sha);
          try {
            const info = await stat(path);
            if (!info.isFile()) throw new Error("not a file");
            const range = req.headers.range;
            const mime = MIME[extname(path)] ?? "application/octet-stream";
            if (range) {
              const m = /^bytes=(\d*)-(\d*)$/.exec(range);
              if (m) {
                const start = m[1] === "" ? 0 : Number(m[1] ?? 0);
                const requestedEnd = m[2] === "" ? info.size - 1 : Number(m[2] ?? info.size - 1);
                const end = Math.min(requestedEnd, info.size - 1);
                if (start <= end && start < info.size) {
                  res.writeHead(206, {
                    "content-type": mime,
                    "accept-ranges": "bytes",
                    "content-range": `bytes ${start}-${end}/${info.size}`,
                    "content-length": String(end - start + 1),
                  });
                  createReadStream(path, { start, end }).pipe(res);
                  return;
                }
              }
              res.writeHead(416, { "content-range": `bytes */${info.size}` });
              res.end();
              return;
            }
            res.writeHead(200, {
              "content-type": mime,
              "accept-ranges": "bytes",
              "content-length": String(info.size),
            });
            createReadStream(path).pipe(res);
            return;
          } catch {
            res.writeHead(404, { "content-type": "text/plain" });
            res.end("object not found");
            return;
          }
        }

        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
      } catch (e) {
        this.log.error({ event: "HTTP_ERROR", err: String(e) });
        res.writeHead(500, { "content-type": "text/plain" });
        res.end("internal error");
      }
    });

    server.listen(this.port, "0.0.0.0", () => {
      this.log.info({ event: "HTTP_LISTEN", port: this.port });
    });
  }
}