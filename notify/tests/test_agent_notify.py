"""python3 -m unittest discover -s notify/tests  (from the repo root)"""

import io
import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

TMP = tempfile.mkdtemp(prefix="agent-notify-test-")
os.environ["XDG_STATE_HOME"] = os.path.join(TMP, "state")
os.environ["AGENT_NOTIFY_CONFIG"] = os.path.join(TMP, "notify.env")
os.environ["AGENT_NOTIFY_WAIT_SECONDS"] = "0.3"
os.environ["CODEX_HOME"] = os.path.join(TMP, "codex")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from agent_notify import channels, cli, notifier  # noqa: E402
from agent_notify.agents import GenericAgent, get_agent  # noqa: E402
from agent_notify.alert import BODY_MAX, Alert  # noqa: E402
from agent_notify.channels import Profile  # noqa: E402
from agent_notify.channels.discord import Discord  # noqa: E402
from agent_notify.channels.ntfy import Ntfy  # noqa: E402
from agent_notify.config import LOG_PATH, Config  # noqa: E402
from agent_notify.switches import Switches  # noqa: E402

WEBHOOK = "https://discord.com/api/webhooks/123456/abc_DEF-ghi"


class Mock(BaseHTTPRequestHandler):
    seen = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Mock.seen.append({"path": self.path, "auth": self.headers.get("Authorization"), "body": body})
        if body.get("topic") == "slow":
            time.sleep(3)
        self.send_response(500 if body.get("topic") == "broken" else 200)
        self.end_headers()

    def log_message(self, *args):
        pass


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Mock)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        Mock.seen.clear()
        if LOG_PATH.exists():
            LOG_PATH.unlink()

    def config(self, **values):
        return Config(values, Path(os.environ["AGENT_NOTIFY_CONFIG"]))


class ConfigTest(Base):
    def test_read_as_text_never_run(self):
        path = Path(TMP) / "evil.env"
        path.write_text("NTFY_URL=$(touch pwned)\n# c\nDISCORD_WEBHOOK_URL='x'\n")
        config = Config.load(path)
        self.assertEqual(config.get("NTFY_URL"), "$(touch pwned)")
        self.assertEqual(config.get("DISCORD_WEBHOOK_URL"), "x")
        self.assertFalse(Path("pwned").exists())

    def test_saved_private(self):
        config = self.config(NTFY_URL=f"{self.base}/t")
        config.save()
        self.assertEqual(stat.S_IMODE(os.stat(config.path).st_mode), 0o600)
        self.assertEqual(Config.load(config.path).get("NTFY_URL"), f"{self.base}/t")

    def test_channel_states(self):
        self.assertEqual(Discord.state(self.config()), "off")
        self.assertEqual(Discord.state(self.config(DISCORD_WEBHOOK_URL=WEBHOOK)), "on")
        self.assertEqual(Discord.state(self.config(DISCORD_WEBHOOK_URL="https://evil.example/x")), "invalid")
        self.assertEqual(Ntfy.state(self.config(NTFY_URL=f"{self.base}/topic")), "on")
        self.assertEqual(Ntfy.state(self.config(NTFY_URL=f"{self.base}/t", NTFY_TOKEN='a"b')), "invalid")


class ProfileTest(Base):
    def test_each_agent_has_its_own_sender(self):
        config = self.config()
        claude, codex = get_agent("claude").profile(config), get_agent("codex").profile(config)
        self.assertEqual(claude.name, "Claude Code")
        self.assertEqual(codex.name, "Codex")
        self.assertNotEqual(claude.avatar, codex.avatar)
        self.assertTrue(claude.avatar.startswith("https://"))

    def test_config_overrides_a_profile(self):
        sender = get_agent("codex").profile(self.config(CODEX_NAME="Codex @ work", CODEX_AVATAR=""))
        self.assertEqual(sender, Profile("Codex @ work", ""))

    def test_unknown_agent_still_sends_under_its_key(self):
        agent = get_agent("gemini")
        self.assertIsInstance(agent, GenericAgent)
        self.assertEqual(agent.profile(self.config()).name, "gemini")


