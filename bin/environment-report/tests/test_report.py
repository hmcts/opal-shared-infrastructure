"""Offline behavioral tests. No real clusters or Teams endpoints are used."""

import copy
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

REPORT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPORT_DIR))
import report


NOW = datetime(2026, 11, 23, 9, tzinfo=timezone.utc)
SERVICE = "opal-fines-service"
IMAGE = "hmctsprod.azurecr.io/opal/fines-service:prod-example"


def resources(name=SERVICE, image=IMAGE, ready=True):
    deployment = {
        "kind": "Deployment",
        "metadata": {"name": name, "uid": name + "-deployment", "generation": 2,
                     "labels": {"app.kubernetes.io/instance": name}},
        "spec": {"replicas": 1, "template": {"spec": {
            "containers": [{"name": "app", "image": image}]}}},
        "status": {"observedGeneration": 2, "updatedReplicas": 1, "availableReplicas": int(ready)},
    }
    rs = {"kind": "ReplicaSet", "metadata": {
        "name": name + "-abc", "uid": name + "-rs", "ownerReferences": [
            {"uid": deployment["metadata"]["uid"], "controller": True}]}}
    pod = {
        "kind": "Pod", "metadata": {"name": name + "-abc-123", "uid": name + "-pod",
                                     "creationTimestamp": report.iso(NOW - timedelta(days=2, hours=3)),
                                     "ownerReferences": [{"uid": rs["metadata"]["uid"], "controller": True}]},
        "spec": {"containers": [{"name": "app", "image": image}]},
        "status": {"phase": "Running", "conditions": [{"type": "Ready", "status": "True" if ready else "False"}],
                   "containerStatuses": [{"name": "app", "ready": ready, "restartCount": 0,
                                          "state": {"running": {}}}]},
    }
    return [deployment, rs, pod]


def config(contexts=None):
    return {"namespace": "opal", "environments": [{"name": "Staging",
            "contexts": contexts or ["ss-stg-00-aks"], "expected_services": [SERVICE]}]}


