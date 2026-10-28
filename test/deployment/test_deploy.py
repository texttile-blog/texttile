"""Guard the single-database deployment constraints without calling Bunny."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

spec = importlib.util.spec_from_file_location("deploy", Path(__file__).resolve().parents[2] / "scripts/deploy-bunny.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeploymentGuardsTest(unittest.TestCase):
    def test_two_ready_pods_fail_even_when_bunny_reports_active(self):
        overview = {"status": "active", "regions": [{"pods": [
            {"name": "one", "status": "ready"}, {"name": "two", "status": "ready"},
        ]}]}
        with self.assertRaisesRegex(RuntimeError, "More than one ready pod"):
            deploy.ready_pod(overview)

    def test_rollout_is_not_finished_while_old_pod_is_deleting(self):
        overview = {"status": "active", "regions": [{"pods": [
            {"name": "old", "status": "deleting"}, {"name": "new", "status": "ready"},
        ]}]}
        self.assertIsNone(deploy.ready_pod(overview))

    def test_replacement_volume_requires_manual_recovery(self):
        volumes = {"items": [{"name": "data", "volumeInstances": [{"id": "empty-replacement"}]}]}
        with self.assertRaisesRegex(RuntimeError, "Provisioned volume was replaced"):
            deploy.volume_identity(volumes, {"volume": "data", "volume_instance_id": "original"})

    def test_second_volume_is_not_silently_selected(self):
        volumes = {"items": [{"name": "data", "volumeInstances": [{"id": "old"}, {"id": "new"}]}]}
        with self.assertRaisesRegex(RuntimeError, "exactly one persistent volume"):
            deploy.volume_identity(volumes, {"volume": "data", "region": "DE"})

    def test_volume_size_must_match_the_recorded_size(self):
        volumes = {"items": [{"name": "data", "size": 4, "volumeInstances": [{
            "id": "original", "region": "DE", "status": "attached",
            "attachedPods": ["one"], "size": 3,
        }]}]}
        with self.assertRaisesRegex(RuntimeError, "volume size"):
            deploy.volume_identity(volumes, {"volume": "data", "region": "DE",
                                            "volume_instance_id": "original", "volume_size_gb": 4})


class HttpReadinessTest(unittest.TestCase):
    def test_temporary_cdn_503_does_not_fail_a_healthy_rollout(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 200
        response.headers = {"Content-Type": "text/html"}
        response.read.return_value = b"Texttile"
        unavailable = urllib.error.HTTPError("https://demo.test/blog", 503, "Unavailable", {}, None)
        self.addCleanup(unavailable.close)
        with patch.object(deploy.urllib.request, "urlopen", side_effect=[unavailable, response, response]), patch.object(deploy.time, "sleep") as sleep:
            deploy.check_http({"url": "https://demo.test"})
            sleep.assert_called_once()

    def test_permanent_http_failure_is_not_retried(self):
        missing = urllib.error.HTTPError("https://demo.test/blog", 404, "Not found", {}, None)
        self.addCleanup(missing.close)
        with patch.object(deploy.urllib.request, "urlopen", side_effect=missing), patch.object(deploy.time, "sleep") as sleep:
            with self.assertRaises(urllib.error.HTTPError):
                deploy.check_http({"url": "https://demo.test"})
            sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
