#!/usr/bin/env python3
"""Turn the run's GitHub variables and secrets into the exact env a container app may receive.

Collect, validate, render — all before scripts/cd.sh makes its first change to Azure, so
a deploy that is going to be rejected is rejected while nothing has changed. The
contract is deploy/env-contract.json; its `_comment` explains the owners (variables,
derived, infra, secret_refs, secrets).

The shared CD wrapper passes every variable and every secret the run can see as two JSON
objects, DEPLOYMENT_VARS_JSON and DEPLOYMENT_SECRETS_JSON. Both are read from this
process's environment, never from a command line, and only the names the contract
assigns to GitHub are read out of them.

Errors name keys, never values. The deploy runner has no API
dependencies installed, so this is stdlib only.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import json
import os
from pathlib import Path
import sys

PRIVATE_FILE_MODE = 0o600
VARIABLES_ENV = "DEPLOYMENT_VARS_JSON"
SECRETS_ENV = "DEPLOYMENT_SECRETS_JSON"
WRAPPER = "FO-AI/automation reusable-azure-cd.yml"


class ContractError(Exception):
    """Every failure carries the full list, so one run says everything that is wrong."""

    def __init__(self, problems: list[str]):
        self.problems = problems
        super().__init__(f"{len(problems)} problem(s)")


@dataclass(frozen=True)
class Rendered:
    env_args: list[str]
    key_vault: dict[str, str]
    pruned: list[str] = field(default_factory=list)


def load_github_json(raw: str | None, name: str) -> dict[str, str]:
    """One of the wrapper's two objects; errors never quote it, since it may hold secrets."""
    if not raw:
        raise ContractError([f"{name} is not set; pin {WRAPPER} at a commit that passes it"])
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        raise ContractError([f"{name} is not valid JSON"]) from None
    if not isinstance(parsed, dict) or not all(isinstance(value, str) for value in parsed.values()):
        raise ContractError([f"{name} must be a JSON object of strings"])
    return parsed


def _collect(
    spec: dict, variables: dict[str, str], secrets: dict[str, str]
) -> tuple[dict[str, str], dict[str, str]]:
    """Read only the names the contract assigns to GitHub, each from its own kind."""
    variable_keys = set(spec["variables"]) | set(spec["rename"])
    from_variables = {key: value for key, value in variables.items() if key in variable_keys}
    from_secrets = {key: value for key, value in secrets.items() if key in spec["secrets"]}
    return from_variables, from_secrets


def _missing_problem(key: str, spec: dict, secrets: dict[str, str]) -> str:
    if key not in spec["secrets"]:
        return f"{key} is required but not set (a dev environment variable)"
    # Names only. A wrapper that drops undeclared environment secrets shows up here.
    received = ", ".join(sorted(secrets)) or "none"
    return f"{key} is required but not set (a dev environment secret; this run received secrets: {received})"


def _apply_renames(spec: dict, values: dict[str, str]) -> tuple[dict[str, str], list[str]]:
    renamed = dict(values)
    problems = []
    for old, new in spec["rename"].items():
        if old not in renamed:
            continue
        if new in renamed:
            problems.append(f"{old} and {new} are the same setting; keep {new}")
            continue
        renamed[new] = renamed.pop(old)
    return renamed, problems


def _rule_problems(rules: list[dict], values: dict[str, str]) -> list[str]:
    problems = []
    for rule in rules:
        key = rule["key"]
        if key not in values:
            continue  # absence is the `required` list's job
        value = values[key]
        why = f" ({rule['why']})" if "why" in rule else ""
        if "equals" in rule and value != rule["equals"]:
            problems.append(f"{key} must be {rule['equals']!r}{why}")
        for fragment in rule.get("not_contains", []):
            if fragment in value:
                problems.append(f"{key} must not contain {fragment!r}{why}")
    return problems


def _current_env(current_app: dict) -> list[dict]:
    return current_app["properties"]["template"]["containers"][0].get("env") or []


def _env_arg(entry: dict) -> str:
    if entry.get("secretRef"):
        return f"{entry['name']}=secretref:{entry['secretRef']}"
    return f"{entry['name']}={entry.get('value') or ''}"


def previous_env_args(current_app: dict) -> list[str]:
    """The running app's env as replace arguments, so a rollback restores it exactly."""
    return [_env_arg(entry) for entry in _current_env(current_app)]


