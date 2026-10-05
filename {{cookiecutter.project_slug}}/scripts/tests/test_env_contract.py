"""deploy/env-contract.json must stay honest about what the apps actually read.

Derived, never hand-maintained: adding an API setting or a web runtime variable without
deciding how it deploys fails here. Needs the API's dependencies installed (scripts/ci.sh
backend runs it).
"""

import json
from pathlib import Path
import re
import sys
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "api"))

from pydantic import AliasChoices  # noqa: E402

from app.core.config import Settings  # noqa: E402

CONTRACT = json.loads((REPO / "deploy" / "env-contract.json").read_text())
WEB_SOURCES = REPO / "web" / "src"
OWNER_SECTIONS = ("variables", "derived", "infra", "secret_refs", "secrets", "omitted", "rename")

# Read by the web app but not deployable configuration.
WEB_NOT_DEPLOYED = {
    "NODE_ENV": "set by Next.js itself",
    "NEXT_PUBLIC_AUTH_DISABLED": "build-time only, so a published image cannot disable sign-in",
}


def settings_env_names():
    """Every env name Settings accepts: alias choices where declared, else the field name."""
    names = set()
    for name, field in Settings.model_fields.items():
        if isinstance(field.validation_alias, AliasChoices):
            names.update(str(choice).upper() for choice in field.validation_alias.choices)
        elif field.alias:
            names.add(field.alias.upper())
        else:
            names.add(name.upper())
    return names


def web_env_reads():
    names = set()
    for path in WEB_SOURCES.rglob("*.ts*"):
        names.update(re.findall(r"process\.env\.([A-Z0-9_]+)", path.read_text()))
    return names


def covered(spec):
    return {key for section in OWNER_SECTIONS for key in spec[section]}


class ContractTests(unittest.TestCase):
    def test_api_contract_covers_the_settings_surface(self):
        """A new setting must be given an owner; infra-only names are the only extras."""
        api = CONTRACT["api"]
        settings = settings_env_names()
        missing = settings - covered(api)
        self.assertFalse(missing, f"add to deploy/env-contract.json under api: {sorted(missing)}")
        unknown = covered(api) - settings - set(api["infra"])
        self.assertFalse(unknown, f"not a Settings field: {sorted(unknown)}")

    def test_web_contract_covers_exactly_what_the_web_server_reads(self):
        read = web_env_reads() - set(WEB_NOT_DEPLOYED)
        self.assertTrue(read, "no process.env reads found; update this test's pattern")
        web = CONTRACT["web"]
        self.assertEqual(read, set(web["variables"]) | set(web["derived"]))

    def test_web_inlines_nothing_environment_specific_at_build(self):
        """One image must serve every environment: no NEXT_PUBLIC_ value but the auth flag."""
        public = {name for name in web_env_reads() if name.startswith("NEXT_PUBLIC_")}
        self.assertEqual(public, {"NEXT_PUBLIC_AUTH_DISABLED"})

    def test_each_name_has_exactly_one_owner(self):
        for service in ("api", "web"):
            spec = CONTRACT[service]
            # A secret may share a name with its secret_ref binding on purpose: the GitHub
            # value goes to Key Vault, the container gets the reference.
            sections = [set(spec[s]) for s in ("variables", "derived", "infra", "secret_refs")]
            sections.append(set(spec["secrets"]) - set(spec["secret_refs"]))
            seen = set()
            for names in sections:
                self.assertFalse(seen & names, f"{service}: {sorted(seen & names)}")
                seen |= names

    def test_required_keys_come_from_github(self):
        for service in ("api", "web"):
            spec = CONTRACT[service]
            self.assertLessEqual(set(spec["required"]), set(spec["variables"]) | set(spec["secrets"]))

    def test_a_github_name_is_a_variable_or_a_secret_never_both(self):
        """GitHub has one namespace for every service; the kind must agree across them."""
        services = (CONTRACT["api"], CONTRACT["web"])
        variables = {key for spec in services for key in (*spec["variables"], *spec["rename"])}
        secrets = {key for spec in services for key in spec["secrets"]}
        self.assertFalse(variables & secrets, sorted(variables & secrets))

    def test_rules_and_defaults_reference_github_keys(self):
        for service in ("api", "web"):
            spec = CONTRACT[service]
            github_keys = set(spec["variables"]) | set(spec["secrets"])
            for rule in spec["rules"]:
                self.assertIn(rule["key"], github_keys, service)
            self.assertLessEqual(set(spec["defaults"]), set(spec["variables"]), service)
            self.assertLessEqual(set(spec["rename"].values()), set(spec["variables"]), service)

    def test_every_secret_has_a_binding_on_the_app(self):
        """A secret synced to Key Vault that no env var references would never be read."""
        for service in ("api", "web"):
            spec = CONTRACT[service]
            bound = {ref["secret"] for ref in spec["secret_refs"].values()}
            self.assertLessEqual(set(spec["secrets"].values()), bound, service)


if __name__ == "__main__":
    unittest.main()
