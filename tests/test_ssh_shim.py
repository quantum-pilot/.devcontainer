import importlib.machinery
import importlib.util
import os
from pathlib import Path
from unittest import mock
import unittest


path = Path(__file__).resolve().parents[1] / "scripts/ssh"
loader = importlib.machinery.SourceFileLoader("ssh_shim", str(path))
spec = importlib.util.spec_from_loader("ssh_shim", loader)
ssh_shim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ssh_shim)


class WinsizeTests(unittest.TestCase):
    def test_winsize_maps_columns_and_rows_correctly(self):
        with mock.patch("os.get_terminal_size", return_value=os.terminal_size((132, 43))):
            self.assertEqual(ssh_shim.winsize(), {"rows": 43, "cols": 132})

    def test_modern_scp_argv_is_supported(self):
        payload = ssh_shim.parse_argv([
            "-x",
            "-oPermitLocalCommand=no",
            "-oClearAllForwardings=yes",
            "-oRemoteCommand=none",
            "-oRequestTTY=no",
            "-oForwardAgent=no",
            "-p",
            "2222",
            "-l",
            "user",
            "-s",
            "--",
            "example.com",
            "sftp",
        ])
        self.assertEqual(payload["host"], "example.com")
        self.assertEqual(payload["user"], "user")
        self.assertEqual(payload["port"], 2222)
        self.assertEqual(payload["remote_args"], ["sftp"])

    def test_sftp_port_option_is_supported(self):
        payload = ssh_shim.parse_argv([
            "-oForwardX11 no",
            "-oPermitLocalCommand no",
            "-oClearAllForwardings yes",
            "-oForwardAgent no",
            "-oPort 2222",
            "-l",
            "user",
            "-s",
            "--",
            "example.com",
            "sftp",
        ])
        self.assertEqual(payload["host"], "example.com")
        self.assertEqual(payload["user"], "user")
        self.assertEqual(payload["port"], 2222)
        self.assertEqual(payload["remote_args"], ["sftp"])

    def test_legacy_scp_argv_is_supported(self):
        payload = ssh_shim.parse_argv([
            "-x",
            "-oPermitLocalCommand=no",
            "-oClearAllForwardings=yes",
            "-oRemoteCommand=none",
            "-oRequestTTY=no",
            "-oForwardAgent=no",
            "-p",
            "2222",
            "-l",
            "user",
            "--",
            "example.com",
            "scp -t /tmp/out",
        ])
        self.assertEqual(payload["host"], "example.com")
        self.assertEqual(payload["port"], 2222)
        self.assertEqual(payload["remote_args"], ["scp -t /tmp/out"])


if __name__ == "__main__":
    unittest.main()
