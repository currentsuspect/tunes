# tunes (codename)

Private music library + player fed by Telegram channels. One box daemon (`tunesd`, TS)
does fetch → tag → dedupe → manifest; one Flutter app plays it with gapless, R128-
normalized audio and downloads the best copies to the phone.

- Master product spec: [`docs/SPEC.md`](docs/SPEC.md)
- Automation policy: [`AGENTS.md`](AGENTS.md)

Codename stands until M5 branding. Package id `com.currentsuspect.tunes` is name-proof.