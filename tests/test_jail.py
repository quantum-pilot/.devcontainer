import importlib.machinery
import importlib.util
from pathlib import Path
import unittest


path = Path(__file__).resolve().parents[1] / "scripts/jail"
loader = importlib.machinery.SourceFileLoader("jail", str(path))
spec = importlib.util.spec_from_loader("jail", loader)
jail = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jail)


class TmuxRestoreTests(unittest.TestCase):
    def test_balances_panes_without_manual_window_sizing(self):
        calls = []
        old_tmux = jail.tmux
        jail.tmux = lambda args, check=True: calls.append(args) or ""
        try:
            jail.restore_session({"windows": [{
                "index": 0,
                "name": "trading",
                "layout": "de85,304x62,0,0{...}",
                "panes": [{"index": index} for index in range(5)],
            }]}, "work")
        finally:
            jail.tmux = old_tmux

        self.assertNotIn("resize-window", [call[0] for call in calls])
        self.assertEqual(4, calls.count(["select-layout", "-t", "work:0", "tiled"]))
        self.assertIn(["set-option", "-w", "-t", "work:0", "window-size", "latest"], calls)


if __name__ == "__main__":
    unittest.main()
