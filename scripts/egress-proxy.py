#!/usr/bin/env python3
import datetime as dt
import fnmatch
import json
import os
import select
import socket
import socketserver
import sys
import urllib.parse


APPROVALS_FILE = os.environ.get("EGRESS_APPROVALS_FILE", "/policy/approvals.json")
LOG_FILE = os.environ.get("EGRESS_LOG_FILE", "/state/egress.log")
BIND = os.environ.get("EGRESS_BIND", "0.0.0.0")
PORT = int(os.environ.get("EGRESS_PORT", "8080"))
BUFFER_SIZE = 64 * 1024


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


def allowed(protocol, host, port):
    policy = load_policy()
    if policy.get("policy_error"):
        return False, {"reason": "policy_error", "detail": policy["policy_error"]}
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
    jailctl egress {host} --port {egress_port} --reason "<why this access is needed>"

  Package/tool installs:
    jailctl install npm ci
    jailctl install uv sync
    jailctl install cargo fetch
    jailctl install go mod download

  SSH:
    jailctl ssh <approved-alias>
    jailctl ssh-lease <approved-alias> --ttl 30m

Host approval examples:

  .devcontainer/host/jail-approve-egress add {host} --port {egress_port} --ttl 10m --reason "<why>"
  .devcontainer/host/jail-ssh-broker requests --kind ssh-lease

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
                "egress": f"jailctl egress {host} --port {int(port or 443)} --reason \"<why>\"",
                "install": "jailctl install <manager> <args...>",
                "ssh": "jailctl ssh <approved-alias>",
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
            self.deny(info.get("reason", "default_deny"), host, port, target, {"protocol": "connect", **info})
            return
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
        ok, info = allowed("http", host, port)
        if not ok:
            self.deny(info.get("reason", "default_deny"), host, port, target, {"protocol": "http", "method": method, **info})
            return
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
