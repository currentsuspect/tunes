type Level = "debug" | "info" | "warn" | "error";

const ORDER: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };

export interface Log {
  debug(o: Record<string, unknown>): void;
  info(o: Record<string, unknown>): void;
  warn(o: Record<string, unknown>): void;
  error(o: Record<string, unknown>): void;
}

export function makeLogger(minLevel: Level = "info"): Log {
  const threshold = ORDER[minLevel];
  const emit = (level: Level, o: Record<string, unknown>) => {
    if (ORDER[level] < threshold) return;
    const line = { ts: new Date().toISOString(), level, ...o };
    const out = JSON.stringify(line);
    if (level === "error") process.stderr.write(out + "\n");
    else process.stdout.write(out + "\n");
  };
  return {
    debug: (o) => emit("debug", o),
    info: (o) => emit("info", o),
    warn: (o) => emit("warn", o),
    error: (o) => emit("error", o),
  };
}