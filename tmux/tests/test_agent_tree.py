"""Verify the picker stores status metadata, never agent titles or paths."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'agent_tree.py'
spec = importlib.util.spec_from_file_location('agent_tree', SCRIPT)
agent_tree = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent_tree)


class AgentTreeTest(unittest.TestCase):
    def run_refresh(self, scan_result):
        calls = []

        def fake_tmux(*args):
            calls.append(args)
            if args[0] == 'list-panes':
                # One window is linked into two sessions.
                return subprocess.CompletedProcess(args, 0, '%1\t@1\t$1\n%1\t@1\t$2\n%2\t@1\t$1\n%2\t@1\t$2\n', '')
            return subprocess.CompletedProcess(args, 0, '', '')

        with mock.patch.object(agent_tree, 'tmux', side_effect=fake_tmux), \
             mock.patch.object(agent_tree.subprocess, 'run', return_value=scan_result):
            self.assertEqual(agent_tree.main(), 0)
        return [c for c in calls if c[0] == 'set-option']

    def test_counts_linked_panes_and_omits_private_metadata(self):
        scan = subprocess.CompletedProcess([], 0,
            '%1\tsession:1.0\topencode\tworking\tPRIVATE_PATH\tPRIVATE_TITLE\n'
            '%2\tsession:1.1\tclaude\tblocked\tOTHER_PATH\tOTHER_TITLE\n', '')
        calls = self.run_refresh(scan)
        output = repr(calls)
        self.assertNotIn('PRIVATE_', output)
        self.assertNotIn('OTHER_', output)
        windows = [c for c in calls if '@am_tree_window' in c]
        self.assertEqual(len(windows), 1)
        self.assertIn('WAIT:1', windows[0][-1])
        self.assertIn('WORK:1', windows[0][-1])
        self.assertIn('[opencode]', windows[0][-1])
        self.assertIn('[claude]', windows[0][-1])
        sessions = [c for c in calls if '@am_tree_session' in c]
        self.assertEqual(len(sessions), 2)
        for call in sessions:
            self.assertIn('WAIT:1', call[-1])
            self.assertIn('WORK:1', call[-1])

    def test_scan_failure_does_not_leave_stale_labels(self):
        calls = self.run_refresh(subprocess.CompletedProcess([], 1, '', 'failure'))
        panes = [c for c in calls if '@am_tree_pane' in c]
        self.assertEqual([c[-1] for c in panes], ['', ''])
        self.assertTrue(all(c[-1] == '? scan unavailable' for c in calls
                            if '@am_tree_window' in c or '@am_tree_session' in c))


if __name__ == '__main__':
    unittest.main()
