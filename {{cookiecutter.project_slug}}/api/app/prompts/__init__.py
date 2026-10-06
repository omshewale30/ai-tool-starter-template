"""Prompt templates, kept as versioned files next to the code that uses them.

Each prompt is a Markdown file in this package (`assistant.md` -> `load_prompt("assistant")`).
Keeping prompts out of route code makes them reviewable in diffs and easy to iterate
on. Use `str.format` placeholders for runtime values and pass them to `render_prompt`.
"""

from __future__ import annotations

from functools import lru_cache
from importlib import resources


@lru_cache
def load_prompt(name: str) -> str:
    return resources.files(__package__).joinpath(f"{name}.md").read_text(encoding="utf-8").strip()


def render_prompt(name: str, **values: str) -> str:
    return load_prompt(name).format(**values)
