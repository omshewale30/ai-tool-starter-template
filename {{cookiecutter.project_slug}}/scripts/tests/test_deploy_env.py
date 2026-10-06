"""The deploy env renderer (scripts/deploy_env.py), against a small contract.

Written as the list of ways a deploy's configuration can be wrong, before the code:

Input (the shared CD wrapper passes every GitHub variable and every GitHub secret the
run can see as two JSON objects, DEPLOYMENT_VARS_JSON and DEPLOYMENT_SECRETS_JSON)
  - the secrets object is missing, as it is when the wrapper is pinned at a commit that
    does not pass it;
  - either object is not JSON, not an object, or holds a non-string value;
  - an error quotes the object, and with it a value.
Collecting (only keys the contract assigns to GitHub are read, each from its own kind)
  - a pipeline name that is also a container key (AZURE_CLIENT_ID is both the deploy's
    sign-in app and the API's managed identity) leaks into the container;
  - a renamed key is set under both names.
Rendering (what reaches the container)
  - a required key is missing (and a missing secret does not say what did arrive, which
    is how a wrapper that drops undeclared secrets would show up); a rule is violated;
  - cd.sh fails to supply, or supplies an undeclared, derived value;
  - infra-owned values are lost instead of carried over from the running app;
  - a required Key Vault binding is missing from the app;
  - a secret's value leaks into the container env;
  - replace semantics would silently delete a hand-set key;
  - an error message contains a value.
"""

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from deploy_env import ContractError, load_github_json, previous_env_args, render  # noqa: E402

CONTRACT = {
    "api": {
        "variables": ["AUTH_MODE", "LOG_LEVEL", "AI_PROVIDER", "DEPLOYMENT_NAME"],
        "rename": {"CHAT_DEPLOYMENT_NAME": "DEPLOYMENT_NAME"},
        "defaults": {"AI_PROVIDER": "foundry"},
        "derived": {"ENVIRONMENT": "deploy target"},
        "infra": {"AZURE_CLIENT_ID": "identity", "OTEL_TRACES_SAMPLER": "sampling"},
        "secret_refs": {
            "DATABASE_URL": {"secret": "database-url", "required": True},
            "FOUNDRY_KEY": {"secret": "foundry-api-key"},
        },
        "secrets": {"DEV_DATABASE_URL": "database-url", "FOUNDRY_KEY": "foundry-api-key"},
        "omitted": {},
        "required": ["AUTH_MODE", "DEV_DATABASE_URL"],
        "rules": [
            {"key": "AUTH_MODE", "equals": "entra", "why": "no bypass"},
            {"key": "DEV_DATABASE_URL", "not_contains": ["localhost", "127.0.0.1"]},
        ],
    }
}

DB_SECRET = "postgresql://user:hunter2-db-secret@db.example.test/app"
VARIABLES = {"AUTH_MODE": "entra", "RESOURCE_GROUP": "rg-unrelated"}
SECRETS = {
    "DEV_DATABASE_URL": DB_SECRET,
    "FOUNDRY_KEY": "foundry-secret-value",
    "github_token": "ghs-token-value",
}
DERIVED = {"ENVIRONMENT": "dev"}


def app(env=None, secrets=("database-url", "foundry-api-key")):
    """The shape of `az containerapp show -o json` that deploy_env.py reads."""
    return {
        "properties": {
            "configuration": {"secrets": [{"name": name} for name in secrets]},
            "template": {"containers": [{"name": "api", "env": env or []}]},
        }
    }


def render_api(variables=None, secrets=None, derived=DERIVED, current_app=None, allow_prune=False):
    return render(
        "api", CONTRACT,
        VARIABLES if variables is None else variables,
        SECRETS if secrets is None else secrets,
        derived, current_app or app(), allow_prune,
    )


def problems_of(function, *args, **kwargs):
    with unittest.TestCase().assertRaises(ContractError) as caught:
        function(*args, **kwargs)
    return caught.exception.problems


