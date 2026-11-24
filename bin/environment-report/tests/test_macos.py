"""Exercise local setup without changing launchd, reading clusters or posting."""

import contextlib
import io
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import macos


class MacScheduleTests(unittest.TestCase):
    webhook = "https://example.invalid/workflow?sig=PRIVATE_TEST_VALUE"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.local = self.root / "local"
        self.webhook_file = self.local / "teams-webhook"
        self.agent = self.root / "LaunchAgents/com.opal.environment-report.plist"
        self.output = io.StringIO()
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        for patcher in (patch.object(macos, "LOCAL", self.local),
                        patch.object(macos, "WEBHOOK", self.webhook_file),
                        patch.object(macos, "AGENT", self.agent),
                        patch.object(macos.sys, "platform", "darwin"),
                        patch.object(macos.shutil, "which", return_value="/test/tool"),
                        contextlib.redirect_stdout(self.output),
                        contextlib.redirect_stderr(self.output)):
            stack.enter_context(patcher)

    def save_webhook(self):
        with patch.object(macos.getpass, "getpass", return_value=self.webhook):
            self.assertEqual(macos.main(["configure"]), 0)

    def test_configuration_and_check_are_private_and_never_send(self):
        with patch.object(macos.subprocess, "run") as run:
            self.save_webhook()
            self.assertEqual(macos.main(["check"]), 0)
        run.assert_not_called()
        self.assertEqual(self.local.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.webhook_file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.webhook_file.read_text().strip(), self.webhook)
        self.assertNotIn(self.webhook, self.output.getvalue())

    def test_missing_or_publicly_readable_webhook_prevents_running(self):
        with patch.object(macos.subprocess, "run") as run:
            self.assertEqual(macos.main(["run"]), 1)
            self.save_webhook()
            self.webhook_file.chmod(0o644)
            self.assertEqual(macos.main(["run"]), 1)
        run.assert_not_called()
        self.assertNotIn(self.webhook, self.output.getvalue())

    def test_hidden_prompt_failure_or_cancellation_does_not_save_or_send(self):
        for error in (macos.getpass.GetPassWarning(), EOFError(), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__), \
                    patch.object(macos.getpass, "getpass", side_effect=error), \
                    patch.object(macos.subprocess, "run") as run:
                self.assertEqual(macos.main(["configure"]), 1)
                self.assertFalse(self.webhook_file.exists())
                run.assert_not_called()

    def test_incomplete_webhook_is_not_saved(self):
        with patch.object(macos.getpass, "getpass", return_value="https://example.invalid"), \
                patch.object(macos.subprocess, "run") as run:
            self.assertEqual(macos.main(["configure"]), 1)
        self.assertFalse(self.webhook_file.exists())
        run.assert_not_called()

    def test_install_registers_nine_am_without_starting_a_report(self):
        with patch.object(macos, "launchctl", side_effect=[Mock(returncode=113), Mock(returncode=0)]) as ctl, \
                patch.object(macos.subprocess, "run") as run:
            self.assertEqual(macos.main(["install"]), 0)
        run.assert_not_called()
        self.assertEqual([call.args[0] for call in ctl.call_args_list], ["print", "bootstrap"])
        config = plistlib.loads(self.agent.read_bytes())
        self.assertEqual(config["StartCalendarInterval"], {"Hour": 9, "Minute": 0})
        self.assertFalse(config["RunAtLoad"])
        self.assertNotIn("KeepAlive", config)
        self.assertEqual(config["ProgramArguments"][-2:], [str(macos.HERE / "macos.py"), "run"])
        self.assertEqual(config["StandardErrorPath"], str(self.local / "schedule.log"))
        self.assertEqual(config["StandardOutPath"], config["StandardErrorPath"])
        self.assertNotIn("OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK", config["EnvironmentVariables"])

    def test_install_failure_restores_the_previous_schedule_and_credentials(self):
        self.save_webhook()
        self.agent.parent.mkdir()
        previous = plistlib.dumps({"Label": macos.LABEL, "ProgramArguments": ["previous-script"]})
        self.agent.write_bytes(previous)
        results = [Mock(returncode=value) for value in (0, 0, 1, 0)]
        with patch.object(macos, "launchctl", side_effect=results) as ctl:
            self.assertEqual(macos.main(["install"]), 1)
        self.assertEqual(self.agent.read_bytes(), previous)
        self.assertEqual(self.webhook_file.read_text().strip(), self.webhook)
        self.assertEqual([call.args[0] for call in ctl.call_args_list],
                         ["print", "bootout", "bootstrap", "bootstrap"])

    def test_uninstall_preserves_webhook_and_log(self):
        self.save_webhook()
        log = self.local / "schedule.log"
        log.write_text("Previous run failed\n")
        self.agent.parent.mkdir()
        self.agent.write_bytes(plistlib.dumps(macos.job_config()))
        with patch.object(macos, "launchctl", return_value=Mock(returncode=0)) as ctl:
            self.assertEqual(macos.main(["uninstall"]), 0)
        self.assertEqual([call.args[0] for call in ctl.call_args_list], ["print", "bootout"])
        self.assertFalse(self.agent.exists())
        self.assertTrue(self.webhook_file.exists())
        self.assertEqual(log.read_text(), "Previous run failed\n")

    def test_only_explicit_run_sends_and_keeps_the_webhook_out_of_arguments(self):
        self.save_webhook()
        with patch.object(macos.subprocess, "run", return_value=Mock(returncode=1)) as run:
            self.assertEqual(macos.main(["run"]), 1)
        self.assertEqual(run.call_count, 1)
        command = run.call_args.args[0]
        self.assertEqual(command[-2:], [str(macos.HERE / "report.py"), "--send"])
        self.assertNotIn(self.webhook, str(command))
        self.assertEqual(run.call_args.kwargs["env"]["OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK"], self.webhook)
        self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertNotIn(self.webhook, self.output.getvalue())

    def test_no_command_cannot_send_a_report(self):
        with patch.object(macos.subprocess, "run") as run:
            with self.assertRaises(SystemExit):
                macos.main([])
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
