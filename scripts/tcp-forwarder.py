#!/usr/bin/env python3
import os
import select
import socket
import socketserver
import sys


BIND = os.environ.get("TCP_FORWARD_BIND", "0.0.0.0")
PORT = int(os.environ.get("TCP_FORWARD_PORT", "8822"))
TARGET_HOST = os.environ.get("TCP_FORWARD_TARGET_HOST", "host.docker.internal")
TARGET_PORT = int(os.environ.get("TCP_FORWARD_TARGET_PORT", "8822"))
BUFFER_SIZE = 64 * 1024


class ForwardHandler(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            upstream = socket.create_connection((TARGET_HOST, TARGET_PORT), timeout=10)
        except OSError as exc:
            print(
                f"tcp-forwarder: cannot connect to {TARGET_HOST}:{TARGET_PORT}: {exc}",
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
    print(
        f"tcp-forwarder: listening on {BIND}:{PORT}, forwarding to {TARGET_HOST}:{TARGET_PORT}",
        file=sys.stderr,
        flush=True,
    )
    with ThreadingForwarder((BIND, PORT), ForwardHandler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