class HealthTests(unittest.TestCase):
    def summary(self, items=None):
        return report.summarise_cluster(items if items is not None else resources(), [SERVICE], NOW)

    def test_healthy_service_reports_ready_image_and_pod_age(self):
        summary = self.summary()
        row = summary["rows"][0]
        self.assertEqual(row["health"], "Healthy")
        self.assertEqual((row["ready"], row["desired"]), (1, 1))
        self.assertEqual(row["running_images"], ["app=" + IMAGE])
        self.assertEqual(row["pod_age"], "2d 3h")

    def test_running_but_unready_is_not_healthy(self):
        summary = self.summary(resources(ready=False))
        row = summary["rows"][0]
        self.assertEqual(row["health"], "Attention")
        self.assertEqual(row["ready"], 0)

    def test_init_failure_and_crashloop_reasons_are_visible(self):
        items = resources(ready=False)
        items[-1]["status"]["containerStatuses"][0]["state"] = {"waiting": {"reason": "CrashLoopBackOff"}}
        items[-1]["status"]["initContainerStatuses"] = [
            {"name": "migration", "restartCount": 2, "state": {"terminated": {"exitCode": 1, "reason": "Error"}}}]
        row = self.summary(items)["rows"][0]
        self.assertIn("CrashLoopBackOff", " ".join(row["issues"]))
        self.assertIn("Error", " ".join(row["issues"]))

    def test_new_rollout_with_old_ready_replicas_is_not_healthy(self):
        items = resources()
        items[0]["spec"]["template"]["spec"]["containers"][0]["image"] = IMAGE + "-new"
        items[0]["status"]["updatedReplicas"] = 0
        row = self.summary(items)["rows"][0]
        self.assertEqual(row["ready"], 1)
        self.assertEqual(row["health"], "Attention")
        self.assertIn("Deployment rollout incomplete", row["issues"])

    def test_old_and_new_replica_images_are_both_reported(self):
        items = resources()
        new_pod = copy.deepcopy(items[-1])
        new_pod["metadata"].update(uid="new-pod", name="new-pod", creationTimestamp=report.iso(NOW - timedelta(minutes=5)))
        new_pod["spec"]["containers"][0]["image"] = IMAGE + "-new"
        items.append(new_pod)
        row = self.summary(items)["rows"][0]
        self.assertEqual(len(row["running_images"]), 2)
        self.assertEqual(row["pod_age"], "5m–2d 3h")
        self.assertEqual(row["health"], "Attention")

    def test_injected_sidecar_does_not_look_like_a_version_mismatch(self):
        items = resources()
        items[-1]["spec"]["containers"].append({"name": "proxy", "image": "proxy:v1"})
        items[-1]["status"]["containerStatuses"].append({"name": "proxy", "ready": True, "restartCount": 0})
        row = self.summary(items)["rows"][0]
        self.assertEqual(row["health"], "Healthy")
        self.assertIn("proxy=proxy:v1", row["running_images"])

    def test_missing_expected_service_is_reported_even_with_no_pods(self):
        summary = self.summary([])
        self.assertEqual(summary["rows"][0]["health"], "Missing")
        self.assertIsNone(summary["rows"][0]["desired"])

    def test_job_pod_with_same_name_prefix_does_not_count_as_service_replica(self):
        items = resources()
        job_pod = copy.deepcopy(items[-1])
        job_pod["metadata"].update(uid="job-pod", ownerReferences=[{"uid": "job", "controller": True}])
        job_pod["status"]["containerStatuses"][0]["restartCount"] = 100
        items.append(job_pod)
        row = self.summary(items)["rows"][0]
        self.assertEqual(row["ready"], 1)

    def test_terminating_pods_do_not_inflate_ready_counts(self):
        items = resources()
        terminating = copy.deepcopy(items[-1])
        terminating["metadata"].update(uid="old-pod", deletionTimestamp=report.iso(NOW))
        terminating["status"]["containerStatuses"][0]["restartCount"] = 10
        items.append(terminating)
        row = self.summary(items)["rows"][0]
        self.assertEqual(row["ready"], 1)

    def test_scaled_to_zero_is_explicit(self):
        items = resources()[:2]
        items[0]["spec"]["replicas"] = 0
        items[0]["status"].update(updatedReplicas=0, availableReplicas=0)
        row = self.summary(items)["rows"][0]
        self.assertEqual(row["health"], "Scaled to zero")

    def test_stale_controller_generation_is_highlighted(self):
        items = resources()
        items[0]["status"]["observedGeneration"] = 1
        self.assertEqual(self.summary(items)["rows"][0]["health"], "Attention")

    def test_statefulset_direct_owner_and_daemonset_replicas(self):
        for kind in ("StatefulSet", "DaemonSet"):
            with self.subTest(kind=kind):
                items = resources()
                items[0]["kind"] = kind
                items[-1]["metadata"]["ownerReferences"][0]["uid"] = items[0]["metadata"]["uid"]
                items[0]["status"].update(desiredNumberScheduled=1, updatedNumberScheduled=1,
                                          currentRevision="v1", updateRevision="v1")
                summary = self.summary([items[0], items[-1]])
                self.assertEqual(summary["rows"][0]["health"], "Healthy")

    def test_helm_release_suffix_maps_to_expected_service(self):
        items = resources()
        items[0]["metadata"]["name"] = SERVICE + "-java"
        summary = self.summary(items)
        self.assertEqual(len(summary["rows"]), 1)
        self.assertEqual(summary["rows"][0]["service"], SERVICE)

    def test_daemonset_old_ready_pods_do_not_hide_an_incomplete_rollout(self):
        items = resources()
        items[0]["kind"] = "DaemonSet"
        items[0]["status"].update(desiredNumberScheduled=1, updatedNumberScheduled=0)
        items[-1]["metadata"]["ownerReferences"][0]["uid"] = items[0]["metadata"]["uid"]
        row = self.summary([items[0], items[-1]])["rows"][0]
        self.assertIn("DaemonSet rollout incomplete", row["issues"])


