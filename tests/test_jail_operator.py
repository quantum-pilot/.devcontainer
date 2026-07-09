import importlib.machinery
import importlib.util
import tempfile
from pathlib import Path
import unittest


path = Path(__file__).resolve().parents[1] / "host/jail-operator"
loader = importlib.machinery.SourceFileLoader("jail_operator", str(path))
spec = importlib.util.spec_from_loader("jail_operator", loader)
jail_operator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jail_operator)


class SshLeaseCleanupTests(unittest.TestCase):
    def test_clear_ssh_leases_removes_json_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            old_dir = jail_operator.LEASE_DIR
            jail_operator.LEASE_DIR = Path(tmp)
            try:
                (jail_operator.LEASE_DIR / "lease.json").write_text("{}\n", encoding="utf-8")
                self.assertEqual(jail_operator.clear_ssh_leases(), 1)
                self.assertFalse((jail_operator.LEASE_DIR / "lease.json").exists())
            finally:
                jail_operator.LEASE_DIR = old_dir


if __name__ == "__main__":
    unittest.main()
