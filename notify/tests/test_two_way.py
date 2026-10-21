"""Two-way alerts, against a fake channel: python3 -m unittest discover -s notify/tests"""

import io
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

TMP = tempfile.mkdtemp(prefix="agent-notify-2way-")
os.environ.setdefault("XDG_STATE_HOME", os.path.join(TMP, "state"))
os.environ.setdefault("AGENT_NOTIFY_CONFIG", os.path.join(TMP, "notify.env"))
os.environ.setdefault("CODEX_HOME", os.path.join(TMP, "codex"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from agent_notify import bridge, cli, interactive as ia  # noqa: E402
from agent_notify.agents import get_agent  # noqa: E402
from agent_notify.channels import Inbound, Interactive  # noqa: E402
from agent_notify.channels.discord import Discord  # noqa: E402
from agent_notify.config import Config  # noqa: E402
from agent_notify.notifier import Notifier  # noqa: E402
from agent_notify.switches import Switches  # noqa: E402

OWNER = "111111111111111111"


class FakeChannel(Interactive):
    """Records what the bridge and ask do; answers what a test set up."""

    def __init__(self):
        self.asked, self.closed, self.acks, self.inbound = [], [], [], []
        self.reacted = {}  # message id -> Answer to give

    @classmethod
    def can_listen(cls, config):
        return True

    def post_alert(self, alert, sender):
        return True

    def ask(self, question, sender):
        message_id = str(1000 + len(self.asked))
        self.asked.append((message_id, question, sender))
        ia.add_pending(message_id, "c1", question)
        return "c1", message_id

    def poll_answer(self, channel_id, message_id, question):
        return self.reacted.pop(message_id, None)

    def start_cursor(self):
        return "0"

    def poll_messages(self, cursor):
        found, self.inbound = self.inbound, []
        return found, cursor

    def close(self, message_id, question, sender, outcome, answered):
        self.closed.append((message_id, outcome, answered))

    def ack(self, message, delivered):
        self.acks.append((message.id, delivered))


def clean():
    for folder in (ia.SENT, ia.PENDING, ia.ANSWERS, ia.INBOX, ia.CANCEL, Switches("claude").dir, Switches("codex").dir):
        if folder.exists():
            for path in sorted(folder.rglob("*"), reverse=True):
                path.unlink() if path.is_file() else path.rmdir()


class SwitchModes(unittest.TestCase):
    def setUp(self):
        clean()

    def test_an_empty_file_is_alerts_as_sidebars_write_it(self):
        s = Switches("codex")
        s.dir.mkdir(parents=True, exist_ok=True)
        (s.dir / "t1").touch()
        self.assertEqual(s.mode("t1"), "alerts")

    def test_away_keeps_the_pane(self):
        s = Switches("codex")
        s.set_mode("t1", "away", pane="%3")
        self.assertEqual(s.info("t1"), {"mode": "away", "pane": "%3"})
        self.assertEqual([k for k, _ in s.sessions("away")], ["t1"])
        s.set_mode("t1", "off")
        self.assertEqual(s.mode("t1"), "off")

    def test_cli_switch_prints_the_mode(self):
        with mock.patch.object(bridge, "ensure") as ensure, mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            cli.main(["switch", "claude", "s1", "away"])
        self.assertEqual(out.getvalue().strip(), "away")
        ensure.assert_called_once()


class Routing(unittest.TestCase):
    def setUp(self):
        clean()
        self.ch = FakeChannel()
        self.b = bridge.Bridge(Config({}))

    def test_a_reply_to_a_question_answers_it(self):
        q = ia.Question("claude", "s1", "choice", "Which?", options=["A", "B"])
        _, mid = self.ch.ask(q, None)
        self.b.route(self.ch, Inbound("m1", "2", reply_to=mid))
        self.assertEqual(ia.take_answer(mid).values, ["B"])
        self.assertEqual(self.ch.acks, [("m1", True)])

    def test_a_reply_to_an_alert_goes_to_that_session_if_away(self):
        ia.remember_sent("500", "claude", "s1")
        self.b.route(self.ch, Inbound("m1", "run the tests", reply_to="500"))
        self.assertEqual(self.ch.acks[-1], ("m1", False))  # s1 is not away
        Switches("claude").set_mode("s1", "away")
        self.b.route(self.ch, Inbound("m2", "run the tests", reply_to="500"))
        self.assertEqual(self.ch.acks[-1], ("m2", True))
        self.assertEqual(ia.take_inbox("claude", "s1"), ["run the tests"])

    def test_a_plain_message_goes_to_the_newest_away_session(self):
        Switches("claude").set_mode("old", "away")
        time.sleep(0.02)
        Switches("claude").set_mode("new", "away")
        self.b.route(self.ch, Inbound("m1", "hello"))
        self.assertEqual(ia.take_inbox("claude", "new"), ["hello"])
        self.assertEqual(ia.take_inbox("claude", "old"), [])

    def test_with_no_away_session_nothing_is_delivered(self):
        self.b.route(self.ch, Inbound("m1", "hello"))
        self.assertEqual(self.ch.acks, [("m1", False)])

    def test_codex_types_into_its_pane(self):
        Switches("codex").set_mode("t1", "away", pane="%7")
        ia.remember_sent("600", "codex", "t1")
        calls = []
        ran = mock.Mock(stdout="%1 %7\n", returncode=0)
        with mock.patch("subprocess.run", side_effect=lambda argv, **kw: calls.append(argv) or ran):
            self.b.route(self.ch, Inbound("m1", "line 1\nline 2", reply_to="600"))
        self.assertEqual(self.ch.acks, [("m1", True)])
        self.assertEqual([c[1] for c in calls], ["list-panes", "load-buffer", "paste-buffer", "send-keys"])

    def test_codex_with_its_pane_gone_says_so(self):
        Switches("codex").set_mode("t1", "away", pane="%7")
        with mock.patch("subprocess.run", return_value=mock.Mock(stdout="%1\n")):
            self.b.route(self.ch, Inbound("m1", "hi"))
        self.assertEqual(self.ch.acks, [("m1", False)])

    def test_text_answers(self):
        approve = ia.Question("codex", "t", "approve", "Run?")
        self.assertEqual(bridge.text_answer(approve, "ㅇㅇ").kind, "allow")
        self.assertEqual(bridge.text_answer(approve, "no, use npm ci").value, "no, use npm ci")
        choice = ia.Question("claude", "s", "choice", "?", options=["A", "B"])
        self.assertEqual(bridge.text_answer(choice, "something else").kind, "text")


class Asking(unittest.TestCase):
    def setUp(self):
        clean()
        self.ch = FakeChannel()
        self.patches = [mock.patch.object(bridge, "listening", return_value=self.ch),
                        mock.patch.object(bridge, "ensure")]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()

    def question(self):
        return ia.Question("claude", "s1", "choice", "Which?", options=["A", "B"])

    def later(self, fn):
        def run():
            for _ in range(50):
                if self.ch.asked:
                    break
                time.sleep(0.02)
            fn(self.ch.asked[0][0])
        threading.Thread(target=run).start()

    def test_answer_from_the_channel(self):
        self.later(lambda mid: ia.answer(mid, ia.Answer("choice", values=["A"])))
        got = bridge.ask(self.question(), 5)
        self.assertEqual(got.values, ["A"])
        self.assertTrue(self.ch.closed[0][2])
        self.assertEqual(list(ia.pending()), [])

    def test_answered_in_the_terminal(self):
        self.later(lambda mid: ia.cancel("tok"))
        self.assertIsNone(bridge.ask(self.question(), 5, token="tok"))
        self.assertEqual(self.ch.closed[0][1:], ("Answered in the terminal", False))

    def test_timeout(self):
        self.assertIsNone(bridge.ask(self.question(), 0.3))
        self.assertIn("back to the terminal", self.ch.closed[0][1])

    def test_a_long_wait_in_chunks_posts_once(self):
        with self.assertRaises(bridge.StillWaiting) as wait:
            bridge.ask(self.question(), 0.2, token="t", final=False)
        mid = wait.exception.message_id
        self.assertTrue(ia.is_pending(mid))
        self.assertEqual(self.ch.closed, [])
        ia.answer(mid, ia.Answer("choice", values=["B"]))
        self.assertEqual(bridge.ask(self.question(), 1, token="t", resume=mid).values, ["B"])
        self.assertEqual(len(self.ch.asked), 1)
        self.assertTrue(self.ch.closed[0][2])

    def test_cli_ask_prints_json(self):
        self.later(lambda mid: ia.answer(mid, ia.Answer("text", value="C")))
        stdin = json.dumps({"agent": "claude", "session": "s1", "kind": "choice", "title": "Which?",
                            "options": ["A", "B"], "timeout": 5, "token": "t", "extra": "ignored"})
        with mock.patch.object(sys, "stdin", io.StringIO(stdin)), mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            cli.main(["ask"])
        self.assertEqual(json.loads(out.getvalue()), {"kind": "text", "value": "C", "values": []})


class CodexApproval(unittest.TestCase):
    event = {"hook_event_name": "PermissionRequest", "session_id": "t1", "cwd": TMP,
             "tool_name": "Bash", "tool_input": {"command": "git push"}}

    def setUp(self):
        clean()

    def sync(self, answer, mode="away", can_listen=True):
        codex = get_agent("codex")
        with mock.patch("agent_notify.channels.listening", return_value=object() if can_listen else None), \
             mock.patch.object(bridge, "ask", return_value=answer) as ask:
            return codex.on_hook_sync(self.event, Notifier(Config({})), mode), ask

    def test_allow(self):
        reply, ask = self.sync(ia.Answer("allow"))
        self.assertEqual(reply.output["hookSpecificOutput"]["decision"], {"behavior": "allow"})
        self.assertEqual(ask.call_args[0][0].body, "Bash: git push")

    def test_deny_with_a_message(self):
        reply, _ = self.sync(ia.Answer("deny", value="use --force-with-lease"))
        self.assertEqual(reply.output["hookSpecificOutput"]["decision"],
                         {"behavior": "deny", "message": "use --force-with-lease"})

    def test_no_answer_falls_back_to_codex_prompt(self):
        reply, _ = self.sync(None)
        self.assertEqual((reply.output, reply.handled), (None, True))

    def test_alerts_mode_and_no_bot_do_not_ask(self):
        for kwargs in ({"mode": "alerts"}, {"can_listen": False}):
            reply, ask = self.sync(ia.Answer("allow"), **kwargs)
            self.assertEqual((reply.output, reply.handled), (None, False))
            ask.assert_not_called()

    def test_cli_hook_prints_the_decision(self):
        Switches("codex").set_mode("t1", "away")
        with mock.patch("agent_notify.channels.listening", return_value=object()), \
             mock.patch.object(bridge, "ask", return_value=ia.Answer("allow")), \
             mock.patch.object(sys, "stdin", io.StringIO(json.dumps(self.event))), \
             mock.patch("agent_notify.notifier.detach") as detach, \
             mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            self.assertEqual(cli.main(["hook", "codex"]), 0)
        self.assertEqual(json.loads(out.getvalue())["hookSpecificOutput"]["decision"]["behavior"], "allow")
        detach.assert_not_called()


class DiscordReading(unittest.TestCase):
    def channel(self):
        config = Config({"DISCORD_WEBHOOK_URL": "https://discord.com/api/webhooks/1/abc",
                         "DISCORD_BOT_TOKEN": "x" * 40, "DISCORD_OWNER_ID": OWNER})
        ch = Discord(config)
        ch.api = mock.Mock()
        ch._channel_id = "c1"
        return ch

    def test_only_the_owners_reactions_count(self):
        ch = self.channel()
        q = ia.Question("claude", "s", "choice", "?", options=["A", "B"])
        ch.api.reactors.side_effect = lambda c, m, e: {"1️⃣": ["999"], "2️⃣": [OWNER]}.get(e, [])
        self.assertEqual(ch.poll_answer("c1", "m", q).values, ["B"])
        ch.api.reactors.side_effect = lambda c, m, e: ["999", "bot"]
        self.assertIsNone(ch.poll_answer("c1", "m", q))

    def test_multi_select_waits_for_the_check_mark(self):
        ch = self.channel()
        q = ia.Question("claude", "s", "choice", "?", options=["A", "B", "C"], multi=True)
        picks = {"1️⃣": [OWNER], "3️⃣": [OWNER]}
        ch.api.reactors.side_effect = lambda c, m, e: picks.get(e, [])
        self.assertIsNone(ch.poll_answer("c1", "m", q))
        picks["✅"] = [OWNER]
        self.assertEqual(ch.poll_answer("c1", "m", q).values, ["A", "C"])

    def test_messages_from_others_bots_and_webhooks_are_ignored(self):
        ch = self.channel()
        ch.api.messages_after.return_value = [
            {"id": "1", "author": {"id": OWNER}, "content": "mine", "message_reference": {"message_id": "500"}},
            {"id": "2", "author": {"id": "999"}, "content": "someone else"},
            {"id": "3", "author": {"id": "b", "bot": True}, "content": "bot"},
            {"id": "4", "author": {"id": OWNER}, "webhook_id": "w", "content": "webhook"},
        ]
        got, cursor = ch.poll_messages("0")
        self.assertEqual([(m.id, m.text, m.reply_to) for m in got], [("1", "mine", "500")])
        self.assertEqual(cursor, "4")

    def test_needs_bot_and_owner_to_listen(self):
        self.assertFalse(Discord.can_listen(Config({"DISCORD_WEBHOOK_URL": "https://discord.com/api/webhooks/1/abc"})))
        self.assertTrue(Discord.can_listen(self.channel().config))


if __name__ == "__main__":
    unittest.main()
