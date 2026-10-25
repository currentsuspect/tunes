# Setting up a Tunes box: instructions for your agent

This is for **an AI coding agent** (Claude Code or similar) running on the machine of someone who wants their own Tunes
box. Read it top to bottom before doing anything. The design is in [docs/BYOB.md](../BYOB.md); you do not need it to
follow these steps.

You are setting up three services on this machine:

- **tunesd**, the Tunes library daemon. It holds this person's music, runs their searches and Soulseek gets, and
  uploads their songs to the shared Telegram archive.
- **slskd**, the Soulseek client tunesd gets songs through. Download-only: nothing on this machine is shared.
- **cloudflared**, which connects this machine out to the Tunes front door (`tunes.aestra.studio`). No open ports.

Supported here: **macOS** and **Linux**. Windows is not covered yet; stop and say so if that is what you are on.

## Rules

1. **Secrets stay on this machine.** These are secrets:
   - the Soulseek password;
   - the Telegram API hash and session;
   - the tunnel token and the publish key from the bundle.

   Never send them to the Tunes owner, never paste them into a chat, an issue or a commit, and never print them in your
   output. Files holding them are mode 600.
2. **The person types their own secrets.** Ask them to enter the Soulseek password, the Telegram login code and any
   2FA password into a terminal themselves. Don't ask them to tell you.
3. **Ask before installing** anything system-wide (Homebrew packages, apt packages), and before turning on anything
   that keeps the machine awake.
4. **Stop on the first thing that fails.** Report what failed and the exact error. Don't improvise around it: a box
   that half-works fails in confusing ways later.
5. **Never share the music folder on Soulseek.** slskd is configured with no shares. Don't add any.

## What the person got from the Tunes owner

One file, `<box-id>.env`, handed over privately. It contains:

```
TUNESD_BOX_ID=<name>-box
TUNES_BOX_HOST=<name>-box.aestra.studio
TUNNEL_TOKEN=…            # secret
INTERNAL_PUBLISH_URL=https://tunes.aestra.studio/internal/publish
INTERNAL_PUBLISH_KEY=…    # secret
TUNESD_ARCHIVE_CHAT=-100…
```

Ask where they saved it. If they don't have it, stop: the owner makes it with `scripts/byob/new-box.sh`.

They also need to be **a member of the Tunes archive group** on Telegram, with the Telegram account they'll use here.
Ask them to confirm.

## Step 1: ask the person

Ask these, and write down the answers. They are not secrets.

1. **OS and chip:** run `uname -sm` yourself.
2. **Where the box should live.** Default: `~/TunesBox`. The music cache goes inside it.
3. **How much disk the cache may use.** Default 20 GB. Songs beyond that stay in the Telegram archive and come back
   when played.
4. **Do they have a Soulseek account?** If not, slskd will make one at first login from the username and password
   they choose. Use a new account for this, not one they share music from.
5. **A Telegram API ID and hash.** They make these at <https://my.telegram.org> → API development tools: any app name,
   platform "Desktop". They keep the page open; they'll paste the two values into a file you create (Step 4).
