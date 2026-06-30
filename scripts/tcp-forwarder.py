#!/usr/bin/env python3
import os
import select
import socket
import socketserver
import sys
import threading


BIND = os.environ.get("TCP_FORWARD_BIND", "0.0.0.0")
PORT = int(os.environ.get("TCP_FORWARD_PORT", "8822"))
PORTS = os.environ.get("TCP_FORWARD_PORTS", "")
TARGET_HOST = os.environ.get("TCP_FORWARD_TARGET_HOST", "host.docker.internal")
BUFFER_SIZE = 64 * 1024


class ForwardHandler(socketserver.BaseRequestHandler):
    def handle(self):
        target_port = self.server.server_address[1]
        try:
            upstream = socket.create_connection((TARGET_HOST, target_port), timeout=10)
        except OSError as exc:
            print(
                f"tcp-forwarder: cannot connect to {TARGET_HOST}:{target_port}: {exc}",
                file=sys.stderr,
                flush=True,
            )
            return
        sockets = [self.request, upstream]
        try:
            while True:
                readable, _, _ = select.select(sockets, [], [], 60)
                if not readable:
                    continue
                for source in readable:
                    data = source.recv(BUFFER_SIZE)
                    if not data:
                        return
                    target = upstream if source is self.request else self.request
                    target.sendall(data)
        except OSError as exc:
            print(f"tcp-forwarder: relay failed: {exc}", file=sys.stderr, flush=True)
        finally:
            upstream.close()


class ThreadingForwarder(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ports = sorted({PORT} | {int(port) for port in PORTS.replace(" ", "").split(",") if port})
    servers = []
    for port in ports:
        server = ThreadingForwarder((BIND, port), ForwardHandler)
        servers.append(server)
        print(
            f"tcp-forwarder: listening on {BIND}:{port}, forwarding to {TARGET_HOST}:{port}",
            file=sys.stderr,
            flush=True,
        )
        threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        threading.Event().wait()
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