class ChannelTest(Base):
    alert = Alert("claude", "done", "Done · Fix login", "Fixed it @everyone", "app · main · 2m 1s")
    sender = Profile("Claude Code", "https://example.com/a.png")

    def test_discord_sends_as_the_agent(self):
        req = Discord(self.config(DISCORD_WEBHOOK_URL=WEBHOOK)).request(self.alert, self.sender)
        self.assertEqual(req.url, WEBHOOK)
        self.assertEqual(req.body["username"], "Claude Code")
        self.assertEqual(req.body["avatar_url"], "https://example.com/a.png")
        self.assertEqual(req.body["allowed_mentions"], {"parse": []})
        self.assertEqual(req.body["embeds"][0]["footer"]["text"], "app · main · 2m 1s")

    def test_ntfy_names_the_agent_and_its_icon(self):
        config = self.config(NTFY_URL=f"{self.base}/sub/topic", NTFY_TOKEN="tk_1")
        req = Ntfy(config).request(self.alert, self.sender)
        self.assertEqual(req.url, f"{self.base}/sub")
        self.assertEqual(req.body["topic"], "topic")
        self.assertEqual(req.body["title"], "Claude Code · Done · Fix login")
        self.assertEqual(req.body["icon"], "https://example.com/a.png")
        self.assertEqual(req.headers, {"Authorization": "Bearer tk_1"})

    def test_body_is_cut(self):
        self.assertEqual(len(Alert("x", "done", "t", "a" * 5000).body), BODY_MAX)

    def test_delivers(self):
        sent = notifier.Notifier(self.config(NTFY_URL=f"{self.base}/ok")).deliver(get_agent("codex"), self.alert)
        self.assertEqual(sent, {"ntfy": True})
        self.assertEqual(Mock.seen[0]["body"]["title"], "Codex · Done · Fix login")

    def test_failures_return_false_and_log_no_url(self):
        with mock.patch.object(channels, "TIMEOUT_S", 1):
            for target in (f"{self.base}/broken", f"{self.base}/slow", "http://127.0.0.1:1/refused",
                           "http://no-such-host.invalid/x"):
                n = notifier.Notifier(self.config(NTFY_URL=target, NTFY_TOKEN="secret_token"))
                self.assertEqual(n.deliver(get_agent("claude"), self.alert), {"ntfy": False}, target)
        text = LOG_PATH.read_text()
        self.assertIn("http 500", text)
        self.assertNotIn("127.0.0.1", text)
        self.assertNotIn("secret_token", text)

    def test_nothing_set_sends_nothing(self):
        self.assertEqual(notifier.Notifier(self.config()).deliver(get_agent("claude"), self.alert), {})


class SwitchTest(Base):
    def test_toggle(self):
        s = Switches("codex")
        self.assertFalse(s.is_on("t-toggle"))
        self.assertTrue(s.toggle("t-toggle"))
        self.assertTrue((s.dir / "t-toggle").exists())
        self.assertFalse(s.toggle("t-toggle"))

    def test_session_ids_are_names_not_paths(self):
        with self.assertRaises(ValueError):
            Switches("codex").set("../../x", True)
        self.assertFalse(Switches("codex").is_on("../x"))


class HookTest(Base):
    def run_hook(self, key, stdin):
        with mock.patch.object(sys, "stdin", io.StringIO(stdin)), \
             mock.patch.object(notifier, "detach") as detach, \
             mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            code = cli.main(["hook", key])
        return code, detach, out.getvalue()

    def test_off_garbage_and_unknown_are_silent(self):
        for key, stdin in (("codex", json.dumps({"session_id": "t-off"})), ("codex", "not json"),
                           ("codex", "[1]"), ("nobody", "{}"), ("codex", "")):
            code, detach, out = self.run_hook(key, stdin)
            self.assertEqual((code, out), (0, ""))
            detach.assert_not_called()

    def test_on_hands_the_event_to_a_detached_job(self):
        Switches("codex").set("t-on", True)
        code, detach, out = self.run_hook("codex", json.dumps({"session_id": "t-on", "hook_event_name": "Stop"}))
        self.assertEqual((code, out), (0, ""))
        self.assertEqual(detach.call_args[0][0]["hook"], "codex")


class CodexTest(Base):
    def setUp(self):
        super().setUp()
        self.rollout = Path(TMP) / "rollout.jsonl"
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S.123Z", time.gmtime(time.time() - 75))
        self.rollout.write_text(json.dumps({"timestamp": stamp, "type": "event_msg", "payload": {"type": "task_started"}}) + "\n")
        self.n = notifier.Notifier(self.config(NTFY_URL=f"{self.base}/codex"))
        Switches("codex").set("t-1", True)

    def event(self, name, **extra):
        return {"hook_event_name": name, "session_id": "t-1", "cwd": TMP, "transcript_path": str(self.rollout), **extra}

    def test_stop_sends_done_with_the_answer_and_time(self):
        get_agent("codex").on_hook(self.event("Stop", last_assistant_message="All green."), self.n)
        body = Mock.seen[0]["body"]
        self.assertEqual(body["title"], "Codex · Done")
        self.assertRegex(body["message"], r"All green\.\n.+ · 1m 1[45]s")

    def test_approval_left_waiting_is_sent(self):
        get_agent("codex").on_hook(self.event("PermissionRequest", tool_name="Bash", tool_input={"command": "git push"}), self.n)
        self.assertEqual(Mock.seen[0]["body"]["message"].split("\n")[0], "Bash: git push")

    def test_approval_answered_in_time_is_not(self):
        def answer():
            time.sleep(0.1)
            with self.rollout.open("a") as f:
                f.write("{}\n")
        threading.Thread(target=answer).start()
        get_agent("codex").on_hook(self.event("PermissionRequest", tool_name="Bash"), self.n)
        self.assertEqual(Mock.seen, [])


class DetachTest(Base):
    def test_a_job_outside_the_spool_is_refused(self):
        outside = Path(TMP) / "job.json"
        outside.write_text(json.dumps({"send": {}}))
        self.assertIsNone(notifier.take_job(str(outside)))

    def test_send_returns_at_once_and_delivers_later(self):
        self.config(NTFY_URL=f"{self.base}/later").save()
        started = time.time()
        self.assertEqual(cli.main(["send", "claude", "done", "Later", "body"]), 0)
        self.assertLess(time.time() - started, 0.5)
        for _ in range(50):
            if Mock.seen:
                break
            time.sleep(0.1)
        self.assertEqual(Mock.seen[0]["body"]["title"], "Claude Code · Later")
        self.assertEqual(list(notifier.SPOOL.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