class CoverageTests(unittest.TestCase):
    def test_excluded_services_are_not_discovered(self):
        excluded = ["opal-frontend-test", "opal-legacy-db-stub"]
        items = resources() + resources(name=excluded[0]) + resources(name=excluded[1])
        summary = report.summarise_cluster(items, [SERVICE] + excluded, NOW, excluded)
        self.assertEqual([row["service"] for row in summary["rows"]], [SERVICE])

    def test_excluded_service_with_a_custom_workload_name_uses_release_label(self):
        items = resources(name="custom-frontend-test")
        items[0]["metadata"]["labels"]["app.kubernetes.io/instance"] = "opal-frontend-test"
        summary = report.summarise_cluster(items, [SERVICE], NOW, ["opal-frontend-test"])
        self.assertEqual(len(summary["rows"]), 1)
        self.assertEqual(summary["rows"][0]["service"], SERVICE)
        self.assertEqual(summary["rows"][0]["health"], "Missing")

    def test_unavailable_optional_cluster_is_silent(self):
        conf = config(["ss-stg-00-aks", "ss-stg-01-aks"])
        conf["environments"][0]["optional_contexts"] = ["ss-stg-00-aks"]

        def collector(context, namespace):
            if "00" in context:
                raise report.ReportError("Unavailable")
            return resources()

        result = report.generate_report(conf, NOW, collector)
        summary = report.summarise_environment(result["environments"][0])
        self.assertEqual(summary["health"], "Healthy")
        self.assertEqual(summary["rows"][0]["health"], "Healthy")
        self.assertEqual(summary["warnings"], [])
        self.assertNotIn("Unavailable", report.render_markdown(result))
        self.assertTrue(result["environments"][0]["clusters"][0]["error"])

    def test_optional_cluster_is_fully_checked_when_it_becomes_available(self):
        conf = config(["ss-stg-00-aks", "ss-stg-01-aks"])
        conf["environments"][0]["optional_contexts"] = ["ss-stg-00-aks"]
        for ready in (True, False):
            with self.subTest(ready=ready):
                result = report.generate_report(conf, NOW,
                                                   lambda ctx, _: resources(ready=ready if "00" in ctx else True))
                row = report.summarise_environment(result["environments"][0])["rows"][0]
                self.assertEqual(row["replicas"], "2/2" if ready else "1/2")
                self.assertEqual(row["health"], "Healthy" if ready else "Attention")

    def test_required_cluster_failure_is_not_masked_by_optional_cluster_success(self):
        conf = config(["ss-stg-00-aks", "ss-stg-01-aks"])
        conf["environments"][0]["optional_contexts"] = ["ss-stg-00-aks"]

        def collector(context, namespace):
            if "01" in context:
                raise report.ReportError("Unavailable")
            return resources()

        result = report.generate_report(conf, NOW, collector)
        self.assertEqual(report.summarise_environment(result["environments"][0])["health"], "Incomplete")

    def test_no_available_clusters_does_not_report_healthy_even_when_all_optional(self):
        conf = config()
        conf["environments"][0]["optional_contexts"] = conf["environments"][0]["contexts"]
        result = report.generate_report(conf, NOW, Mock(side_effect=report.ReportError("No access")))
        self.assertEqual(report.summarise_environment(result["environments"][0])["health"], "Check failed")


    def test_failed_cluster_does_not_hide_other_cluster(self):
        def collector(context, namespace):
            if context == "unavailable":
                raise report.ReportError("Authentication failed")
            return resources()

        result = report.generate_report(config(["working", "unavailable"]), NOW, collector)
        self.assertIn("Incomplete", report.environment_health(result["environments"][0]))
        self.assertEqual(result["environments"][0]["clusters"][0]["rows"][0]["health"], "Healthy")

    def test_all_cluster_failures_never_show_healthy(self):
        collector = Mock(side_effect=report.ReportError("No access"))
        result = report.generate_report(config(), NOW, collector)
        self.assertEqual(report.environment_health(result["environments"][0]), "Check failed")