def render(
    service: str,
    contract: dict,
    variables: dict[str, str],
    secrets: dict[str, str],
    derived: dict[str, str],
    current_app: dict,
    allow_prune: bool = False,
) -> Rendered:
    """Collect from GitHub, validate, and return what to apply."""
    spec = contract[service]
    allowed, secret_values = _collect(spec, variables, secrets)
    allowed, problems = _apply_renames(spec, allowed)
    for key, default in spec["defaults"].items():
        allowed.setdefault(key, default)

    github_values = {**allowed, **secret_values}
    problems += [_missing_problem(key, spec, secrets) for key in spec["required"] if not github_values.get(key)]
    problems += _rule_problems(spec["rules"], github_values)

    problems += [f"derived value {key} was not supplied by the deploy" for key in spec["derived"] if key not in derived]
    problems += [f"derived value {key} is not declared in the contract" for key in derived if key not in spec["derived"]]

    env = {key: f"{key}={value}" for key, value in allowed.items()}
    env.update({key: f"{key}={value}" for key, value in derived.items() if key in spec["derived"]})

    current = {entry["name"]: entry for entry in _current_env(current_app)}
    env.update({key: _env_arg(current[key]) for key in spec["infra"] if key in current})

    app_secrets = {secret["name"] for secret in current_app["properties"]["configuration"].get("secrets") or []}
    for key, ref in spec["secret_refs"].items():
        if ref["secret"] in app_secrets:
            env[key] = f"{key}=secretref:{ref['secret']}"
        elif ref.get("required"):
            problems.append(
                f"the app declares no secret {ref['secret']} for {key}; run infra/scripts/deploy-{service}-app.sh"
            )

    pruned = sorted(set(current) - set(env))
    if pruned and not allow_prune:
        # --replace-env-vars removes anything not re-declared. A key set by hand in the
        # portal would vanish silently on the next run.
        problems.append(
            "these variables are set on the container app but not by the contract, and would be "
            f"removed: {', '.join(pruned)}. Add them to deploy/env-contract.json, or re-run the CD "
            "workflow by hand with allow-prune (ALLOW_PRUNE=true) to accept."
        )

    if problems:
        raise ContractError(problems)

    key_vault = {spec["secrets"][key]: value for key, value in secret_values.items()}
    return Rendered([env[key] for key in sorted(env)], key_vault, pruned)


def _write_private(path: Path, text: str) -> None:
    # Created 0600 rather than chmod-ed after, so the content is never world-readable.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, PRIVATE_FILE_MODE)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(text)


def _parse_derived(pairs: list[str]) -> dict[str, str]:
    derived = {}
    for pair in pairs:
        key, separator, value = pair.partition("=")
        if not separator:
            raise ContractError([f"--derived expects KEY=VALUE, got {key!r}"])
        derived[key] = value
    return derived


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", required=True, choices=["api", "web"])
    parser.add_argument("--contract", default="deploy/env-contract.json")
    parser.add_argument("--current-app", required=True, help="`az containerapp show -o json` output")
    parser.add_argument("--derived", action="append", default=[], help="KEY=VALUE computed by the deploy")
    parser.add_argument("--allow-prune", action="store_true")
    parser.add_argument("--out", help="NUL-delimited KEY=VALUE records for --replace-env-vars")
    parser.add_argument("--previous-out", help="NUL-delimited records restoring the current env")
    parser.add_argument("--key-vault-out", help="directory: one 0600 file per Key Vault secret")
    parser.add_argument("--emit-masks", action="store_true", help="print ::add-mask:: for Key Vault values")
    args = parser.parse_args(argv)

    contract = json.loads(Path(args.contract).read_text())
    current_app = json.loads(Path(args.current_app).read_text())
    variables = load_github_json(os.environ.get(VARIABLES_ENV), VARIABLES_ENV)
    secrets = load_github_json(os.environ.get(SECRETS_ENV), SECRETS_ENV)
    rendered = render(
        args.service, contract, variables, secrets, _parse_derived(args.derived), current_app,
        args.allow_prune,
    )

    if args.emit_masks:
        for value in rendered.key_vault.values():
            if value:
                print(f"::add-mask::{value}")
    if rendered.pruned:
        print(f"{args.service}: ALLOW_PRUNE set, removing: {', '.join(rendered.pruned)}", file=sys.stderr)

    if args.out:
        _write_private(Path(args.out), "\0".join(rendered.env_args))
    if args.previous_out:
        _write_private(Path(args.previous_out), "\0".join(previous_env_args(current_app)))
    if args.key_vault_out:
        directory = Path(args.key_vault_out)
        directory.mkdir(mode=0o700, exist_ok=True)
        for name, value in rendered.key_vault.items():
            _write_private(directory / name, value)

    print(
        f"{args.service}: {len(rendered.env_args)} variable(s), {len(rendered.key_vault)} Key Vault secret(s)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ContractError as error:
        # Never let a traceback out: a frame could carry a value.
        print("deploy config rejected:", file=sys.stderr)
        for problem in error.problems:
            print(f"  - {problem}", file=sys.stderr)
        sys.exit(1)
    except (OSError, json.JSONDecodeError, KeyError) as error:
        print(f"deploy config could not be read: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