class GitHubJsonTests(unittest.TestCase):
    def test_reads_an_object_of_strings(self):
        self.assertEqual(load_github_json('{"A": "1"}', "DEPLOYMENT_VARS_JSON"), {"A": "1"})

    def test_missing_secrets_names_the_wrapper_pin(self):
        for raw in (None, ""):
            with self.subTest(raw=raw):
                problems = problems_of(load_github_json, raw, "DEPLOYMENT_SECRETS_JSON")
                self.assertTrue(any("DEPLOYMENT_SECRETS_JSON is not set" in p and "FO-AI/automation" in p
                                    for p in problems), problems)

    def test_malformed_input_is_rejected_without_quoting_it(self):
        for raw in ('{"A": "secret-sentinel"', '["secret-sentinel"]', '{"A": ["secret-sentinel"]}'):
            with self.subTest(raw=raw):
                problems = problems_of(load_github_json, raw, "DEPLOYMENT_SECRETS_JSON")
                self.assertTrue(any("DEPLOYMENT_SECRETS_JSON" in p for p in problems), problems)
                self.assertNotIn("secret-sentinel", "\n".join(problems))


class RenderTests(unittest.TestCase):
    def test_success_renders_variables_derived_infra_and_secret_refs(self):
        current = app(env=[
            {"name": "AZURE_CLIENT_ID", "value": "identity-client"},
            {"name": "OTEL_TRACES_SAMPLER", "value": "microsoft.rate_limited"},
        ])
        rendered = render_api(current_app=current)

        self.assertEqual(rendered.env_args, [
            "AI_PROVIDER=foundry",
            "AUTH_MODE=entra",
            "AZURE_CLIENT_ID=identity-client",
            "DATABASE_URL=secretref:database-url",
            "ENVIRONMENT=dev",
            "FOUNDRY_KEY=secretref:foundry-api-key",
            "OTEL_TRACES_SAMPLER=microsoft.rate_limited",
        ])
        self.assertEqual(
            rendered.key_vault,
            {"database-url": DB_SECRET, "foundry-api-key": "foundry-secret-value"},
        )

    def test_secret_values_never_reach_the_container_env(self):
        joined = "\n".join(render_api().env_args)
        self.assertNotIn(DB_SECRET, joined)
        self.assertNotIn("foundry-secret-value", joined)
        self.assertNotIn("DEV_DATABASE_URL", joined)

    def test_names_the_contract_does_not_assign_to_github_are_ignored(self):
        """Both objects hold the whole run's variables and secrets, most of them not app config."""
        rendered = render_api(
            variables={**VARIABLES, "AZURE_CLIENT_ID": "pipeline-app", "ENVIRONMENT": "prod",
                       "DATABASE_URL": "plain-db-url"},
            secrets={**SECRETS, "AZURE_CLIENT_ID": "pipeline-app"},
            current_app=app(env=[{"name": "AZURE_CLIENT_ID", "value": "identity-client"}]),
        )
        self.assertIn("AZURE_CLIENT_ID=identity-client", rendered.env_args)
        self.assertIn("ENVIRONMENT=dev", rendered.env_args)
        self.assertIn("DATABASE_URL=secretref:database-url", rendered.env_args)
        joined = "\n".join(rendered.env_args)
        for value in ("pipeline-app", "prod", "plain-db-url", "rg-unrelated", "ghs-token-value"):
            self.assertNotIn(value, joined)

    def test_each_key_is_read_only_from_its_own_kind(self):
        """AZURE_TENANT_ID is legitimately both: the API's tenant and the deploy's sign-in tenant."""
        rendered = render_api(
            variables={**VARIABLES, "FOUNDRY_KEY": "variable-copy"},
            secrets={**SECRETS, "AUTH_MODE": "secret-copy"},
        )
        self.assertIn("AUTH_MODE=entra", rendered.env_args)
        self.assertEqual(rendered.key_vault["foundry-api-key"], "foundry-secret-value")
        self.assertNotIn("copy", "\n".join(rendered.env_args) + json.dumps(rendered.key_vault))

    def test_missing_required_variable_fails(self):
        problems = problems_of(render_api, variables={})
        self.assertIn("AUTH_MODE is required but not set (a dev environment variable)", problems)

    def test_missing_required_secret_lists_the_secret_names_that_did_arrive(self):
        problems = problems_of(render_api, secrets={"FOUNDRY_KEY": "x", "github_token": "y"})
        message = next(p for p in problems if p.startswith("DEV_DATABASE_URL is required but not set"))
        self.assertIn("a dev environment secret", message)
        self.assertIn("this run received secrets: FOUNDRY_KEY, github_token", message)
        self.assertNotIn("ghs-token-value", message)

    def test_equals_rule(self):
        problems = problems_of(render_api, variables={"AUTH_MODE": "disabled"})
        self.assertIn("AUTH_MODE must be 'entra' (no bypass)", problems)

    def test_not_contains_rule(self):
        for host in ("localhost", "127.0.0.1"):
            with self.subTest(host=host):
                secrets = {**SECRETS, "DEV_DATABASE_URL": DB_SECRET.replace("db.example.test", host)}
                self.assertIn(f"DEV_DATABASE_URL must not contain {host!r}",
                              problems_of(render_api, secrets=secrets))

    def test_renamed_key_is_accepted_under_its_old_name(self):
        rendered = render_api(variables={**VARIABLES, "CHAT_DEPLOYMENT_NAME": "gpt-4o"})
        self.assertIn("DEPLOYMENT_NAME=gpt-4o", rendered.env_args)

    def test_renamed_key_set_under_both_names_fails(self):
        variables = {**VARIABLES, "CHAT_DEPLOYMENT_NAME": "a", "DEPLOYMENT_NAME": "b"}
        self.assertIn(
            "CHAT_DEPLOYMENT_NAME and DEPLOYMENT_NAME are the same setting; keep DEPLOYMENT_NAME",
            problems_of(render_api, variables=variables),
        )

    def test_default_applies_only_when_absent(self):
        self.assertIn("AI_PROVIDER=mock", render_api(variables={**VARIABLES, "AI_PROVIDER": "mock"}).env_args)

    def test_derived_values_must_match_the_contract(self):
        problems = problems_of(render_api, derived={"SURPRISE": "x"})
        self.assertIn("derived value ENVIRONMENT was not supplied by the deploy", problems)
        self.assertIn("derived value SURPRISE is not declared in the contract", problems)

    def test_infra_secret_reference_is_carried_over_as_a_reference(self):
        current = app(env=[{"name": "OTEL_TRACES_SAMPLER", "secretRef": "sampler"}])
        self.assertIn("OTEL_TRACES_SAMPLER=secretref:sampler", render_api(current_app=current).env_args)

    def test_infra_key_absent_from_the_app_is_not_invented(self):
        self.assertFalse(any(arg.startswith("AZURE_CLIENT_ID=") for arg in render_api().env_args))

    def test_missing_required_secret_binding_fails(self):
        self.assertIn(
            "the app declares no secret database-url for DATABASE_URL; run infra/scripts/deploy-api-app.sh",
            problems_of(render_api, current_app=app(secrets=("foundry-api-key",))),
        )

    def test_optional_secret_binding_is_skipped_when_the_app_lacks_it(self):
        rendered = render_api(current_app=app(secrets=("database-url",)))
        self.assertFalse(any(arg.startswith("FOUNDRY_KEY=") for arg in rendered.env_args))

    def test_replace_would_remove_hand_set_keys_so_it_is_refused(self):
        current = app(env=[{"name": "HAND_SET", "value": "x"}, {"name": "ALSO", "value": "y"}])
        problems = problems_of(render_api, current_app=current)
        self.assertTrue(
            any("would be removed: ALSO, HAND_SET" in p and "ALLOW_PRUNE=true" in p for p in problems),
            problems,
        )

    def test_prune_is_accepted_when_explicitly_allowed(self):
        current = app(env=[{"name": "HAND_SET", "value": "x"}])
        rendered = render_api(current_app=current, allow_prune=True)
        self.assertEqual(rendered.pruned, ["HAND_SET"])
        self.assertFalse(any(arg.startswith("HAND_SET=") for arg in rendered.env_args))

    def test_values_never_appear_in_errors(self):
        variables = {
            "AUTH_MODE": "disabled-secret-sentinel",
            "FOUNDRY_KEY": "exposed-secret-sentinel",
            "CHAT_DEPLOYMENT_NAME": "a-secret-sentinel", "DEPLOYMENT_NAME": "b-secret-sentinel",
        }
        secrets = {"DEV_DATABASE_URL": "postgresql://u:pw-secret-sentinel@localhost/db",
                   "LOG_LEVEL": "level-secret-sentinel"}
        current = app(env=[{"name": "HAND_SET", "value": "hand-secret-sentinel"}], secrets=())
        problems = problems_of(render_api, variables, secrets, current_app=current)
        self.assertGreaterEqual(len(problems), 5)
        self.assertNotIn("secret-sentinel", "\n".join(problems))


