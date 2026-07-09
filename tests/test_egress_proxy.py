import importlib.util
import socket
import threading
from pathlib import Path
from types import SimpleNamespace
from unittest import mock
import unittest


spec = importlib.util.spec_from_file_location(
    "egress_proxy", Path(__file__).resolve().parents[1] / "scripts/egress-proxy.py"
)
egress_proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(egress_proxy)


class RelayTests(unittest.TestCase):
    def test_client_half_close_does_not_drop_large_response(self):
        client, proxy_client = socket.socketpair()
        upstream, proxy_upstream = socket.socketpair()
        payload = b"x" * 800_000
        received = bytearray()
        errors = []

        fake_handler = SimpleNamespace(connection=proxy_client, timeout=1)
        thread = threading.Thread(
            target=egress_proxy.ProxyHandler.relay,
            args=(fake_handler, proxy_upstream),
        )

        def write_response():
            try:
                upstream.sendall(payload)
                upstream.shutdown(socket.SHUT_WR)
            except Exception as exc:
                errors.append(exc)

        writer = threading.Thread(target=write_response)
        thread.start()
        client.shutdown(socket.SHUT_WR)
        writer.start()

        try:
            while True:
                chunk = client.recv(65536)
                if not chunk:
                    break
                received.extend(chunk)
        except Exception as exc:
            errors.append(exc)
        finally:
            client.close()
            upstream.close()
            writer.join(2)
            thread.join(2)
            proxy_client.close()
            proxy_upstream.close()

        self.assertFalse(errors)
        self.assertFalse(writer.is_alive())
        self.assertFalse(thread.is_alive())
        self.assertEqual(payload, bytes(received))

    def test_relay_ignores_idle_select_timeout(self):
        client, proxy_client = socket.socketpair()
        upstream, proxy_upstream = socket.socketpair()
        payload = b"done"
        calls = [([], [], []), ([proxy_upstream], [], [])]

        def fake_select(readers, *_args):
            if calls:
                return calls.pop(0)
            return list(readers), [], []

        fake_handler = SimpleNamespace(connection=proxy_client, timeout=0.01)
        thread = threading.Thread(
            target=lambda: egress_proxy.ProxyHandler.relay(fake_handler, proxy_upstream),
        )

        with mock.patch.object(egress_proxy.select, "select", side_effect=fake_select):
            thread.start()
            upstream.sendall(payload)
            self.assertEqual(client.recv(16), payload)
            upstream.shutdown(socket.SHUT_WR)
            client.shutdown(socket.SHUT_WR)
            thread.join(2)

        client.close()
        upstream.close()
        proxy_client.close()
        proxy_upstream.close()
        self.assertFalse(thread.is_alive())


if __name__ == "__main__":
    unittest.main()
