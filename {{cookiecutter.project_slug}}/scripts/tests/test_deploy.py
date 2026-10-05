"""scripts/cd.sh end to end, against fake az/gh/curl executables. No Azure, no network.

Written as the list of ways a deploy can go wrong, before the code:

Before any change to Azure (no Key Vault write, no container app update)
  - the image tag or a deployment variable is missing or malformed, or the wrapper passes
    no secrets object (it is pinned at a commit that predates DEPLOYMENT_SECRETS_JSON);
  - the GitHub variables and secrets break the contract (a missing key, a rule, a secret
    the run never received);
  - the published image is missing or its digest is malformed;
  - an app is not in Single revision mode or can scale to zero (no health to gate on);
  - an app pulls from the registry without a managed identity (the pull would fail
    only after a broken revision exists);
  - the API's ingress is public, or it has no address for the web to forward to;
  - replace semantics would delete a hand-set key and ALLOW_PRUNE is not set;
  - main has moved on, or cannot be checked.
Secrets
  - a secret reaches disk or a command line;
  - any command cd.sh runs other than the renderer inherits the secrets object, which
    holds every secret the run inherits, or the legacy env-file secrets;
  - a pipeline name that is also a container key (AZURE_CLIENT_ID: the deploy's sign-in
    app, and the API's managed identity) reaches the container, or a GitHub value
    displaces one the deploy derives (BACKEND_ORIGIN, ENVIRONMENT);
  - a Key Vault value file outlives the run or is readable by others.
After a change (each must roll back, web before API, to the exact previous image and env)
  - a revision reports Unhealthy or Failed (fail fast: no waiting out the timeout);
  - a revision never becomes ready within the poll limit;
  - the site answers but its health says auth, AI, or the database is not ready;
  - the site does not answer at all;
  - one rollback fails (the other must still be attempted).
"""

import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "scripts" / "cd.sh"
SHA = "a" * 40
DIGEST = "sha256:" + "c" * 64
REGISTRY = "testregistry.azurecr.io"
API_IMAGE = f"{REGISTRY}/test-repo-api@{DIGEST}"
WEB_IMAGE = f"{REGISTRY}/test-repo-web@{DIGEST}"
API_PREVIOUS_IMAGE = f"{REGISTRY}/test-repo-api@sha256:{'1' * 64}"
WEB_PREVIOUS_IMAGE = f"{REGISTRY}/test-repo-web@sha256:{'2' * 64}"
API_FQDN = "test-api.internal.env.example.test"
DB_SECRET = "postgresql+psycopg://app:db-secret-sentinel@db.example.test:5432/appdb"
# A key the contract does not name. Its value must never reach disk or a command line.
STRAY_SECRET = "stray-secret-sentinel"

# What the shared wrapper passes: every GitHub variable and every GitHub secret the run
# can see. Like the real objects, each holds names that are not app config.
VARIABLES = {
    "AUTH_MODE": "entra",
    "AZURE_TENANT_ID": "test-tenant",
    "ENTRA_BACKEND_CLIENT_ID": "test-backend",
    "ENTRA_BACKEND_APP_ID_URI": "api://test-backend",
    "AZURE_AI_FOUNDRY_ENDPOINT": "https://foundry.example.test",
    "AZURE_AI_FOUNDRY_DEPLOYMENT_NAME": "gpt-4o",
    "ENTRA_CLIENT_ID": "test-frontend",
    "ENTRA_TENANT_ID": "test-tenant",
    "ENTRA_API_SCOPE": "api://test-backend/access_as_user",
    # The deploy's sign-in app, a repository variable. Not the API's managed identity.
    "AZURE_CLIENT_ID": "pipeline-app",
}
SECRETS = {
    "DATABASE_URL": DB_SECRET,
    "AZURE_CLIENT_ID": "pipeline-app",
    "github_token": "fake-test-token",
    "STRAY_KEY": STRAY_SECRET,
}
# Still passed by the wrapper while the secrets exist; nothing may read them.
LEGACY_ENV_FILE = "AUTH_MODE=disabled\nLEGACY_KEY=legacy"

API_PREVIOUS_ENV = [
    {"name": "AUTH_MODE", "value": "entra"},
    {"name": "AZURE_CLIENT_ID", "value": "identity-client"},
    {"name": "DATABASE_URL", "secretRef": "database-url"},
]
WEB_PREVIOUS_ENV = [{"name": "ENTRA_CLIENT_ID", "value": "test-frontend"}]

