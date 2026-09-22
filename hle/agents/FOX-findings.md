# FOX Bridge Reliability Audit & Hardening Report (v8)

**Agent:** FOX (Bridge-Reliability Specialist)  
**Project:** Xenolift PS1 Game Recompile Lab  
**Target:** Bridge Script Hardening (`xenolift-bridge8.sh`)

---

## 1. Freeze-On-Chat Root Cause Analysis

When the owner chats with the AI agent in the Base44 web chat while the bridge is active, the bridge script frequently appears to freeze or lose connection. Audit of `xenolift-bridge7.sh` revealed three major vulnerabilities responsible for this behavior:

### Rank 1: Missing Short `--max-time` on POSTs & 1800s Timeout (Line 81)
* **Location in v7:** Line 81 (`resp=$(curl -s -m 1800 -w $'\n%{http_code}' -X POST "$API" ...)`)
* **Root Cause:** The `post()` function configured `curl` with a 30-minute timeout (`-m 1800`) and silent output (`-s` without `-S`). When the owner starts chatting with the AI agent, conversation turns or backend lock states cause incoming POST requests to block. `curl` will sit waiting for up to 30 minutes without output. If TCP drops or stalls occur during long-running turns, the script hangs indefinitely without output, creating the exact "freeze" signature reported by the owner.

### Rank 2: Exit-On-Error & "Parking" Paths Killing the Process (Lines 200, 202, 285, 288, 292, 295)
* **Locations in v7:** 
  * Line 200: `RESP=$(post ...) || { log "FATAL: announce post failed after retries"; exit 1; }`
  * Line 202: `DIR=$(...) || { log "no directive in announce reply -> parking..."; exit 0; }`
  * Line 285: `RESP=$(post ...) || { log "retry post failed — digest archived; relaunch bridge to resume"; exit 1; }`
  * Line 288: `if ! DIR=$(poll_directive); then log "still no directive -> parking..."; exit 0; fi`
  * Line 292: `log "no directive -> parking..."; exit 0`
  * Line 295: `log "digest post failed after retries... relaunch bridge to resume"; exit 1`
* **Root Cause:** 
  1. **Parking Death (`exit 0`):** When the owner chats with the AI agent, conversation messages contain human/agent chat instead of `===XENOLIFT-DIRECTIVE===` blocks. `poll_directive()` polls for 600s (10 minutes). Once 600s passes without finding a directive block, `poll_directive()` returns 1, causing lines 202, 288, and 292 to execute `exit 0` ("parking").
  2. **Transient Error Death (`exit 1`):** If API calls encounter transient HTTP 5xx/429/409 errors or timeouts during heavy chat activity, `post()` retries 5 times and then returns 1, triggering `exit 1`.
  In both scenarios, the script quietly exits. Without an outer auto-restart wrapper, the process dies completely.

### Rank 3: Missing Per-Poll Heartbeat Visibility & Poll Timeouts (Line 160)
* **Location in v7:** Line 160 (`g=$(curl -s -m 60 "$API" -H "api_key: $KEY")`)
* **Root Cause:** Polling GET requests used `-m 60` without `-sS` and lacked timestamped HTTP status logging. When GET requests stalled or failed during web chat turns, no forensic trail was left in `bridge5.log`. Malformed or non-200 responses silently failed extraction, eventually triggering the parking exit.

---

## 2. Changes Implemented in `xenolift-bridge8.sh`

`xenolift-bridge8.sh` was written to `xenolift/bridge/xenolift-bridge8.sh` as a drop-in replacement for v7 with the following hardening rules:

1. **Strict per-request curl timeouts & explicit error flags (`-sS --max-time`):**
   * Digest POSTs: max 120s (`--max-time 120 -sS`).
   * Directive GET polls: max 30s (`--max-time 30 -sS`).
   * Package Zip downloads: max 300s (`--max-time 300 -sS`).
2. **Eliminated Exit-on-Transient-Error:**
   * Both `post()` and `poll_directive()` now retry indefinitely with exponential backoff on HTTP errors, timeouts, or non-200 status codes.
   * Only missing `KEY_FILE`, missing disc image `BIN`, or missing `WORK` workspace directory trigger fatal exits (`exit 1`).
3. **Never Parse-and-Exit:**
   * Malformed, empty, or chat-only API responses are safely logged and skipped, continuing the poll loop without exiting.
4. **Forensic Heartbeat Logging:**
   * Every GET poll and POST attempt writes a timestamped heartbeat line (`[heartbeat YYYY-MM-DD HH:MM:SS] ... http=CODE len=BYTES`) to `~/Downloads/bridge5.log`.
5. **Preserved Core Engine Features:**
   * Retained v7 Autopilot zero-turn skipping logic (`AUTO_N`).
   * Retained v7.1 zombie-proof completion (`$DONEF` file polling).
   * Retained v6 420s run watchdog.
   * Retained v5.2 hardened multi-shape Python directive extractor.

---

## 3. Recommended One-Paste Relaunch Command

To run `xenolift-bridge8.sh` with self-healing auto-restart protection on macOS:

```bash
pkill -f xenolift-bridge; sleep 2; while true; do caffeinate -i ~/Downloads/xenolift-bridge8.sh 500; echo dead-restart; sleep 10; done
```

---

## 4. Verification

* **Syntax Verification:** Ran `bash -n xenolift/bridge/xenolift-bridge8.sh` — passed cleanly (`SYNTAX OK`).
* **Drop-in Compatibility:** Verified that environment variables (`KEY_FILE`, `CONV_FILE`, `AGENT`, `WORK`, `LOG`, `ARCHIVE`, `BIN`), CLI argument parsing (`MAXCY`), and output formats match v7 line-for-line.