class PreviousEnvTests(unittest.TestCase):
    def test_previous_env_is_rendered_for_an_exact_restore(self):
        current = app(env=[
            {"name": "PLAIN", "value": "v=1"},
            {"name": "EMPTY"},
            {"name": "SECRET", "secretRef": "database-url"},
        ])
        self.assertEqual(
            previous_env_args(current),
            ["PLAIN=v=1", "EMPTY=", "SECRET=secretref:database-url"],
        )


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "contract.json").write_text(json.dumps(CONTRACT))
        (self.root / "app.json").write_text(json.dumps(app()))

    def run_cli(self, variables=VARIABLES, secrets=SECRETS, *extra):
        env = {**os.environ, "DEPLOYMENT_VARS_JSON": json.dumps(variables)}
        env.pop("DEPLOYMENT_SECRETS_JSON", None)
        if secrets is not None:
            env["DEPLOYMENT_SECRETS_JSON"] = json.dumps(secrets)
        return subprocess.run(
            [sys.executable, str(SCRIPTS / "deploy_env.py"), "--service", "api",
             "--contract", str(self.root / "contract.json"),
             "--current-app", str(self.root / "app.json"),
             "--derived", "ENVIRONMENT=dev", *extra],
            env=env, capture_output=True, text=True, check=False,
        )

    def test_writes_private_nul_delimited_outputs(self):
        result = self.run_cli(
            VARIABLES, SECRETS, "--out", str(self.root / "env.args"),
            "--key-vault-out", str(self.root / "kv"),
            "--previous-out", str(self.root / "previous.args"), "--emit-masks",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.root / "env.args").read_text().split("\0")
        self.assertIn("AUTH_MODE=entra", args)
        self.assertEqual((self.root / "kv" / "database-url").read_text(), DB_SECRET)
        for path in (self.root / "env.args", self.root / "kv" / "database-url",
                     self.root / "previous.args"):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600, path)
        self.assertIn(f"::add-mask::{DB_SECRET}", result.stdout)

    def test_rejection_exits_nonzero_without_values_or_traceback(self):
        result = self.run_cli({"AUTH_MODE": "disabled", "FOUNDRY_KEY": "hunter2-exposed"}, SECRETS)
        self.assertEqual(result.returncode, 1)
        self.assertIn("deploy config rejected", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("hunter2", result.stderr + result.stdout)

    def test_missing_secrets_object_is_rejected(self):
        result = self.run_cli(VARIABLES, None)
        self.assertEqual(result.returncode, 1)
        self.assertIn("DEPLOYMENT_SECRETS_JSON is not set", result.stderr)

    def test_reads_nothing_from_stdin(self):
        """The env file used to arrive on stdin; nothing may still depend on that."""
        result = subprocess.run(
            [sys.executable, str(SCRIPTS / "deploy_env.py"), "--service", "api",
             "--contract", str(self.root / "contract.json"),
             "--current-app", str(self.root / "app.json"), "--derived", "ENVIRONMENT=dev"],
            env={**os.environ, "DEPLOYMENT_VARS_JSON": json.dumps(VARIABLES),
                 "DEPLOYMENT_SECRETS_JSON": json.dumps(SECRETS)},
            input="AUTH_MODE=disabled\n", capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")
    unittest.main()