IDENTITY = "/subscriptions/s/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"


def container_app(image, env, secrets=(), mode="Single", min_replicas=1, name="app",
                  registries=({"server": REGISTRY, "identity": IDENTITY},), ingress=None):
    return {
        "properties": {
            "configuration": {
                "activeRevisionsMode": mode,
                "secrets": [{"name": secret} for secret in secrets],
                "registries": list(registries),
                "ingress": ingress or {"external": True, "fqdn": "test-web.env.example.test"},
            },
            "template": {
                "containers": [{"name": name, "image": image, "env": env}],
                "scale": {"minReplicas": min_replicas},
            },
        }
    }


def api_app(env=API_PREVIOUS_ENV, secrets=("database-url", "appinsights-connection-string"),
            ingress=None, **kwargs):
    return container_app(API_PREVIOUS_IMAGE, env, secrets=secrets, name="ca-api",
                         ingress=ingress or {"external": False, "fqdn": API_FQDN}, **kwargs)


HEALTH = {
    "status": "ok", "environment": "dev", "database": "ok",
    "auth": {"mode": "entra", "configured": True},
    "ai": {"provider": "foundry", "configured": True},
}

# One executable impersonates az, gh, and curl. State lives in MOCK_DIR so it survives
# across calls: how many updates each app has had decides which revision is "latest".
FAKE = r'''#!PYTHON
import json, os, pathlib, stat, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state = pathlib.Path(os.environ["MOCK_DIR"])
record = {"name": name, "args": args}

# Nothing the deploy wrote to disk may hold a secret the contract does not read.
for root in (os.environ["RUNNER_TEMP"], os.environ.get("TMPDIR", "")):
    for path in pathlib.Path(root).rglob("*") if root else []:
        if path.is_file():
            text = path.read_text(errors="ignore")
            if os.environ["STRAY_SECRET"] in text:
                record["leaked_to_disk"] = str(path)
record["inherited"] = sorted(
    name for name in ("DEPLOYMENT_SECRETS_JSON", "API_ENV_FILE", "WEB_ENV_FILE") if name in os.environ
)

def option(flag):
    return args[args.index(flag) + 1] if flag in args else None

def updates(app):
    path = state / f"updates-{app}"
    return int(path.read_text()) if path.exists() else 0

if name == "az" and args[:3] == ["keyvault", "secret", "set"]:
    secret = pathlib.Path(option("--file"))
    record["file_mode"] = stat.S_IMODE(secret.stat().st_mode)
    record["file_content"] = secret.read_text()

with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps(record) + "\n")

if os.environ.get("MOCK_FAIL") and os.environ["MOCK_FAIL"] in " ".join([name] + args):
    sys.exit(22)

if name == "gh":
    print(os.environ.get("MOCK_MAIN_SHA") or os.environ["DEPLOY_SHA"])
elif name == "curl":
    responses = json.loads((state / "curl.json").read_text())
    body = responses.get(args[-1])
    if body is None:
        sys.exit(22)
    if "--output" not in args:
        print(json.dumps(body))
elif name == "az" and args[:3] == ["acr", "repository", "show"]:
    print(os.environ["MOCK_DIGEST"])
elif name == "az" and args[:2] == ["containerapp", "update"]:
    app = option("--name")
    (state / f"updates-{app}").write_text(str(updates(app) + 1))
elif name == "az" and args[:2] == ["containerapp", "show"]:
    app = option("--name")
    query = option("--query")
    if query is None:
        print((state / f"app-{app}.json").read_text())
    else:
        # Revision n's health is the nth entry of MOCK_HEALTH_<app>; default Healthy.
        revision = f"{app}--{updates(app)}"
        health = [h for h in os.environ.get(f"MOCK_HEALTH_{app}", "").split(",") if h]
        current = health[updates(app) - 1] if 0 < updates(app) <= len(health) else "Healthy"
        if query == "properties.latestRevisionName":
            print(revision)
        elif query == "properties.latestReadyRevisionName":
            print(revision if current == "Healthy" else f"{app}--0")
elif name == "az" and args[:3] == ["containerapp", "revision", "show"]:
    app = option("--name")
    health = [h for h in os.environ.get(f"MOCK_HEALTH_{app}", "").split(",") if h]
    current = health[updates(app) - 1] if 0 < updates(app) <= len(health) else "Healthy"
    states = {
        "Healthy": ("Healthy", "Running", "Provisioned"),
        "Unhealthy": ("Unhealthy", "Running", "Provisioned"),
        "Failed": ("None", "Failed", "Provisioned"),
        "Pending": ("None", "Activating", "Provisioning"),
    }[current]
    print(json.dumps({"properties": dict(zip(
        ("healthState", "runningState", "provisioningState"), states))}))
'''


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.runner = self.root / "runner"
        self.runner.mkdir()
        self.state = self.root / "state"
        self.state.mkdir()
        self.log = self.root / "commands.jsonl"
        self.summary = self.root / "summary.md"
        for tool in ("az", "gh", "curl"):
            path = self.bin / tool
            path.write_text(FAKE.replace("PYTHON", sys.executable))
            path.chmod(0o755)
        self.set_app("test-api", api_app())
        self.set_app("test-web", container_app(WEB_PREVIOUS_IMAGE, WEB_PREVIOUS_ENV, name="ca-web"))
        self.set_curl()
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "PYTHONDONTWRITEBYTECODE": "1",
            "RUNNER_TEMP": str(self.runner),
            "TMPDIR": str(self.runner),
            "GITHUB_STEP_SUMMARY": str(self.summary),
            "MOCK_LOG": str(self.log),
            "MOCK_DIR": str(self.state),
            "MOCK_DIGEST": DIGEST,
            "STRAY_SECRET": STRAY_SECRET,
            "ROLLOUT_POLL_SECONDS": "0",
            "IMAGE_TAG": SHA,
            "DEPLOY_SHA": SHA,
            "GITHUB_REPOSITORY": "FO-AI/test-repo",
            "GH_TOKEN": "fake-test-token",
            "DEPLOYMENT_VARS_JSON": json.dumps(VARIABLES),
            "DEPLOYMENT_SECRETS_JSON": json.dumps(SECRETS),
            "RESOURCE_GROUP": "test-rg",
            "ACR_NAME": "testregistry",
            "KEY_VAULT_NAME": "test-vault",
            "API_APP_NAME": "test-api",
            "WEB_APP_NAME": "test-web",
            "AZURE_WEB_URL": "https://web.example.test",
            "WEB_URL": "https://custom.example.test",
            "API_ENV_FILE": LEGACY_ENV_FILE,
            "WEB_ENV_FILE": LEGACY_ENV_FILE,
            "ALLOW_PRUNE": "",
            "IMAGE_PREFIX": "",
        }
        for name in ("MOCK_FAIL", "MOCK_MAIN_SHA", "MOCK_HEALTH_test-api", "MOCK_HEALTH_test-web"):
            self.env.pop(name, None)

    def set_app(self, name, definition):
        (self.state / f"app-{name}.json").write_text(json.dumps(definition))

    def set_curl(self, health=HEALTH, web_root=True):
        (self.state / "curl.json").write_text(json.dumps({
            "https://web.example.test/api/health": health,
            "https://custom.example.test/": "" if web_root else None,
        }))

    def deploy(self, **overrides):
        result = subprocess.run(
            ["bash", str(SCRIPT)], env={**self.env, **overrides},
            cwd=REPO, text=True, capture_output=True, check=False,
        )
        commands = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        self.assertEqual(list(self.runner.iterdir()), [], "every rendered file must be removed")
        for command in commands:
            self.assertNotIn("leaked_to_disk", command, command)
            joined = " ".join(command["args"])
            for secret in (DB_SECRET, STRAY_SECRET):
                self.assertNotIn(secret, joined, f"a secret reached a command line: {command['args'][:3]}")
            self.assertEqual(command["inherited"], [], f"inherited by {command['name']} {command['args'][:3]}")
        return result, commands

    @staticmethod
    def mutations(commands):
        return [c for c in commands if c["name"] == "az" and (
            c["args"][:2] == ["containerapp", "update"] or c["args"][:3] == ["keyvault", "secret", "set"]
        )]

    @staticmethod
    def updates(commands):
        return [c["args"] for c in commands if c["name"] == "az" and c["args"][:2] == ["containerapp", "update"]]

    @staticmethod
    def env_args(update):
        flag = "--replace-env-vars"
        start = update.index(flag) + 1
        end = next((i for i in range(start, len(update)) if update[i].startswith("--")), len(update))
        return update[start:end]

    def assert_no_change(self, result, commands, message):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stdout + result.stderr)
        self.assertEqual(self.mutations(commands), [], "nothing may change before validation passes")

    # ---- success ---------------------------------------------------------------

    def test_success_promotes_the_published_digests_with_replace_semantics(self):
        result, commands = self.deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        self.assertFalse(any(c["args"][:2] == ["acr", "build"] for c in commands), "cd.sh never builds")
        updates = self.updates(commands)
        self.assertEqual([u[u.index("--name") + 1] for u in updates], ["test-api", "test-web"])
        self.assertEqual(updates[0][updates[0].index("--image") + 1], API_IMAGE)
        self.assertEqual(updates[1][updates[1].index("--image") + 1], WEB_IMAGE)
        self.assertEqual(updates[0][updates[0].index("--container-name") + 1], "ca-api")
        self.assertFalse(any("--set-env-vars" in u for u in updates), "merge semantics never remove a key")

        self.assertEqual(self.env_args(updates[0]), [
            "AI_PROVIDER=foundry",
            "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string",
            "AUTH_MODE=entra",
            "AZURE_AI_FOUNDRY_DEPLOYMENT_NAME=gpt-4o",
            "AZURE_AI_FOUNDRY_ENDPOINT=https://foundry.example.test",
            "AZURE_CLIENT_ID=identity-client",
            "AZURE_TENANT_ID=test-tenant",
            "DATABASE_URL=secretref:database-url",
            "ENTRA_BACKEND_APP_ID_URI=api://test-backend",
            "ENTRA_BACKEND_CLIENT_ID=test-backend",
            "ENVIRONMENT=dev",
        ])
        self.assertEqual(self.env_args(updates[1]), [
            f"BACKEND_ORIGIN=https://{API_FQDN}",
            "ENTRA_API_SCOPE=api://test-backend/access_as_user",
            "ENTRA_CLIENT_ID=test-frontend",
            "ENTRA_TENANT_ID=test-tenant",
        ])

        summary = self.summary.read_text()
        self.assertIn("deployed", summary)
        self.assertIn(API_IMAGE, summary)

    def test_image_prefix_can_be_overridden(self):
        result, commands = self.deploy(IMAGE_PREFIX="custom")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lookups = [c["args"][c["args"].index("--image") + 1] for c in commands
                   if c["args"][:3] == ["acr", "repository", "show"]]
        self.assertEqual(lookups, [f"custom-api:{SHA}", f"custom-web:{SHA}"])

    def test_order_is_validate_then_secrets_then_api_then_web_then_end_to_end(self):
        result, commands = self.deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        def first(predicate):
            return next(i for i, c in enumerate(commands) if predicate(c))

        main_check = first(lambda c: c["name"] == "gh")
        key_vault = first(lambda c: c["args"][:3] == ["keyvault", "secret", "set"])
        api_update = first(lambda c: c["args"][:2] == ["containerapp", "update"])
        api_gate = first(lambda c: c["args"][:3] == ["containerapp", "revision", "show"])
        web_update = max(i for i, c in enumerate(commands) if c["args"][:2] == ["containerapp", "update"])
        site_health = first(lambda c: c["name"] == "curl" and c["args"][-1].endswith("/api/health"))
        end_to_end = first(lambda c: c["name"] == "curl" and c["args"][-1] == "https://custom.example.test/")
        order = [main_check, key_vault, api_update, api_gate, web_update, site_health, end_to_end]
        self.assertEqual(sorted(order), order)
        reads = [c for c in commands[:main_check] if c["name"] == "az" and c["args"][0] != "extension"]
        self.assertTrue(all(c["args"][1] == "show" or c["args"][2] == "show" for c in reads), reads)

    def test_containerapp_extension_is_current_before_any_containerapp_call(self):
        """--replace-env-vars and --remove-all-env-vars need a recent extension."""
        result, commands = self.deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        az = [c["args"] for c in commands if c["name"] == "az"]
        extension = next(i for i, a in enumerate(az) if a[:2] == ["extension", "add"])
        self.assertIn("--upgrade", az[extension])
        self.assertEqual(az[extension][az[extension].index("--name") + 1], "containerapp")
        first_containerapp = next(i for i, a in enumerate(az) if a[0] == "containerapp")
        self.assertLess(extension, first_containerapp)

    def test_key_vault_values_are_written_from_private_files_only(self):
        result, commands = self.deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        writes = {c["args"][c["args"].index("--name") + 1]: c
                  for c in commands if c["args"][:3] == ["keyvault", "secret", "set"]}
        self.assertEqual(set(writes), {"database-url"})
        self.assertEqual(writes["database-url"]["file_content"], DB_SECRET)
        self.assertTrue(all(w["file_mode"] == 0o600 for w in writes.values()))

    def test_web_url_defaults_to_the_azure_url(self):
        curl = json.loads((self.state / "curl.json").read_text())
        curl["https://web.example.test/"] = ""
        (self.state / "curl.json").write_text(json.dumps(curl))
        result, commands = self.deploy(WEB_URL="")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(c["name"] == "curl" and c["args"][-1] == "https://web.example.test/"
                            for c in commands))

    def test_settings_can_come_from_the_dev_environment_variables(self):
        names = ["RESOURCE_GROUP", "ACR_NAME", "KEY_VAULT_NAME", "API_APP_NAME", "WEB_APP_NAME",
                 "AZURE_WEB_URL", "WEB_URL"]
        variables = {name: self.env[name] for name in names}
        result, _ = self.deploy(**{name: "" for name in names},
                                DEPLOYMENT_VARS_JSON=json.dumps({**VARIABLES, **variables}))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_allow_prune_removes_hand_set_keys(self):
        self.set_app("test-web", container_app(
            WEB_PREVIOUS_IMAGE, WEB_PREVIOUS_ENV + [{"name": "NEXT_PUBLIC_ENTRA_CLIENT_ID", "value": "x"}],
            name="ca-web",
        ))
        result, commands = self.deploy(ALLOW_PRUNE="true")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("web: ALLOW_PRUNE set, removing: NEXT_PUBLIC_ENTRA_CLIENT_ID", result.stderr)
        self.assertNotIn("NEXT_PUBLIC_ENTRA_CLIENT_ID=x", self.env_args(self.updates(commands)[1]))

    # ---- refused before any change -------------------------------------------

    def test_malformed_image_tag(self):
        result, commands = self.deploy(IMAGE_TAG="latest")
        self.assert_no_change(result, commands, "IMAGE_TAG must be a full commit SHA")
        self.assertEqual(commands, [])

    def test_missing_deployment_variable(self):
        result, commands = self.deploy(ACR_NAME="")
        self.assert_no_change(result, commands, "ACR_NAME")
        self.assertEqual(commands, [])

    def test_wrapper_without_the_secrets_object(self):
        for value in (None, ""):
            with self.subTest(value=value):
                self.log.unlink(missing_ok=True)
                env = {**self.env, "DEPLOYMENT_SECRETS_JSON": value or ""}
                if value is None:
                    del env["DEPLOYMENT_SECRETS_JSON"]
                result = subprocess.run(["bash", str(SCRIPT)], env=env, cwd=REPO,
                                        text=True, capture_output=True, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("DEPLOYMENT_SECRETS_JSON is not set", result.stdout + result.stderr)
                self.assertFalse(self.log.exists(), "nothing may run before the input is checked")

    def test_contract_violations(self):
        without_client = {k: v for k, v in VARIABLES.items() if k != "ENTRA_CLIENT_ID"}
        local_db = DB_SECRET.replace("db.example.test", "localhost")
        cases = {
            "AUTH_MODE": ({**VARIABLES, "AUTH_MODE": "disabled"}, SECRETS, "AUTH_MODE must be 'entra'"),
            "local db": (VARIABLES, {**SECRETS, "DATABASE_URL": local_db},
                         "DATABASE_URL must not contain 'localhost'"),
            "web missing": (without_client, SECRETS, "ENTRA_CLIENT_ID is required but not set"),
            # How a wrapper that drops undeclared environment secrets would show up.
            "secrets not received": (VARIABLES, {"AZURE_CLIENT_ID": "x", "github_token": "y"},
                                     "this run received secrets: AZURE_CLIENT_ID, github_token"),
        }
        for label, (variables, secrets, message) in cases.items():
            with self.subTest(label):
                self.log.unlink(missing_ok=True)
                result, commands = self.deploy(DEPLOYMENT_VARS_JSON=json.dumps(variables),
                                               DEPLOYMENT_SECRETS_JSON=json.dumps(secrets))
                self.assert_no_change(result, commands, message)
                self.assertFalse(self.summary.exists() and "deployed" in self.summary.read_text())

    def test_github_values_the_contract_does_not_read_never_reach_a_container(self):
        result, commands = self.deploy(DEPLOYMENT_VARS_JSON=json.dumps({
            **VARIABLES, "ENVIRONMENT": "prod", "BACKEND_ORIGIN": "https://elsewhere.example.test",
            "LEGACY_KEY": "legacy",
        }))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        api, web = (self.env_args(update) for update in self.updates(commands))
        self.assertIn("AZURE_CLIENT_ID=identity-client", api)
        self.assertIn("ENVIRONMENT=dev", api)
        self.assertIn(f"BACKEND_ORIGIN=https://{API_FQDN}", web)
        updates = json.dumps(self.updates(commands))
        for value in ("pipeline-app", "LEGACY_KEY", "AUTH_MODE=disabled", "elsewhere", "prod"):
            self.assertNotIn(value, updates)

    def test_unpublished_image(self):
        result, commands = self.deploy(MOCK_FAIL="acr repository show")
        self.assert_no_change(result, commands, "publish must succeed before deploy")

    def test_malformed_digest(self):
        result, commands = self.deploy(MOCK_DIGEST="latest")
        self.assert_no_change(result, commands, "did not resolve to a sha256 digest")

    def test_multiple_revision_mode_has_no_single_revision_to_gate(self):
        self.set_app("test-web", container_app(WEB_PREVIOUS_IMAGE, WEB_PREVIOUS_ENV, mode="Multiple"))
        result, commands = self.deploy()
        self.assert_no_change(result, commands, "test-web must use Single revision mode")

    def test_scale_to_zero_has_no_replica_to_gate(self):
        self.set_app("test-web", container_app(WEB_PREVIOUS_IMAGE, WEB_PREVIOUS_ENV, min_replicas=0))
        result, commands = self.deploy()
        self.assert_no_change(result, commands, "test-web requires minReplicas >= 1")

    def test_registry_pull_without_managed_identity(self):
        for registries in ((), ({"server": REGISTRY, "username": "admin", "passwordSecretRef": "p"},),
                           ({"server": "other.azurecr.io", "identity": IDENTITY},)):
            with self.subTest(registries=registries):
                self.log.unlink(missing_ok=True)
                self.set_app("test-web", container_app(WEB_PREVIOUS_IMAGE, WEB_PREVIOUS_ENV,
                                                       registries=registries))
                result, commands = self.deploy()
                self.assert_no_change(result, commands,
                                      f"test-web must pull from {REGISTRY} with a managed identity")

    def test_public_api_ingress_is_refused(self):
        self.set_app("test-api", api_app(ingress={"external": True, "fqdn": "test-api.example.test"}))
        result, commands = self.deploy()
        self.assert_no_change(result, commands, "test-api must have internal ingress")

    def test_api_without_ingress_address_is_refused(self):
        self.set_app("test-api", api_app(ingress={"external": False}))
        result, commands = self.deploy()
        self.assert_no_change(result, commands, "test-api has no ingress FQDN")

    def test_hand_set_key_would_be_pruned(self):
        self.set_app("test-api", api_app(env=API_PREVIOUS_ENV + [{"name": "HAND_SET", "value": "x"}]))
        result, commands = self.deploy()
        self.assert_no_change(result, commands, "would be removed: HAND_SET")

    def test_missing_key_vault_binding(self):
        self.set_app("test-api", api_app(secrets=()))
        result, commands = self.deploy()
        self.assert_no_change(result, commands, "the app declares no secret database-url")

    def test_stale_main(self):
        result, commands = self.deploy(MOCK_MAIN_SHA="b" * 40)
        self.assert_no_change(result, commands, "Refusing stale deployment")

    def test_main_lookup_failure(self):
        result, commands = self.deploy(MOCK_FAIL="gh api")
        self.assert_no_change(result, commands, "")

    def test_key_vault_failure_touches_no_app(self):
        result, commands = self.deploy(MOCK_FAIL="--name database-url")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.updates(commands), [])

    # ---- rolled back after a change -------------------------------------------

    def rollbacks(self, commands):
        """Updates after the forward ones, as (app, image, env args)."""
        return [
            (u[u.index("--name") + 1], u[u.index("--image") + 1], self.env_args(u))
            for u in self.updates(commands)
            if u[u.index("--image") + 1] in (API_PREVIOUS_IMAGE, WEB_PREVIOUS_IMAGE)
        ]

    API_RESTORE = ("test-api", API_PREVIOUS_IMAGE, [
        "AUTH_MODE=entra", "AZURE_CLIENT_ID=identity-client", "DATABASE_URL=secretref:database-url",
    ])
    WEB_RESTORE = ("test-web", WEB_PREVIOUS_IMAGE, ["ENTRA_CLIENT_ID=test-frontend"])

    def assert_rolled_back(self, result, commands, expected):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.rollbacks(commands), expected)
        self.assertIn("rolled back", self.summary.read_text())

    def test_unhealthy_api_revision_fails_fast_and_restores_the_api_only(self):
        result, commands = self.deploy(**{"MOCK_HEALTH_test-api": "Unhealthy"})
        self.assert_rolled_back(result, commands, [self.API_RESTORE])
        polls = [c for c in commands if c["args"][:3] == ["containerapp", "revision", "show"]]
        self.assertEqual(len(polls), 2, "one poll for the failed revision, one for the restore")
        self.assertNotIn(WEB_IMAGE, json.dumps(self.updates(commands)))

    def test_failed_revision_fails_fast(self):
        result, commands = self.deploy(**{"MOCK_HEALTH_test-api": "Failed"})
        self.assert_rolled_back(result, commands, [self.API_RESTORE])

    def test_revision_that_never_becomes_ready_times_out(self):
        result, commands = self.deploy(**{"MOCK_HEALTH_test-api": "Pending", "ROLLOUT_POLL_LIMIT": "3"})
        self.assert_rolled_back(result, commands, [self.API_RESTORE])
        self.assertIn("did not become healthy", result.stdout)

    def test_site_health_semantics_restore_web_then_api(self):
        for broken in ({**HEALTH, "auth": {"mode": "entra", "configured": False}},
                       {**HEALTH, "auth": {"mode": "disabled", "configured": False}},
                       {**HEALTH, "ai": {"provider": "foundry", "configured": False}},
                       {**HEALTH, "database": "error", "status": "degraded"},
                       {**HEALTH, "environment": "local"}):
            with self.subTest(broken=broken):
                self.log.unlink(missing_ok=True)
                for path in self.state.glob("updates-*"):
                    path.unlink()
                self.set_curl(health=broken)
                result, commands = self.deploy()
                self.assert_rolled_back(result, commands, [self.WEB_RESTORE, self.API_RESTORE])

    def test_unhealthy_web_revision_restores_web_then_api(self):
        result, commands = self.deploy(**{"MOCK_HEALTH_test-web": "Unhealthy"})
        self.assert_rolled_back(result, commands, [self.WEB_RESTORE, self.API_RESTORE])

    def test_unreachable_site_restores_web_then_api(self):
        self.set_curl(web_root=False)
        result, commands = self.deploy()
        self.assert_rolled_back(result, commands, [self.WEB_RESTORE, self.API_RESTORE])

    def test_failed_web_rollback_still_restores_the_api(self):
        result, commands = self.deploy(**{"MOCK_HEALTH_test-web": "Unhealthy,Unhealthy"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.rollbacks(commands), [self.WEB_RESTORE, self.API_RESTORE])
        self.assertIn("Web rollback failed; manual recovery is required", result.stdout)
        self.assertIn("rollback FAILED", self.summary.read_text())

    def test_rollback_warns_that_key_vault_keeps_the_new_versions(self):
        result, _ = self.deploy(**{"MOCK_HEALTH_test-api": "Unhealthy"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Key Vault secrets keep their new versions", result.stdout)


class StaticTests(unittest.TestCase):
    def test_no_script_sources_an_env_file(self):
        for script in ("cd.sh", "aca_rollout.sh"):
            text = (REPO / "scripts" / script).read_text()
            self.assertIsNone(re.search(r"^\s*(source|\.)\s", text, re.MULTILINE), script)
            self.assertNotIn("set -a", text, script)


if __name__ == "__main__":
    unittest.main()
