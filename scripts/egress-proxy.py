#!/usr/bin/env python3
import datetime as dt
import fnmatch
import hashlib
import json
import os
import pathlib
import select
import socket
import socketserver
import sys
import time
import urllib.parse
import uuid


APPROVALS_FILE = os.environ.get("EGRESS_APPROVALS_FILE", "/policy/approvals.json")
LOG_FILE = os.environ.get("EGRESS_LOG_FILE", "/state/egress.log")
REQUEST_DIR = pathlib.Path(os.environ.get("EGRESS_REQUEST_DIR", "/jail-requests"))
BIND = os.environ.get("EGRESS_BIND", "0.0.0.0")
PORT = int(os.environ.get("EGRESS_PORT", "8080"))
BUFFER_SIZE = 64 * 1024
BODY_METHODS = {"POST", "PUT", "PATCH"}
WAIT_FOR_APPROVAL = os.environ.get("EGRESS_WAIT_FOR_APPROVAL", "true").lower() not in {"0", "false", "no"}
APPROVAL_WAIT_TIMEOUT = int(os.environ.get("EGRESS_APPROVAL_WAIT_TIMEOUT", "0"))
APPROVAL_POLL_SECONDS = float(os.environ.get("EGRESS_APPROVAL_POLL_SECONDS", "1"))


def utc_now():
    return dt.datetime.now(dt.timezone.utc)


def parse_time(value):
    if not value:
        return None
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return dt.datetime.fromisoformat(value)