class RenderingTests(unittest.TestCase):
    def sample(self):
        return report.generate_report(config(), NOW, lambda *_: resources())

    def test_preview_has_one_compact_environment_table(self):
        markdown = report.render_markdown(self.sample())
        self.assertIn("## Staging — Healthy", markdown)
        self.assertIn("| Service | Status | Ready | Age | Image |", markdown)
        self.assertIn("| fines | Healthy | 1/1 |", markdown)
        self.assertNotIn("### ss-stg-00-aks", markdown)
        self.assertNotIn("baseline", markdown)
        self.assertNotIn("Restarts:", markdown)
        self.assertIn("fines-service:prod-example", markdown)

    def test_teams_uses_a_separate_card_for_each_environment_with_alerts(self):
        result = self.sample()
        template = result["environments"][0]
        result["environments"] = [{**copy.deepcopy(template), "name": name}
                                  for name in ("Staging", "Demo", "ITHC", "Test")]
        cards = report.render_cards(result)
        self.assertEqual(len(cards), 4)
        for card, name in zip(cards, ("Staging", "Demo", "ITHC", "Test")):
            self.assertEqual(card["body"][1]["columns"][0]["items"][0]["text"], name)
            self.assertEqual(card["actions"][0]["type"], "Action.ShowCard")
            self.assertEqual(card["actions"][-1], {
                "type": "Action.OpenUrl", "title": "Set up k9s",
                "url": "https://hmcts.atlassian.net/wiki/spaces/PO/pages/271490998/Connect+to+Azure+Kubernetes+pods"})
            self.assertLessEqual(report.payload_size(card), report.MAX_PAYLOAD_BYTES)

    def test_build_date_and_time_are_visible_separately_from_pod_age(self):
        image = "hmctsprod.azurecr.io/opal/fines-service:prod-b4ae8c7-20261120173110"
        result = report.generate_report(config(), NOW, lambda *_: resources(image=image, ready=False))
        card = report.render_cards(result)[0]
        visible = json.dumps(card["body"], ensure_ascii=False)
        self.assertIn("prod · b4ae8c7", visible)
        self.assertIn("Built 20 Nov 2026 17:31:10", visible)
        self.assertIn("~2d15h old", visible)
        self.assertIn("Pod age 2d3h", visible)
        self.assertIn(image, json.dumps(card["actions"]))
        self.assertIn("prod-b4ae8c7-20261120173110", report.render_markdown(result))
        self.assertIn("Attention", visible)

    def test_attention_and_failure_reasons_stay_visible_without_expanding(self):
        items = resources(ready=False)
        items[-1]["status"]["containerStatuses"][0]["state"] = {"waiting": {"reason": "CrashLoopBackOff"}}
        card = report.render_cards(report.generate_report(config(), NOW, lambda *_: items))[0]
        visible = json.dumps(card["body"])
        self.assertIn("Attention", visible)
        self.assertIn("CrashLoopBackOff", visible)
        self.assertIn("0/1", visible)

    def test_image_summary_keeps_multiple_app_versions_and_counts_supporting_images(self):
        row = {"name": "frontend", "image": "frontend:prod-8129632-20261120194505; "
               "frontend:staging-fafbcdf-20261123075338; postgresql:17.5.0; redis:8.2.1",
               "health": "Healthy", "replicas": "2/2", "age": "1h 5m", "notes": ""}
        summary = json.dumps(report.service_card_row(row, report.iso(NOW)), ensure_ascii=False)
        self.assertIn("prod · 8129632", summary)
        self.assertIn("staging · fafbcdf", summary)
        self.assertIn("Built 20 Nov 2026 19:45:05", summary)
        self.assertIn("Built 23 Nov 2026 07:53:38", summary)
        self.assertIn("+2 supporting images in details", summary)

    def test_image_age_warning_boundaries_do_not_change_service_health(self):
        for delta, colour, warning in (
                (timedelta(days=12, seconds=-1), "Default", None),
                (timedelta(days=12), "Warning", "nearing 14 days"),
                (timedelta(days=14, seconds=-1), "Warning", "nearing 14 days"),
                (timedelta(days=14), "Attention", "14+ days old")):
            with self.subTest(delta=delta):
                image = "fines-service:prod-b4ae8c7-" + (NOW - delta).strftime("%Y%m%d%H%M%S")
                detail = report.image_build_detail(image, report.iso(NOW))
                self.assertEqual(detail["color"], colour)
                if warning:
                    self.assertIn(warning, detail["text"])
                else:
                    self.assertNotIn("14", detail["text"].split(" old", 1)[-1])
                result = report.generate_report(config(), NOW, lambda *_: resources(image=image))
                card = report.render_cards(result)[0]
                self.assertEqual(report.summarise_environment(result["environments"][0])["rows"][0]["health"], "Healthy")
                visible = json.dumps(card["body"])
                if warning:
                    self.assertIn(warning, visible)
                    self.assertIn("Image age", visible)
                    self.assertIn("1 flagged", visible)
                else:
                    self.assertIn("All clear", visible)
                    self.assertNotIn("Built ", visible)

    def test_all_clear_is_one_brief_card_with_all_environments_and_no_service_detail(self):
        image = "fines-service:prod-b4ae8c7-20261122090000"
        result = report.generate_report(config(), NOW, lambda *_: resources(image=image))
        template = result["environments"][0]
        result["environments"] = [{**copy.deepcopy(template), "name": name}
                                  for name in ("Staging", "Demo", "ITHC", "Test")]
        cards = report.render_cards(result)
        self.assertEqual(len(cards), 1)
        visible = json.dumps(cards[0]["body"])
        self.assertIn("All clear", visible)
        self.assertIn("4 services checked", visible)
        for name in ("Staging", "Demo", "ITHC", "Test"):
            self.assertIn(name, visible)
        self.assertNotIn("Built ", visible)
        self.assertNotIn("b4ae8c7", visible)
        self.assertEqual([action["type"] for action in cards[0]["actions"]], ["Action.OpenUrl"])
        self.assertEqual(cards[0]["actions"][0]["title"], "Set up k9s")
        self.assertIn(image, report.render_markdown(result))

    def test_only_unhealthy_or_aging_services_appear_in_teams(self):
        conf = config()
        conf["environments"][0]["expected_services"] += ["opal-logging-service", "opal-user-service"]
        items = (resources(image="fines-service:prod-aaaaaaa-20261122090000", ready=False)
                 + resources(name="opal-logging-service", image="logging-service:prod-bbbbbbb-20261110090000")
                 + resources(name="opal-user-service", image="user-service:prod-ccccccc-20261122090000"))
        result = report.generate_report(conf, NOW, lambda *_: items)
        card = report.render_cards(result)[0]
        body = json.dumps(card["body"], ensure_ascii=False)
        self.assertIn("3 services checked · 2 flagged", body)
        self.assertIn("aaaaaaa", body)
        self.assertIn("bbbbbbb", body)
        self.assertNotIn("ccccccc", json.dumps(card))
        self.assertIn("ccccccc", report.render_markdown(result))
        self.assertIn("ccccccc", json.dumps(result))

    def test_clear_environments_are_summarised_beside_the_affected_environment(self):
        result = report.generate_report(config(), NOW,
                                       lambda *_: resources(image="fines-service:prod-aaaaaaa-20261122090000"))
        template = result["environments"][0]
        result["environments"] = [{**copy.deepcopy(template), "name": name}
                                  for name in ("Staging", "Demo", "ITHC", "Test")]
        result["environments"][-1]["clusters"][0]["rows"][0]["health"] = "Attention"
        cards = report.render_cards(result)
        self.assertEqual(len(cards), 1)
        self.assertEqual(cards[0]["body"][1]["columns"][0]["items"][0]["text"], "Test")
        self.assertIn("No alerts: Staging, Demo, ITHC", json.dumps(cards[0]["body"]))

    def test_old_supporting_image_does_not_flag_a_recent_application_image(self):
        result = report.generate_report(config(), NOW,
                                       lambda *_: resources(image="fines-service:prod-aaaaaaa-20261122090000"))
        result["environments"][0]["clusters"][0]["rows"][0]["running_images"].append(
            "redis=registry.example/redis:prod-bbbbbbb-20260101090000")
        self.assertIn("All clear", json.dumps(report.render_cards(result)))

    def test_unknown_build_age_prevents_a_false_all_clear(self):
        card = report.render_cards(self.sample())[0]
        visible = json.dumps(card["body"])
        self.assertIn("Image age warning", visible)
        self.assertIn("Build date unavailable", visible)
        self.assertNotIn("All clear", visible)

    def test_scaled_down_service_stays_visible(self):
        result = self.sample()
        row = result["environments"][0]["clusters"][0]["rows"][0]
        row.update(health="Scaled to zero", ready=0, desired=0, running_images=[], pod_age="No pods")
        visible = json.dumps(report.render_cards(result))
        self.assertIn("Scaled to zero", visible)
        self.assertIn("Check services", visible)
        self.assertNotIn("All clear", visible)


    def test_oldest_build_stays_visible_when_more_than_two_versions_are_running(self):
        versions = ["prod-aaaaaaa-20261123080000", "prod-bbbbbbb-20261122080000",
                    "prod-ccccccc-20261101080000"]
        result = report.generate_report(config(["00", "01", "02"]), NOW,
                    lambda context, _: resources(image="fines-service:" + versions[int(context)]))
        visible = json.dumps(report.render_cards(result)[0]["body"])
        self.assertIn("Built 01 Nov 2026 08:00:00", visible)
        self.assertIn("14+ days old", visible)
        self.assertIn("Built 22 Nov 2026 08:00:00", visible)
        self.assertIn("Built 23 Nov 2026 08:00:00", visible)

    def test_missing_or_invalid_tag_dates_never_use_pod_age_as_build_age(self):
        for image in ("fines-service:latest", "fines-service@sha256:abcdef",
                      "fines-service:prod-abcdef0-20260230090000", "fines-service:1.2.3"):
            with self.subTest(image=image):
                result = report.generate_report(config(), NOW, lambda *_: resources(image=image))
                visible = json.dumps(report.render_cards(result)[0]["body"])
                self.assertIn("Build date unavailable", visible)
                self.assertIn("Pod age 2d3h", visible)
                self.assertNotIn("~2d3h old", visible)

    def test_future_tag_is_explicit_instead_of_showing_zero_age(self):
        detail = report.image_build_detail("fines-service:prod-abcdef0-20261124090000", report.iso(NOW))
        self.assertIn("Built 24 Nov 2026 09:00:00", detail["text"])
        self.assertIn("future tag date", detail["text"])
        self.assertNotIn("~0m old", detail["text"])

    def test_build_tag_wall_time_is_preserved_in_summer_and_with_digest(self):
        detail = report.image_build_detail(
            "frontend:staging-abcdef0-20260701080000@sha256:abcdef", "2026-07-01T09:00:00Z")
        self.assertIn("Built 01 Jul 2026 08:00:00", detail["text"])
        self.assertIn("~1h0m old", detail["text"])

    def test_failed_cluster_card_keeps_warning_and_has_no_empty_details_button(self):
        result = report.generate_report(config(), NOW, Mock(side_effect=report.ReportError("No access")))
        card = report.render_cards(result)[0]
        self.assertIn("Check failed", json.dumps(card["body"]))
        self.assertIn("ss-stg-00-aks", json.dumps(card["body"]))
        self.assertNotIn("All clear", json.dumps(card))
        self.assertEqual([action["type"] for action in card["actions"]], ["Action.OpenUrl"])

    def test_two_clusters_share_a_row_without_hiding_different_images(self):
        conf = config(["ss-stg-00-aks", "ss-stg-01-aks"])
        result = report.generate_report(conf, NOW,
                                           lambda ctx, _: resources(image=IMAGE + ("-new" if "01" in ctx else "")))
        summary = report.summarise_environment(result["environments"][0])
        self.assertEqual(len(summary["rows"]), 1)
        self.assertEqual(summary["rows"][0]["replicas"], "2/2")
        self.assertIn("prod-example-new", summary["rows"][0]["image"])
        self.assertIn("fines-service:prod-example;", summary["rows"][0]["image"])
        self.assertEqual(report.render_markdown(result).count("| fines |"), 1)

    def test_failure_in_one_cluster_is_not_masked_by_healthy_replicas_elsewhere(self):
        conf = config(["ss-stg-00-aks", "ss-stg-01-aks"])
        result = report.generate_report(conf, NOW,
                                           lambda ctx, _: resources(ready="00" in ctx))
        row = report.summarise_environment(result["environments"][0])["rows"][0]
        self.assertEqual(row["health"], "Attention")
        self.assertEqual(row["replicas"], "1/2")
        self.assertIn("Running (01)", row["notes"])

    def test_missing_service_in_one_cluster_has_explicit_unknown_replica_count(self):
        result = report.generate_report(config(["ss-stg-00-aks", "ss-stg-01-aks"]), NOW,
                                           lambda ctx, _: resources() if "00" in ctx else [])
        row = report.summarise_environment(result["environments"][0])["rows"][0]
        self.assertEqual(row["health"], "Attention")
        self.assertEqual(row["replicas"], "1/1 + ?")
        self.assertIn("Missing in 01", row["notes"])

    def test_unreachable_cluster_makes_service_coverage_partial(self):
        def collector(context, namespace):
            if "01" in context:
                raise report.ReportError("No access")
            return resources()

        result = report.generate_report(config(["ss-stg-00-aks", "ss-stg-01-aks"]), NOW, collector)
        summary = report.summarise_environment(result["environments"][0])
        self.assertEqual(summary["health"], "Incomplete")
        self.assertEqual(summary["rows"][0]["health"], "Partial")
        self.assertIn("ss-stg-01-aks", summary["warnings"][0])

    def test_problem_notes_remove_duplicate_pod_names_and_rollout_symptoms(self):
        result = self.sample()
        row = result["environments"][0]["clusters"][0]["rows"][0]
        row["issues"] = ["opal-fines-service-old: PodInitializing", "opal-fines-service-new: PodInitializing",
                         "Only 0/1 replicas ready", "Deployment rollout incomplete",
                         "Pod images differ from target; rollout may be in progress"]
        self.assertEqual(report.summarise_environment(result["environments"][0])["rows"][0]["notes"], "PodInitializing")

    def test_timezone_is_correct_across_bst(self):
        self.assertEqual(report.local_time("2026-07-01T08:00:00Z"), "01 Jul 2026 09:00 BST")
        self.assertEqual(report.local_time("2026-11-23T09:00:00Z"), "23 Nov 2026 09:00 GMT")

    def test_large_report_splits_below_teams_limit_with_environment_on_every_card(self):
        result = self.sample()
        cluster = result["environments"][0]["clusters"][0]
        template = cluster["rows"][0]
        cluster["rows"] = []
        for index in range(100):
            row = copy.deepcopy(template)
            row["name"] = f"opal-service-{index}"
            row["service"] = f"opal-service-{index}"
            row["issues"] = ["⚠" * 200]
            cluster["rows"].append(row)
        cards = report.render_cards(result)
        self.assertGreater(len(cards), 1)
        for card in cards:
            self.assertLessEqual(report.payload_size(card), report.MAX_PAYLOAD_BYTES)
            body = json.dumps(card, ensure_ascii=False)
            self.assertIn("Staging", body)
        # Check the actual transmitted bytes, including non-ASCII text, using a mocked endpoint.
        response = Mock(status=202)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=None)
        with patch.object(report, "urlopen", return_value=response) as post:
            report.send_cards(cards, "https://example.invalid/webhook")
        for call in post.call_args_list:
            self.assertLessEqual(len(call.args[0].data), report.MAX_PAYLOAD_BYTES)
        text = " ".join(json.dumps(card) for card in cards)
        for index in range(100):
            self.assertIn(f"service-{index}", text)

    def test_single_huge_row_is_abridged_only_in_teams(self):
        result = self.sample()
        result["environments"][0]["clusters"][0]["rows"][0]["issues"] = ["x" * 50000]
        cards = report.render_cards(result)
        self.assertLessEqual(report.payload_size(cards[0]), report.MAX_PAYLOAD_BYTES)
        self.assertIn("Additional detail", json.dumps(cards))
        self.assertIn("x" * 50000, report.render_markdown(result))


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.conf = self.root / "config.json"
        self.conf.write_text(json.dumps(config()))
        self.out = self.root / "output"
        self.args = ["--config", str(self.conf), "--output-dir", str(self.out)]

    def test_defaults_write_to_repository_when_run_from_another_directory(self):
        checkout = self.root / "checkout"
        elsewhere = self.root / "another-directory"
        elsewhere.mkdir()
        previous_directory = Path.cwd()
        try:
            os.chdir(elsewhere)
            with patch.object(report, "ROOT", checkout), \
                    patch.object(report, "collect", return_value=resources()), \
                    patch.object(report, "send_cards") as send, patch("builtins.print") as output:
                self.assertEqual(report.main(["--config", str(self.conf)]), 0)
            send.assert_not_called()
            expected_report = (checkout / ".environment-report/output/report.md").resolve()
            self.assertTrue(expected_report.is_file())
            self.assertFalse((checkout / ".environment-report/state.json").exists())
            self.assertFalse((elsewhere / ".environment-report").exists())
            output.assert_any_call(f"Report saved to: {expected_report}", flush=True)
        finally:
            os.chdir(previous_directory)

    def test_explicit_relative_output_path_uses_current_directory(self):
        previous_directory = Path.cwd()
        try:
            os.chdir(self.root)
            with patch.object(report, "collect", return_value=resources()), \
                    patch.object(report, "send_cards") as send, patch("builtins.print"):
                result = report.main(["--config", str(self.conf), "--output-dir", "custom-output"])
            self.assertEqual(result, 0)
            send.assert_not_called()
            self.assertTrue((self.root / "custom-output/report.md").is_file())
        finally:
            os.chdir(previous_directory)

    def test_default_is_preview_even_with_webhook_present(self):
        with patch.dict(os.environ, {"OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK": "https://example.invalid/secret"}), \
                patch.object(report, "collect", return_value=resources()), \
                patch.object(report, "send_cards") as send, patch("builtins.print"):
            self.assertEqual(report.main(self.args), 0)
        send.assert_not_called()
        self.assertTrue((self.out / "report.md").is_file())
        self.assertIsInstance(json.loads((self.out / "teams-cards.json").read_text()), list)
        self.assertEqual(sorted(path.name for path in self.out.iterdir()),
                         ["report.json", "report.md", "teams-cards.json"])

    def test_missing_webhook_with_send_stops_before_cluster_queries(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(report, "generate_report") as generate, \
                patch.object(report.sys.stdin, "isatty", return_value=False), \
                patch.object(report.getpass, "getpass") as prompt, patch("builtins.print"):
            self.assertEqual(report.main(self.args + ["--send"]), 1)
        generate.assert_not_called()
        prompt.assert_not_called()

    def test_local_send_prompts_without_saving_or_printing_the_webhook(self):
        webhook = "https://example.invalid/local-secret"
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(report.sys.stdin, "isatty", return_value=True), \
                patch.object(report.getpass, "getpass", return_value=webhook) as prompt, \
                patch.object(report, "collect", return_value=resources()), \
                patch.object(report, "send_cards") as send, patch("builtins.print") as output:
            self.assertEqual(report.main(self.args + ["--send"]), 0)
        prompt.assert_called_once()
        self.assertEqual(send.call_args.args[1], webhook)
        self.assertNotIn(webhook, str(output.call_args_list))
        for path in self.out.iterdir():
            self.assertNotIn(webhook, path.read_text())

    def test_local_preview_never_prompts_or_sends(self):
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(report.sys.stdin, "isatty", return_value=True), \
                patch.object(report.getpass, "getpass") as prompt, \
                patch.object(report, "collect", return_value=resources()), \
                patch.object(report, "send_cards") as send, patch("builtins.print"):
            self.assertEqual(report.main(self.args), 0)
        prompt.assert_not_called()
        send.assert_not_called()


    def test_cancelled_or_unhidden_webhook_entry_stops_before_cluster_queries(self):
        for error in (EOFError(), KeyboardInterrupt(), report.getpass.GetPassWarning()):
            with self.subTest(error=type(error).__name__), patch.dict(os.environ, {}, clear=True), \
                    patch.object(report.sys.stdin, "isatty", return_value=True), \
                    patch.object(report.getpass, "getpass", side_effect=error), \
                    patch.object(report, "generate_report") as generate, \
                    patch.object(report, "send_cards") as send, patch("builtins.print"):
                self.assertEqual(report.main(self.args + ["--send"]), 1)
            generate.assert_not_called()
            send.assert_not_called()

    def test_optional_context_must_reference_a_configured_context(self):
        conf = config()
        conf["environments"][0]["optional_contexts"] = ["unknown-cluster"]
        self.conf.write_text(json.dumps(conf))
        with self.assertRaisesRegex(ValueError, "optional_contexts"):
            report.load_config(self.conf)

    def test_optional_cluster_failure_does_not_fail_cli_or_send_messages(self):
        conf = config(["ss-stg-00-aks", "ss-stg-01-aks"])
        conf["environments"][0]["optional_contexts"] = ["ss-stg-00-aks"]
        conf["excluded_services"] = ["opal-legacy-db-stub", "opal-frontend-test"]
        self.conf.write_text(json.dumps(conf))

        def collector(context, namespace):
            if "00" in context:
                raise report.ReportError("No access")
            return resources() + resources(name="opal-legacy-db-stub") + resources(name="opal-frontend-test")

        with patch.object(report, "collect", side_effect=collector), \
                patch.object(report, "send_cards") as send, patch("builtins.print"):
            self.assertEqual(report.main(self.args), 0)
        send.assert_not_called()
        data = json.loads((self.out / "report.json").read_text())
        self.assertEqual(len(data["environments"][0]["clusters"][1]["rows"]), 1)
        markdown = (self.out / "report.md").read_text()
        self.assertIn("## Staging — Healthy", markdown)
        self.assertNotIn("legacy-db-stub", markdown)
        self.assertNotIn("frontend-test", markdown)

    def test_delivery_failure_still_leaves_the_generated_report(self):
        with patch.dict(os.environ, {"OPAL_ENVIRONMENT_REPORT_TEAMS_WEBHOOK": "https://example.invalid/secret"}), \
                patch.object(report, "collect", return_value=resources()), \
                patch.object(report, "send_cards", side_effect=report.ReportError("Delivery failed")), patch("builtins.print"):
            self.assertEqual(report.main(self.args + ["--send"]), 1)
        self.assertTrue((self.out / "report.md").is_file())

    def test_old_comparison_file_is_ignored(self):
        old_file = self.root / ".environment-report/state.json"
        old_file.parent.mkdir()
        old_file.write_text("Old comparison data that is not valid JSON")
        with patch.object(report, "ROOT", self.root), \
                patch.object(report, "collect", return_value=resources()), \
                patch.object(report, "send_cards") as send, patch("builtins.print"):
            self.assertEqual(report.main(self.args), 0)
        send.assert_not_called()
        self.assertEqual(old_file.read_text(), "Old comparison data that is not valid JSON")
        data = json.loads((self.out / "report.json").read_text())
        row = data["environments"][0]["clusters"][0]["rows"][0]
        self.assertNotIn("changes", row)
        self.assertNotIn("restarts_observed", row)

    def test_collection_failure_still_writes_report_and_fails_job(self):
        collector = Mock(side_effect=report.ReportError("No access"))
        with patch.object(report, "collect", collector), patch("builtins.print"):
            self.assertEqual(report.main(self.args), 1)
        self.assertIn("Check failed", (self.out / "report.md").read_text())

    def test_kubectl_uses_explicit_context_and_suppresses_secret_errors(self):
        result = Mock(returncode=1, stderr="token=PRIVATE_SECRET", stdout="")
        with patch.object(report.subprocess, "run", return_value=result) as run:
            with self.assertRaises(report.ReportError) as raised:
                report.collect("ss-stg-00-aks", "opal")
        self.assertNotIn("PRIVATE_SECRET", str(raised.exception))
        args = run.call_args.args[0]
        self.assertEqual(args[args.index("--context") + 1], "ss-stg-00-aks")
        self.assertEqual(args[args.index("--namespace") + 1], "opal")
        self.assertNotIn("secrets", " ".join(args))

    def test_kubectl_timeout_is_a_reported_failure(self):
        with patch.object(report.subprocess, "run", side_effect=subprocess.TimeoutExpired("kubectl", 45)):
            with self.assertRaisesRegex(report.ReportError, "timed out"):
                report.collect("context", "opal")

    def test_http_error_does_not_expose_webhook(self):
        url = "https://example.invalid/PRIVATE_SECRET"
        with patch.object(report, "urlopen", side_effect=HTTPError(url, 403, url, {}, None)):
            with self.assertRaises(report.ReportError) as raised:
                report.send_cards([{}], url)
        self.assertNotIn("PRIVATE_SECRET", str(raised.exception))
        self.assertIn("403", str(raised.exception))

    def test_non_https_delivery_is_rejected_before_network_request(self):
        with patch.object(report, "urlopen") as request:
            with self.assertRaises(report.ReportError):
                report.send_cards([{}], "http://example.invalid/webhook")
        request.assert_not_called()

    def test_webhook_delivery_does_not_use_an_azure_token(self):
        response = Mock(status=202)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=None)
        with patch.object(report, "urlopen", return_value=response) as post, \
                patch.object(report.subprocess, "run") as azure:
            report.send_cards([{"type": "AdaptiveCard"}], "https://example.invalid/workflow?sig=PRIVATE")
        azure.assert_not_called()
        self.assertIsNone(post.call_args.args[0].get_header("Authorization"))

    def test_restricted_or_incomplete_url_error_does_not_expose_webhook(self):
        webhook = "https://example.invalid/workflow?sig=PRIVATE"
        with patch.object(report, "urlopen", side_effect=HTTPError(webhook, 401, "PRIVATE", {}, None)):
            with self.assertRaisesRegex(report.ReportError, "Anyone") as error:
                report.send_cards([{}], webhook)
        self.assertNotIn("PRIVATE", str(error.exception))


if __name__ == "__main__":
    unittest.main()
