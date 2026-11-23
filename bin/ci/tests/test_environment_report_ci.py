"""CI orchestration tests: all external calls are mocked."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import environment_report as report
import environment_report_ci as ci


class CISampleTests(unittest.TestCase):
    def test_sample_generates_all_environments_without_cluster_or_message_calls(self):
        config = report.load_config(report.HERE / "environment-report.json")
        now = datetime(2026, 11, 23, 9, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with patch.object(report, "collect") as collect, patch.object(report, "send_cards") as send, \
                    patch.object(ci.subprocess, "run") as external, patch("builtins.print"):
                ci.generate_sample(config, directory, now)
            collect.assert_not_called()
            send.assert_not_called()
            external.assert_not_called()
            markdown = (directory / "report.md").read_text()
            self.assertIn("# SAMPLE —", markdown)
            self.assertIn("Synthetic data; no live cluster checks", markdown)
            data = json.loads((directory / "report.json").read_text())
            self.assertTrue(data["sample_data"])
            self.assertEqual([env["name"] for env in data["environments"]], ["Staging", "Demo", "ITHC", "Test"])
            self.assertNotIn("legacy-db-stub", markdown)
            self.assertNotIn("frontend-test", markdown)
            self.assertIn("## Test — Attention", markdown)
            self.assertFalse((directory / "state.json").exists())
            cards = json.loads((directory / "teams-cards.json").read_text())
            self.assertEqual([card["body"][1]["columns"][0]["items"][0]["text"] for card in cards],
                             ["Demo", "Test"])
            self.assertIn("nearing 14 days", json.dumps(cards[0]))
            self.assertIn("PodInitializing", json.dumps(cards[1]))
            self.assertIn("No alerts: Staging, ITHC", json.dumps(cards[0]))
            for index, card in enumerate(cards, 1):
                self.assertEqual(json.loads((directory / f"teams-card-{index}.json").read_text()), card)
                self.assertIn("SAMPLE", card["body"][0]["text"])
                self.assertLessEqual(report.payload_size(card), report.MAX_PAYLOAD_BYTES)


class CIContextTests(unittest.TestCase):
    def config(self):
        return {"namespace": "opal", "environments": [{
            "name": "Staging", "azure_subscription": "DTS-SHAREDSERVICES-STG",
            "contexts": ["ss-stg-00-aks", "ss-stg-01-aks"],
            "optional_contexts": ["ss-stg-00-aks"], "expected_services": ["opal-fines-service"]}]}

    def test_context_setup_never_uses_the_default_personal_kubeconfig(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(ci.subprocess, "run") as external:
            with self.assertRaisesRegex(report.ReportError, "explicit KUBECONFIG"):
                ci.prepare_contexts(self.config())
        external.assert_not_called()

    def test_contexts_use_each_subscription_and_resource_group_and_unattended_auth(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "job-kubeconfig"
            with patch.dict(os.environ, {"KUBECONFIG": str(path)}), \
                    patch.object(ci.subprocess, "run", return_value=Mock(returncode=0)) as external, patch("builtins.print"):
                ci.prepare_contexts(self.config())
            calls = [call.args[0] for call in external.call_args_list]
            self.assertEqual(len(calls), 3)
            for command, number in zip(calls[:2], ("00", "01")):
                self.assertEqual(command[:3], ["az", "aks", "get-credentials"])
                self.assertEqual(command[command.index("--subscription") + 1], "DTS-SHAREDSERVICES-STG")
                self.assertEqual(command[command.index("--resource-group") + 1], f"ss-stg-{number}-rg")
                self.assertEqual(command[command.index("--file") + 1], str(path))
                self.assertNotIn("--admin", command)
            self.assertEqual(calls[-1], ["kubelogin", "convert-kubeconfig", "-l", "azurecli"])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_missing_subscription_is_rejected_before_overwriting_any_file(self):
        config = self.config()
        del config["environments"][0]["azure_subscription"]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "kubeconfig"
            path.write_text("original")
            with patch.dict(os.environ, {"KUBECONFIG": str(path)}), patch.object(ci.subprocess, "run") as external:
                with self.assertRaisesRegex(report.ReportError, "azure_subscription"):
                    ci.prepare_contexts(config)
            self.assertEqual(path.read_text(), "original")
            external.assert_not_called()

    def test_unavailable_context_does_not_prevent_checking_the_remaining_contexts(self):
        results = [Mock(returncode=1, stderr="PRIVATE_CREDENTIAL"), Mock(returncode=0), Mock(returncode=0)]
        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(os.environ, {"KUBECONFIG": str(Path(temporary) / "config")}), \
                    patch.object(ci.subprocess, "run", side_effect=results) as external, patch("builtins.print") as output:
                ci.prepare_contexts(self.config())
            self.assertEqual(external.call_count, 3)
            printed = " ".join(str(call) for call in output.call_args_list)
            self.assertIn("ss-stg-00-aks", printed)
            self.assertNotIn("PRIVATE_CREDENTIAL", printed)

    def test_context_timeout_still_attempts_remaining_contexts(self):
        with tempfile.TemporaryDirectory() as temporary:
            results = [subprocess.TimeoutExpired("az", 45), Mock(returncode=0), Mock(returncode=0)]
            with patch.dict(os.environ, {"KUBECONFIG": str(Path(temporary) / "config")}), \
                    patch.object(ci.subprocess, "run", side_effect=results) as external, patch("builtins.print"):
                ci.prepare_contexts(self.config())
            self.assertEqual(external.call_count, 3)


if __name__ == "__main__":
    unittest.main()
