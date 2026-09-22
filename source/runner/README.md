# Mac runner (GitHub pull model)

Cloud cannot reach your Mac. This script runs **on the MacBook**.

## One-time setup
1. Clone `AkaiSystems/xenolift-disc1-recompile`, branch `xenolift-clean`.
2. Set `XG_DISC_BIN` to your Disc 1 `.bin`.
3. Copy `com.akaisystems.xenolift.runner.plist.example` → `~/Library/LaunchAgents/com.akaisystems.xenolift.runner.plist`
4. Replace `/ABS/PATH/...` placeholders.
5. `launchctl load ~/Library/LaunchAgents/com.akaisystems.xenolift.runner.plist`

Polls every 120s: if `docs/directives/next.json` exists → one `./run.sh` → push digest → move directive to `done/`.

**Note:** Old Base44 bridge forbade LaunchAgents for *that* bridge. This GitHub watcher is a different path (repo sync, not Base44). Still **one cycle at a time** via the lock file.

## Manual / Claude Code
```bash
export XG_DISC_BIN="/path/to/disc.bin"
./source/runner/watch-and-run.sh
```