def load_policy():
    try:
        with open(APPROVALS_FILE, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return {"rules": []}
    except json.JSONDecodeError as exc:
        return {"rules": [], "policy_error": str(exc)}
    if not isinstance(data, dict):
        return {"rules": [], "policy_error": "policy root must be an object"}
    data.setdefault("rules", [])
    data.setdefault("blocks", [])
    return data


def append_log(record):
    record["ts"] = utc_now().isoformat()
    line = json.dumps(record, sort_keys=True)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        print(line, file=sys.stderr, flush=True)


def request_key(protocol, host, port):
    raw = f"egress:{host.lower().rstrip('.')}:{int(port or 443)}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def pending_request_path(key):
    for path in REQUEST_DIR.glob("*.json"):
        request = read_json(path)
        if not isinstance(request, dict):
            continue
        if request.get("status", "pending") != "pending":
            continue
        if request.get("dedupe_key") == key:
            return path
    return None


def merge_pending_request(path, protocol, target, reason):
    request = read_json(path)
    if not isinstance(request, dict):
        return path
    payload = request.setdefault("payload", {})
    protocols = sorted(set(payload.get("protocols") or []) | {protocol})
    payload["protocols"] = protocols
    payload["target"] = target
    payload["deny_reason"] = reason
    request["last_seen_at"] = utc_now().isoformat()
    request["seen_count"] = int(request.get("seen_count") or 1) + 1
    path.write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def write_auto_request(protocol, host, port, target, reason):
    key = request_key(protocol, host, port)
    try:
        REQUEST_DIR.mkdir(parents=True, exist_ok=True)
        existing = pending_request_path(key)
        if existing:
            return merge_pending_request(existing, protocol, target, reason)
        request_id = f"{utc_now().strftime('%Y%m%dT%H%M%SZ')}-{uuid.uuid4().hex[:12]}"
        now = utc_now().isoformat()
        request = {
            "id": request_id,
            "kind": "egress",
            "status": "pending",
            "dedupe_key": key,
            "created_at": now,
            "last_seen_at": now,
            "seen_count": 1,
            "cwd": "",
            "source": "egress-proxy",
            "payload": {
                "host": host,
                "port": int(port or 443),
                "protocols": [protocol],
                "ttl": "10m",
                "reason": f"AUTO_DENIED_{protocol.upper()}",
                "target": target,
                "deny_reason": reason,
            },
        }
        path = REQUEST_DIR / f"{request_id}.json"
        path.write_text(json.dumps(request, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        try:
            path.chmod(0o666)
        except OSError:
            pass
        return path
    except OSError as exc:
        append_log({
            "decision": "request_error",
            "reason": str(exc),
            "host": host,
            "port": port,
            "protocol": protocol,
            "target": target,
        })
        return None


def wait_for_operator_decision(protocol, host, port, target, reason):
    request_path = write_auto_request(protocol, host, port, target, reason)
    if not WAIT_FOR_APPROVAL or not request_path:
        return False, {"reason": reason, "request_path": str(request_path) if request_path else ""}

    deadline = None
    if APPROVAL_WAIT_TIMEOUT > 0:
        deadline = time.monotonic() + APPROVAL_WAIT_TIMEOUT

    append_log({
        "decision": "wait",
        "reason": reason,
        "host": host,
        "port": port,
        "protocol": protocol,
        "target": target,
        "request_path": str(request_path),
    })

    while True:
        ok, info = allowed(protocol, host, port)
        if ok:
            info = dict(info)
            info["waited_for_approval"] = True
            info["request_path"] = str(request_path)
            return True, info
        if info.get("reason") == "blocked":
            info = dict(info)
            info["request_path"] = str(request_path)
            return False, info

        request = read_json(request_path)
        if isinstance(request, dict):
            status = request.get("status", "pending")
            if status == "denied":
                return False, {
                    "reason": "operator_denied",
                    "detail": request.get("decision_reason", "denied by host operator"),
                    "request_path": str(request_path),
                }
            if status == "approved":
                ok, info = allowed(protocol, host, port)
                info = dict(info)
                info["request_path"] = str(request_path)
                if ok:
                    info["waited_for_approval"] = True
                    return True, info
                info.setdefault("detail", "request was approved, but no active matching policy rule is present")
                return False, info
        elif not request_path.exists():
            return False, {
                "reason": "request_missing",
                "detail": "pending request disappeared before operator decision",
                "request_path": str(request_path),
            }

        if deadline is not None and time.monotonic() >= deadline:
            return False, {
                "reason": "approval_timeout",
                "detail": f"no operator decision within {APPROVAL_WAIT_TIMEOUT}s",
                "request_path": str(request_path),
            }

        time.sleep(APPROVAL_POLL_SECONDS)


def host_matches(rule, host):
    host = host.lower().rstrip(".")
    if "host" in rule and host == str(rule["host"]).lower().rstrip("."):
        return True
    if "host_suffix" in rule:
        suffix = str(rule["host_suffix"]).lower().rstrip(".")
        return host == suffix.lstrip(".") or host.endswith(suffix)
    if "host_glob" in rule:
        return fnmatch.fnmatch(host, str(rule["host_glob"]).lower())
    return False


def rule_allows(rule, protocol, host, port):
    if not rule.get("enabled", True):
        return False
    expires_at = parse_time(rule.get("expires_at"))
    if expires_at and utc_now() >= expires_at:
        return False
    protocols = rule.get("protocols")
    if protocols and protocol not in protocols:
        return False
    rule_port = rule.get("port")
    if rule_port is not None and int(rule_port) != int(port):
        return False
    return host_matches(rule, host)


def rule_blocks(rule, protocol, host, port):
    if not rule.get("enabled", True):
        return False
    protocols = rule.get("protocols")
    if protocols and protocol not in protocols:
        return False
    rule_port = rule.get("port")
    if rule_port is not None and int(rule_port) != int(port):
        return False
    return host_matches(rule, host)


def allowed(protocol, host, port):
    policy = load_policy()
    if policy.get("policy_error"):
        return False, {"reason": "policy_error", "detail": policy["policy_error"]}
    for rule in policy.get("blocks", []):
        if isinstance(rule, dict) and rule_blocks(rule, protocol, host, port):
            return False, {"reason": "blocked", "rule": rule.get("name", "unnamed")}
    for rule in policy.get("rules", []):
        if isinstance(rule, dict) and rule_allows(rule, protocol, host, port):
            return True, {"rule": rule.get("name", "unnamed")}
    return False, {"reason": "default_deny"}


def split_host_port(target, default_port):
    if target.startswith("["):
        host, _, rest = target[1:].partition("]")
        if rest.startswith(":"):
            return host, int(rest[1:])
        return host, default_port
    host, sep, port = target.rpartition(":")
    if sep and port.isdigit():
        return host, int(port)
    return target, default_port


def deny_body(reason, host, port, target, protocol=None):
    host = host or "unknown"
    port = int(port or 0)
    protocol_text = protocol or "unknown"
    egress_port = port if port else 443
    return f"""HARDENED JAIL: egress denied

Attempted: {protocol_text} {host}:{port}
Target: {target}
Reason: {reason}

Use one of these request paths instead of retrying direct network commands:

  Generic HTTPS/TCP egress:
    A pending request has been created automatically when possible.
    Review it from the host with:
      .devcontainer/host/jail-operator

  Package/tool installs:
    jailctl install --run pnpm install --frozen-lockfile
    jailctl install --run uv sync
    jailctl install --run cargo fetch
    jailctl install --run go mod download

  Agent login:
    jailctl agent-login codex
    jailctl agent-login claude

  SSH:
    ssh <target-or-alias>
    jailctl ssh-lease <approved-alias> --ttl 30m --wait

Host approval:

  .devcontainer/host/jail-operator

Direct egress is blocked by design. Do not retry direct installs/downloads repeatedly.
"""


class ProxyHandler(socketserver.StreamRequestHandler):
    timeout = 30

    def handle(self):
        request_line = self.rfile.readline(65536).decode("iso-8859-1").strip()
        if not request_line:
            return
        parts = request_line.split()
        if len(parts) != 3:
            self.deny("malformed", "unknown", 0, request_line)
            return

        method, target, _version = parts
        headers = self.read_headers()

        if method.upper() == "CONNECT":
            host, port = split_host_port(target, 443)
            self.handle_connect(host, port, target)
            return

        parsed = urllib.parse.urlsplit(target)
        if not parsed.hostname:
            self.deny("absolute_uri_required", "unknown", 0, target)
            return
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        self.handle_http(method, target, parsed.hostname, port, headers, request_line)

    def read_headers(self):
        headers = []
        while True:
            line = self.rfile.readline(65536)
            if line in (b"\r\n", b"\n", b""):
                break
            headers.append(line)
        return headers

    def header_value(self, headers, name):
        prefix = name.lower().encode("ascii") + b":"
        for header in headers:
            if header.lower().startswith(prefix):
                return header.split(b":", 1)[1].strip().decode("iso-8859-1")
        return ""

    def request_body_length(self, method, headers):
        transfer_encoding = self.header_value(headers, "Transfer-Encoding").lower()
        if transfer_encoding and transfer_encoding != "identity":
            raise ValueError("chunked request bodies are not supported by this proxy")
        content_length = self.header_value(headers, "Content-Length")
        if content_length:
            return int(content_length)
        return 0 if method.upper() not in BODY_METHODS else 0

    def deny(self, reason, host, port, target, extra=None):
        protocol = extra.get("protocol") if extra else None
        body = deny_body(reason, host, port, target, protocol).encode("utf-8")
        record = {
            "decision": "deny",
            "reason": reason,
            "client": self.client_address[0],
            "host": host,
            "port": port,
            "target": target,
            "guidance": {
                "egress": ".devcontainer/host/jail-operator",
                "install": "jailctl install --run <manager> <args...>",
                "ssh": "ssh <target-or-alias>",
            },
        }
        if extra:
            record.update(extra)
        append_log(record)
        response = (
            b"HTTP/1.1 403 Forbidden\r\n"
            + b"Content-Type: text/plain\r\n"
            + f"Content-Length: {len(body)}\r\n".encode("ascii")
            + b"Connection: close\r\n\r\n"
            + body
        )
        self.wfile.write(response)

    def handle_connect(self, host, port, target):
        ok, info = allowed("connect", host, port)
        if not ok:
            if info.get("reason") == "default_deny":
                ok, info = wait_for_operator_decision("connect", host, port, target, info["reason"])
            if ok:
                self.allow_connect(host, port, target, info)
                return
            self.deny(info.get("reason", "default_deny"), host, port, target, {"protocol": "connect", **info})
            return
        self.allow_connect(host, port, target, info)

    def allow_connect(self, host, port, target, info):
        append_log({
            "decision": "allow",
            "protocol": "connect",
            "client": self.client_address[0],
            "host": host,
            "port": port,
            "target": target,
            **info,
        })
        try:
            upstream = socket.create_connection((host, port), timeout=20)
        except OSError as exc:
            self.wfile.write(
                f"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n{exc}\n".encode("utf-8")
            )
            return
        self.wfile.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        self.relay(upstream)

    def handle_http(self, method, target, host, port, headers, request_line):
        try:
            body_length = self.request_body_length(method, headers)
        except (ValueError, UnicodeError) as exc:
            self.deny("unsupported_request_body", host, port, target, {"protocol": "http", "method": method, "detail": str(exc)})
            return
        ok, info = allowed("http", host, port)
        if not ok:
            if info.get("reason") == "default_deny":
                ok, info = wait_for_operator_decision("http", host, port, target, info["reason"])
            if ok:
                self.allow_http(method, target, host, port, headers, body_length, info)
                return
            self.deny(info.get("reason", "default_deny"), host, port, target, {"protocol": "http", "method": method, **info})
            return
        self.allow_http(method, target, host, port, headers, body_length, info)

    def allow_http(self, method, target, host, port, headers, body_length, info):
        append_log({
            "decision": "allow",
            "protocol": "http",
            "method": method,
            "client": self.client_address[0],
            "host": host,
            "port": port,
            "target": target,
            **info,
        })
        parsed = urllib.parse.urlsplit(target)
        path = urllib.parse.urlunsplit(("", "", parsed.path or "/", parsed.query, ""))
        try:
            upstream = socket.create_connection((host, port), timeout=20)
        except OSError as exc:
            self.wfile.write(
                f"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n{exc}\n".encode("utf-8")
            )
            return
        with upstream:
            upstream.sendall(f"{method} {path} HTTP/1.1\r\n".encode("iso-8859-1"))
            for header in headers:
                if not header.lower().startswith(b"proxy-connection:"):
                    upstream.sendall(header)
            upstream.sendall(b"\r\n")
            remaining = body_length
            while remaining:
                chunk = self.rfile.read(min(BUFFER_SIZE, remaining))
                if not chunk:
                    return
                upstream.sendall(chunk)
                remaining -= len(chunk)
            self.relay(upstream)

    def relay(self, upstream):
        sockets = [self.connection, upstream]
        try:
            while True:
                readable, _, _ = select.select(sockets, [], [], self.timeout)
                if not readable:
                    return
                for sock in readable:
                    data = sock.recv(BUFFER_SIZE)
                    if not data:
                        return
                    other = upstream if sock is self.connection else self.connection
                    other.sendall(data)
        finally:
            upstream.close()


class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    print(f"egress-proxy listening on {BIND}:{PORT}", flush=True)
    with ThreadingTCPServer((BIND, PORT), ProxyHandler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