6. **Telegram channels to read songs from.** Optional: most people start with none. Never the archive group (see Step 4).
7. **A Last.fm API key**, optional (<https://www.last.fm/api/account/create>). Without one, song details are a little
   thinner. Lyrics are unaffected.
8. **Is this a laptop that sleeps?** A sleeping box is an offline box. Songs already in the archive still play through
   the cloud; searches and gets wait until it's awake.

## Step 2: tools

**macOS** (Homebrew; ask first):

```sh
brew install node@22 ffmpeg cloudflared git
echo 'export PATH="/opt/homebrew/opt/node@22/bin:$PATH"' >> ~/.zshrc   # node@22 is keg-only
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
```

On an Intel Mac, Homebrew lives in `/usr/local` instead of `/opt/homebrew`; use that prefix everywhere below.

**Linux:** Node 22, ffmpeg, git and cloudflared from the distribution, or:

- Node 22: <https://nodejs.org> or `nvm install 22`.
- cloudflared: Cloudflare's package repo (<https://pkg.cloudflare.com>) or the release binary
  (`cloudflared-linux-amd64`) in `~/.local/bin`.

Check: `node --version` (v22.x), `ffmpeg -version`, `ffprobe -version`, `cloudflared --version`.

## Step 3: tunesd

```sh
BOX=~/TunesBox                     # or what they chose
mkdir -p "$BOX/data"
git clone https://github.com/currentsuspect/tunes.git "$BOX/tunes"
cd "$BOX/tunes/tunesd"
npm ci
npm test                           # must pass; stop if it doesn't
```

`npm ci` installs into this checkout. Never point tunesd at another checkout's `node_modules`.

## Step 4: tunesd's settings

Create `$BOX/tunes/tunesd/.env`, mode 600, from the bundle and Step 1. The person pastes the Telegram API hash
themselves: open the file in their editor at that point.

```sh
umask 077
cat > "$BOX/tunes/tunesd/.env" <<EOF
# --- this box (from the bundle) ---
TUNESD_BOX_ID=<from bundle>
INTERNAL_PUBLISH_URL=<from bundle>
INTERNAL_PUBLISH_KEY=<from bundle>
TUNESD_ARCHIVE_CHAT=<from bundle>

# --- Telegram (from my.telegram.org) ---
TUNESD_API_ID=<their API ID>
TUNESD_API_HASH=<they paste it>

# Channels to read songs FROM, comma-separated as id=Name. Usually empty. Never the archive group: it holds everyone's
# music, and reading it would pull all of it into this box. TUNESD_ARCHIVE_CHAT above is enough to upload there.
TUNESD_CHANNELS=

# --- where and how much ---
TUNESD_DATA_DIR=<BOX>/data
TUNESD_CACHE_MAX_BYTES=<GB × 1073741824>
# Only cloudflared on this machine talks to tunesd.
TUNESD_HOST=127.0.0.1
TUNESD_PORT=4780

# This box carries one person's library, so it may fetch faster than the owner's (defaults 8000 / 7000). Keep the
# daily cap: it's this Telegram account's risk.
TUNESD_FETCH_DELAY_MS=4000
TUNESD_FETCH_JITTER_MS=3000

# Optional
# TUNESD_LASTFM_KEY=<key>
EOF
```

Replace every `<…>`. Then show the person the file **with the secret lines masked**, and have them confirm.

## Step 5: the Telegram login

This writes the session tunesd uses. It asks for a phone number, the code Telegram sends, and a 2FA password if they
have one, **so the person runs it in their own terminal**:

```sh
cd ~/TunesBox/tunes/tunesd && npm run login
```

Then list what that account can see, and check the archive group is there:

```sh
npm run ids
```

The archive group's id (`TUNESD_ARCHIVE_CHAT`) must appear. If it doesn't, they aren't in the group with this
Telegram account: stop and tell them.

## Step 6: slskd

Download the latest release for this OS and chip from <https://github.com/slskd/slskd/releases/latest>:
`…-osx-arm64.zip`, `…-osx-x64.zip` or `…-linux-x64.zip`. Unzip it to `$BOX/slskd/bin`.

On macOS, clear the download quarantine so it can run: `xattr -dr com.apple.quarantine "$BOX/slskd/bin"`.

Make an API key for tunesd (`openssl rand -hex 32`), and a web-UI password the person can use to look at slskd
(`openssl rand -hex 16`). Write `$BOX/slskd/slskd.yml`, mode 600. The person types the Soulseek username and password
lines themselves.

```yaml
directories:
  downloads: <BOX>/data/soulseek/downloads     # tunesd looks exactly here
  incomplete: <BOX>/data/soulseek/incomplete
shares:
  directories: []                              # download only: nothing shared
transfers:
  upload:
    slots: 1
    speed_limit: 10
web:
  port: 5030
  ip_address: 127.0.0.1                        # this machine only
  https:
    disabled: true
  authentication:
    disabled: false
    username: tunesbox
    password: <web-UI password>
    api_keys:
      tunesd:
        key: <API key>
        role: readwrite
        cidr: 127.0.0.1/32
soulseek:
  username: <they type it>
  password: <they type it>
  listen_port: 50300
```

Upload settings go under `transfers:`; slskd rejects `global:`.

Tell tunesd where slskd is, in `~/.config/tunes/slskd.env`, mode 600:

```sh
mkdir -p ~/.config/tunes && umask 077
printf 'SLSKD_URL=http://127.0.0.1:5030\nSLSKD_API_KEY=%s\n' "<API key>" > ~/.config/tunes/slskd.env
```

## Step 7: services that start on boot

Three services:

- **slskd:** `<BOX>/slskd/bin/slskd --app-dir <BOX>/slskd --config <BOX>/slskd/slskd.yml`
- **tunesd:** `node_modules/.bin/tsx src/cli.ts serve`, working directory `<BOX>/tunes/tunesd`. It reads its own `.env`.
- **cloudflared:** `cloudflared tunnel --no-autoupdate run --token <TUNNEL_TOKEN> --url http://127.0.0.1:4780`. The
  token is a secret: put it in an environment variable the service reads (`TUNNEL_TOKEN`), not on a command line other
  users can see.

**macOS:** three LaunchAgents in `~/Library/LaunchAgents/`, e.g. `studio.aestra.tunes.tunesd.plist`, each with
`RunAtLoad` and `KeepAlive` true, `WorkingDirectory`, and `StandardOutPath` / `StandardErrorPath` under `<BOX>/logs/`.
tunesd's `PATH` must contain Node 22 (`/opt/homebrew/opt/node@22/bin`) and ffmpeg (`/opt/homebrew/bin`), because
launchd starts with a bare PATH. cloudflared's token goes in its plist's `EnvironmentVariables` as `TUNNEL_TOKEN`;
make that plist mode 600. Load each with `launchctl bootstrap gui/$(id -u) <plist>`.

**Linux:** three user units in `~/.config/systemd/user/` (`slskd.service`, `tunesd.service`, `tunes-tunnel.service`),
`Restart=on-failure`, `WantedBy=default.target`. cloudflared reads the token from `EnvironmentFile=` pointing at a mode
600 file holding `TUNNEL_TOKEN=…`. Then:

```sh
systemctl --user daemon-reload
systemctl --user enable --now slskd tunesd tunes-tunnel
loginctl enable-linger "$USER"     # keep them running when logged out (may need sudo)
```

Start slskd first, then tunesd, then cloudflared.

## Step 8: prove it works

Each check must pass before the next.

1. **tunesd answers:** `curl -s http://127.0.0.1:4780/health` shows `"ok":true` and this box's id.
2. **The tunnel is up:** cloudflared's log shows `Registered tunnel connection` (four of them, normally).
3. **The box published:** tunesd's log shows an event `PUBLISH_DONE` within a few minutes. Logs are in
   `<BOX>/logs/` on macOS, and `journalctl --user -u tunesd` on Linux.
4. **A get works end to end:** the person opens Tunes on their phone, signed in to their own account, searches for a
   song they don't have and gets it. tunesd logs `GET_DONE`, the song plays, and soon after the log shows `ARCHIVED`
   for it, meaning it's in the Telegram archive.

If check 4's search shows the owner's library instead of an empty one, the box isn't routed yet: tell the owner.

## Step 9: report back to the Tunes owner

Send this, and nothing else:

```
Box <TUNESD_BOX_ID> is up.
OS: <uname -sm>. Node <version>. slskd <version>. cloudflared <version>. tunesd at commit <git rev-parse --short HEAD>.
Checks: health ✓  tunnel ✓  publish ✓  get + archive ✓
```

No keys, tokens, passwords, sessions or logs.

## Later

- **Updating tunesd:** `cd <BOX>/tunes && git pull && cd tunesd && npm ci`, then restart the tunesd service.
- **Turning it off:** stop the three services. The owner runs `scripts/byob/disable-box.sh` to route the account back
  to the owner's box.
- **Moving the music elsewhere** (a second disk, a NAS): stop tunesd and slskd, move `<BOX>/data`, update
  `TUNESD_DATA_DIR` and both slskd directories, then start them again.

## When something fails

- **tunesd exits at start with `TUNESD_API_ID and TUNESD_API_HASH required`:** the `.env` is missing, or not in
  `<BOX>/tunes/tunesd/`.
- **tunesd keeps restarting:** run `node_modules/.bin/tsx src/cli.ts serve` by hand in that folder and read the first
  error.
- **Nothing is ever archived:** `TUNESD_ARCHIVE_CHAT` is missing from `.env`, or this Telegram account isn't in the
  group (`npm run ids` doesn't list it).
- **Gets never finish:** slskd's downloads folder isn't `<TUNESD_DATA_DIR>/soulseek/downloads`, or
  `~/.config/tunes/slskd.env` has the wrong key.
- **The tunnel never registers:** the token was copied incompletely (it is one long line), or the machine blocks
  outbound traffic to Cloudflare.
