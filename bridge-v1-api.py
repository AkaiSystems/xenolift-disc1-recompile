#!/usr/bin/env python3
import getpass, json, os, re, signal, subprocess, sys, tempfile, time
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

AGENT_ID = "6aa26c7ce0ac9a5ee05d2b95"
CONVERSATION_ID = "6ab09035fdeb623a9d6e6e99"
WORKDIR = os.path.expanduser("~/Downloads/xenolift")
STATE = os.path.join(WORKDIR, ".bridge-v1-api-state.json")
RUNFILE = os.path.join(WORKDIR, ".bridge-v1-current.sh")
LOGFILE = os.path.join(WORKDIR, ".bridge-v1-api.log")
POLL_SECONDS = 2
RUN_TIMEOUT = 600
STOP = False
LAST_COMPLETED = None
USED_TOKENS = set()


def stamp():
    return datetime.now().astimezone().strftime("%H:%M:%S")


def say(message):
    line = f"[{stamp()}] {message}"
    print(line, flush=True)
    with open(LOGFILE, "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def request(method, url, key, body=None, timeout=35):
    raw = None if body is None else json.dumps(body).encode("utf-8")
    auth_path = None
    try:
        fd, auth_path = tempfile.mkstemp(prefix="xenolift-auth-", text=True)
        os.fchmod(fd, 0o600)
        escaped = key.replace("\\", "\\\\").replace('"', '\\"')
        config = (
            f'header = "Authorization: Bearer {escaped}"\n'
            'header = "Accept: application/json"\n'
            'header = "Content-Type: application/json"\n'
        )
        os.write(fd, config.encode("utf-8"))
        os.close(fd)
        command = [
            "/usr/bin/curl", "-sS", "--config", auth_path,
            "--request", method, "--connect-timeout", "15",
            "--max-time", str(timeout), "--write-out", "\n__HTTP_STATUS__:%{http_code}",
            url,
        ]
        if raw is not None:
            command[1:1] = ["--data-binary", "@-"]
        result = subprocess.run(command, input=raw, capture_output=True)
        if result.returncode != 0:
            raise RuntimeError("curl rc=%d: %s" % (result.returncode, result.stderr.decode("utf-8", "replace")[:500]))
        text = result.stdout.decode("utf-8", "replace")
        marker = "\n__HTTP_STATUS__:"
        if marker not in text:
            raise RuntimeError("curl response missing HTTP status")
        payload_text, status_text = text.rsplit(marker, 1)
        status = int(status_text.strip())
        if status >= 400:
            raise HTTPError(url, status, payload_text[:1000], None, None)
        parsed = json.loads(payload_text) if payload_text else {}
        return status, parsed
    finally:
        if auth_path:
            try:
                os.unlink(auth_path)
            except FileNotFoundError:
                pass


def candidate_urls():
    return [f"https://app.base44.com/api/agents/{AGENT_ID}/conversations/{CONVERSATION_ID}"]


def choose_endpoint(key):
    failures = []
    for url in candidate_urls():
        try:
            status, payload = request("GET", url, key)
            if status == 200:
                say("API AUTH PASS")
                say("Endpoint: " + url)
                return url, payload
        except HTTPError as exc:
            failures.append(f"{url} -> HTTP {exc.code}")
        except Exception as exc:
            failures.append(f"{url} -> {type(exc).__name__}: {str(exc)[:100]}")
    say("API AUTH FAILED. No bridge was started.")
    for failure in failures:
        say(failure)
    raise SystemExit(2)


def message_rows(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("messages", "data", "items", "records", "results"):
            value = payload.get(key)
            if isinstance(value, list):
                return value
            if isinstance(value, dict):
                nested = message_rows(value)
                if nested:
                    return nested
    return []


def flatten(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(filter(None, (flatten(item) for item in value)))
    if isinstance(value, dict):
        for key in ("text", "content", "markdown", "body", "value", "message"):
            result = flatten(value.get(key))
            if result:
                return result
    return ""


def message_id(message):
    return str(message.get("id") or message.get("_id") or message.get("message_id") or message.get("checkpoint_id") or "")


def message_text(message):
    return flatten(message.get("content") if "content" in message else message)


def parse_directive(text):
    if "XENOLIFT_DIRECTIVE" not in text:
        return None
    marker = text.find("XENOLIFT_DIRECTIVE")
    for match in re.finditer(r"\{", text[marker:]):
        start = marker + match.start()
        try:
            obj, _ = json.JSONDecoder().raw_decode(text[start:])
        except Exception:
            continue
        if not isinstance(obj, dict):
            continue
        token = obj.get("token") or obj.get("directive_token")
        block = obj.get("block") or obj.get("block_text") or obj.get("script")
        parent = obj.get("parent_token")
        protocol = obj.get("protocol")
        if token and isinstance(block, str):
            return str(token), block, (None if parent is None else str(parent)), protocol
    return None


def parse_digest_token(text):
    if "XENOLIFT_DIGEST" not in text:
        return None
    marker = text.find("XENOLIFT_DIGEST")
    for match in re.finditer(r"\{", text[marker:]):
        start = marker + match.start()
        try:
            obj, _ = json.JSONDecoder().raw_decode(text[start:])
        except Exception:
            continue
        if isinstance(obj, dict) and obj.get("directive_token"):
            return str(obj["directive_token"])
    return None


def post_message(endpoint, key, content):
    payloads = [
        {"role": "user", "content": content},
        {"content": content},
    ]
    for index, payload in enumerate(payloads):
        try:
            status, _ = request("POST", endpoint, key, payload, timeout=90)
            if 200 <= status < 300:
                return
        except HTTPError as exc:
            # Retry an alternate body only for a definite schema rejection.
            if exc.code not in (400, 415, 422) or index == len(payloads) - 1:
                raise
    raise RuntimeError("digest POST rejected")


def save_state(seen):
    temp = STATE + ".tmp"
    with open(temp, "w", encoding="utf-8") as handle:
        json.dump({
            "seen": list(seen)[-2000:],
            "last_completed": LAST_COMPLETED,
            "used_tokens": list(USED_TOKENS)[-2000:],
        }, handle)
    os.replace(temp, STATE)


def reject(endpoint, key, token, reason, parent=None):
    say(f"REJECT {token}: {reason}")
    post_message(endpoint + "/messages", key, "[XENOLIFT_REJECT]\n" + json.dumps({
        "directive_token": token,
        "parent_token": parent,
        "reason": reason,
        "last_completed_token": LAST_COMPLETED,
    }))


def run_cycle(endpoint, key, token, block, parent):
    global LAST_COMPLETED
    say("=" * 70)
    say(f"PICKUP {token} parent={parent}")
    with open(RUNFILE, "w", encoding="utf-8") as handle:
        handle.write(block)
    os.chmod(RUNFILE, 0o700)
    syntax = subprocess.run(["/bin/bash", "-n", RUNFILE], capture_output=True, text=True)
    pickup = {
        "directive_token": token,
        "parent_token": parent,
        "status": "syntax_pass" if syntax.returncode == 0 else "syntax_fail",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "protocol": "xenolift-v1.1",
    }
    post_message(endpoint + "/messages", key, "[XENOLIFT_PICKUP]\n" + json.dumps(pickup))
    say(f"PICKUP POSTED {token}")
    if syntax.returncode:
        output = "SHELL_SYNTAX_FAIL\n" + syntax.stderr
        say("SYNTAX FAIL")
        post_message(endpoint + "/messages", key, "[XENOLIFT_DIGEST]\n" + json.dumps({"directive_token": token, "parent_token": parent, "digest_text": output}))
        LAST_COMPLETED = token
        return
    say("SYNTAX PASS")
    say("RUN START. Output follows live:")
    started = time.monotonic()
    lines = []
    process = subprocess.Popen(
        ["/bin/bash", RUNFILE], cwd=WORKDIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    try:
        assert process.stdout is not None
        while True:
            line = process.stdout.readline()
            if line:
                print(line, end="", flush=True)
                lines.append(line)
            if process.poll() is not None:
                rest = process.stdout.read()
                if rest:
                    print(rest, end="", flush=True)
                    lines.append(rest)
                break
            if time.monotonic() - started > RUN_TIMEOUT:
                process.terminate()
                try:
                    process.wait(10)
                except subprocess.TimeoutExpired:
                    process.kill()
                lines.append("\nBRIDGE_RUN_TIMEOUT\n")
                break
    finally:
        rc = process.poll()
        if rc is None:
            process.kill(); rc = 124
    elapsed = int(time.monotonic() - started)
    output = "".join(lines)
    # Keep one complete digest message below the platform content limit.
    if len(output) > 44000:
        output = output[:12000] + "\n...[BRIDGE DIGEST COMPACTED; FULL OUTPUT REMAINS IN TERMINAL]...\n" + output[-30000:]
    digest = output + f"\n[bridge-v1.1-api rc={rc} elapsed={elapsed}s]"
    say(f"RUN END rc={rc} elapsed={elapsed}s")
    post_message(endpoint + "/messages", key, "[XENOLIFT_DIGEST]\n" + json.dumps({
        "directive_token": token,
        "parent_token": parent,
        "protocol": "xenolift-v1.1",
        "digest_text": digest,
    }))
    LAST_COMPLETED = token
    say(f"DIGEST POSTED {token}")
    say(f"WAITING FOR NEXT AGENT-APPROVED DIRECTIVE parent_token={token}")


def stop_handler(*_):
    global STOP
    STOP = True


def main():
    global LAST_COMPLETED, USED_TOKENS
    print("\nXENOLIFT BRIDGE V1.1 API, FOREGROUND HANDSHAKE MODE")
    print("One cycle at a time. Ctrl-C stops it. Nothing runs in the background.\n")
    key = os.environ.get("BASE44_API_KEY") or getpass.getpass("Paste Base44 access token (hidden): ").strip()
    if not key:
        raise SystemExit("No access token supplied")
    endpoint, initial = choose_endpoint(key)
    rows = message_rows(initial)
    seen = {message_id(item) for item in rows if message_id(item)}
    # Bootstrap the handshake from the latest digest already in this conversation.
    for item in rows:
        token = parse_digest_token(message_text(item))
        if token:
            LAST_COMPLETED = token
            USED_TOKENS.add(token)
    save_state(seen)
    say(f"BASELINE PASS: {len(seen)} existing messages ignored")
    say(f"HANDSHAKE BASELINE: last_completed={LAST_COMPLETED}")
    say(f"LIVE: polling every {POLL_SECONDS}s")
    say("Waiting for next agent-approved directive")
    while not STOP:
        try:
            _, payload = request("GET", endpoint, key)
            rows = message_rows(payload)
            for message in rows:
                identity = message_id(message)
                if not identity or identity in seen:
                    continue
                seen.add(identity)
                directive = parse_directive(message_text(message))
                if not directive:
                    continue
                token, block, parent, protocol = directive
                save_state(seen)
                if protocol != "xenolift-v1.1":
                    reject(endpoint, key, token, "protocol_mismatch", parent)
                    continue
                if token in USED_TOKENS:
                    reject(endpoint, key, token, "duplicate_token", parent)
                    continue
                if parent != LAST_COMPLETED:
                    reject(endpoint, key, token, "parent_token_mismatch", parent)
                    continue
                USED_TOKENS.add(token)
                save_state(seen)
                run_cycle(endpoint, key, token, block, parent)
                save_state(seen)
            save_state(seen)
        except KeyboardInterrupt:
            break
        except Exception as exc:
            say(f"POLL ERROR: {type(exc).__name__}: {exc}")
        for _ in range(POLL_SECONDS * 10):
            if STOP:
                break
            time.sleep(0.1)
    say("BRIDGE STOPPED")


signal.signal(signal.SIGINT, stop_handler)
signal.signal(signal.SIGTERM, stop_handler)
main()
