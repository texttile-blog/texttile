#!/usr/bin/env python3
"""Update the existing Bunny app without replacing its persistent storage."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "bunny.json"
MAIL_SECRETS = ("MAIL_ADAPTER", "MAIL_FROM", "RESEND_API_KEY")


def api(method, path, body=None):
    """Use the authenticated CLI and keep API responses containing secrets private."""
    result = subprocess.run(
        ["bunny", "api", method, path],
        input=json.dumps(body) if body is not None else "",
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(f"Bunny API request failed: {method} {path}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate_app(app, config):
    """Refuse deployments when scaling or storage could split the SQLite database."""
    require(app["autoScaling"] == {"min": 1, "max": 1}, "Expected exactly one replica.")
    regions = app["regionSettings"]
    for key in ("allowedRegionIds", "requiredRegionIds"):
        require(regions[key] == [config["region"]], "Expected exactly one fixed region.")
    containers = app["containerTemplates"]
    require(len(containers) == 1, "Expected exactly one container.")
    container = containers[0]
    require(container["name"] == config["container"], "Unexpected container name.")
    require(
        container["volumeMounts"] == [{"name": config["volume"], "mountPath": "/data"}],
        "Expected the persistent data volume mounted at /data.",
    )
    require(
        app["volumes"] == [{"name": config["volume"], "size": config["volume_size_gb"]}],
        "Unexpected volume configuration.",
    )
    require(
        (container["imageNamespace"], container["imageName"]) == ("texttile-blog", "texttile"),
        "Unexpected application image.",
    )
    return container


def volume_identity(volumes, config):
    items = volumes["items"]
    require(len(items) == 1 and items[0]["name"] == config["volume"], "Unexpected volumes.")
    instances = items[0]["volumeInstances"]
    require(len(instances) == 1, "Expected exactly one persistent volume instance.")
    instance = instances[0]
    require(instance["id"] == config["volume_instance_id"], "Provisioned volume was replaced. Restore data before deploying.")
    require(instance["region"] == config["region"], "Volume is in the wrong region.")
    require(instance["status"] == "attached", "Persistent volume is not attached.")
    require(len(instance["attachedPods"]) == 1, "Volume must belong to exactly one pod.")
    require(items[0]["size"] == instance["size"] == config["volume_size_gb"],
            "Unexpected persistent volume size.")
    return instance["id"]


def ready_pod(overview):
    pods = [pod for region in overview["regions"] for pod in region["pods"]]
    ready = [pod for pod in pods if pod["status"] == "ready"]
    require(len(ready) <= 1, "More than one ready pod detected. Deployment stopped.")
    if overview["status"] == "active" and len(pods) == len(ready) == 1:
        return ready[0]["name"]
    return None


def check_http(config):
    # The CDN can briefly lag behind the pod's readiness after a volume handoff.
    for path in ("/blog", "/login"):
        request = urllib.request.Request(config["url"] + path, headers={"Cache-Control": "no-cache"})
        for attempt in range(1, 6):
            try:
                with urllib.request.urlopen(request, timeout=20) as response:
                    require(response.status == 200, f"HTTP check failed: {path}")
                    require("text/html" in response.headers.get("Content-Type", ""), f"Expected HTML: {path}")
                    require(b"Texttile" in response.read(), f"Unexpected page: {path}")
                break
            except urllib.error.HTTPError as error:
                if error.code not in (502, 503, 504) or attempt == 5:
                    raise
            except (urllib.error.URLError, TimeoutError):
                if attempt == 5:
                    raise
            print(f"Waiting for CDN readiness: {path}, attempt {attempt}/5.", flush=True)
            time.sleep(3)
    print(f"HTTP checks passed: {config['url']}", flush=True)


def deploy(config, check_only=False):
    base = "/mc/apps/" + config["app_id"]
    app = api("GET", base)
    container = validate_app(app, config)
    old_pod = ready_pod(api("GET", base + "/overview"))
    require(old_pod is not None, "App must be healthy before deploying. Inspect it in Bunny first.")
    old_volume = volume_identity(api("GET", base + "/volumes"), config)
    if check_only:
        check_http(config)
        print(f"One ready pod in {config['region']}, persistent volume {old_volume}.")
        return

    image = api("POST", "/mc/registries/digest", {
        "registryId": container["imageRegistryId"],
        "imageNamespace": "texttile-blog", "imageName": "texttile", "tag": config["image_tag"],
    })
    environment = {item["name"]: item["value"] for item in container["environmentVariables"]}
    environment.update(config["environment"])
    # Missing GitHub secrets preserve existing mail settings and the signing key.
    for name in MAIL_SECRETS:
        if os.environ.get(name):
            environment[name] = os.environ[name]
    require(bool(environment.get("SECRET_KEY_BASE")), "Missing SECRET_KEY_BASE on the Bunny app.")
    patch = {
        "imageTag": config["image_tag"], "imageDigest": image["digest"], "imagePullPolicy": "always",
        "environmentVariables": [{"name": key, "value": value} for key, value in sorted(environment.items())],
        # Keep the volume's group when dropping to nobody on Bunny.
        "entryPoint": {
            "command": "", "commandArray": ["sh"], "arguments": "",
            "argumentsArray": ["-c", (ROOT / "scripts/start-bunny.sh").read_text()],
            "workingDirectory": "/app",
        },
    }
    # Bunny derives legacy command/arguments strings from the canonical arrays.
    # Ignore those response-only representations when detecting real changes.
    current_entrypoint = {key: container["entryPoint"].get(key) for key in
                          ("commandArray", "argumentsArray", "workingDirectory")}
    desired_entrypoint = {key: patch["entryPoint"][key] for key in current_entrypoint}
    changed = (current_entrypoint != desired_entrypoint or any(
        container.get(key) != value for key, value in patch.items() if key != "entryPoint"
    ))
    if not changed:
        check_http(config)
        print(f"Already up to date: pod {old_pod}, unchanged volume {old_volume}.", flush=True)
        return
    api("PATCH", base + "/containers/" + container["id"], patch)
    print(f"Updating texttile:{config['image_tag']} ({image['digest']}).", flush=True)

    # Wait for a replacement pod, not the still-healthy old pod just after the API call.
    deadline = time.monotonic() + 900
    last_status = None
    while time.monotonic() < deadline:
        overview = api("GET", base + "/overview")
        if overview["status"] != last_status:
            last_status = overview["status"]
            print(f"Bunny status: {last_status}", flush=True)
        require(last_status not in ("suspended", "inactive"), "App stopped during deployment.")
        pod = ready_pod(overview)
        if pod and pod != old_pod:
            current = api("GET", base)
            live = validate_app(current, config)
            require(live["imageDigest"] == image["digest"], "Image digest changed unexpectedly.")
            require(volume_identity(api("GET", base + "/volumes"), config) == old_volume,
                    "Persistent volume identity changed. Inspect Bunny before any further deployment.")
            check_http(config)
            print(f"Deployment verified: pod {pod}, unchanged volume {old_volume}.", flush=True)
            return
        time.sleep(5)
    raise RuntimeError("Deployment did not finish within 15 minutes. Inspect Bunny before retrying.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check the running app without deploying")
    parser.add_argument("--image-tag", help="Deploy the immutable commit tag published by CI")
    args = parser.parse_args()
    if not args.check and not args.image_tag:
        parser.error("Use --image-tag with a published commit, or --check for a read-only check.")
    try:
        config = json.loads(CONFIG.read_text())
        if args.image_tag:
            config["image_tag"] = args.image_tag
        deploy(config, args.check)
    except (RuntimeError, OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
