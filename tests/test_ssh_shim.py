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


if __name__ == "__main__":
    unittest.main()
