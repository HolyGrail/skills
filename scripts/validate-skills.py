#!/usr/bin/env python3
"""Validate Agent Skills against the official spec (https://agentskills.io/specification).

Checks under .apm/skills/<name>/:
  - SKILL.md frontmatter:
    * name: required, 1-64 chars, lowercase / digits / hyphens only,
      no leading/trailing/consecutive hyphens, must match parent dir,
      no reserved words (anthropic, claude)
    * description: required, 1-1024 chars, non-empty
    * compatibility: optional, max 500 chars
  - SKILL.md body: warn if > 500 lines (Anthropic/agentskills recommendation)
  - references/*.md: warn if any single reference exceeds 500 lines or
    lacks a "## Contents" TOC when over 100 lines

Exit code:
  0 - all checks pass (warnings allowed)
  1 - one or more skills violate hard rules (frontmatter spec)
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "PyYAML is required. Install with `pip install pyyaml`.\n"
    )
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO_ROOT / ".apm" / "skills"

NAME_REGEX = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
RESERVED_NAMES = {"anthropic", "claude"}

MAX_BODY_LINES = 500
MAX_REFERENCE_LINES = 500
TOC_THRESHOLD_LINES = 100
TOC_PATTERN = re.compile(r"^##\s+Contents\b", re.MULTILINE)


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)


def parse_frontmatter(text: str) -> tuple[dict | None, str]:
    """Return (frontmatter_dict, body). frontmatter_dict is None on parse failure."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return None, text
    fm_raw = text[4:end]
    body = text[end + 5 :]
    try:
        data = yaml.safe_load(fm_raw)
    except yaml.YAMLError:
        return None, body
    if not isinstance(data, dict):
        return None, body
    return data, body


def validate_name(name: str, expected: str, report: Report) -> None:
    if not isinstance(name, str):
        report.error(f"name: must be a string, got {type(name).__name__}")
        return
    if not name:
        report.error("name: must be non-empty")
        return
    if len(name) > 64:
        report.error(f"name: max 64 chars (got {len(name)})")
    if not NAME_REGEX.match(name):
        report.error(
            f"name: must be kebab-case lowercase alphanumeric (got {name!r})"
        )
    if name in RESERVED_NAMES:
        report.error(f"name: reserved word not allowed ({name!r})")
    if "<" in name or ">" in name:
        report.error("name: XML tags not allowed")
    if name != expected:
        report.error(
            f"name: must match parent directory (expected {expected!r}, got {name!r})"
        )


def validate_description(desc, report: Report) -> None:
    if desc is None:
        report.error("description: required, missing")
        return
    if not isinstance(desc, str):
        report.error(f"description: must be a string, got {type(desc).__name__}")
        return
    desc = desc.strip()
    if not desc:
        report.error("description: must be non-empty")
        return
    if len(desc) > 1024:
        report.error(f"description: max 1024 chars (got {len(desc)})")
    if "<" in desc and ">" in desc and re.search(r"<[a-zA-Z]", desc):
        report.warn("description: contains characters that may be parsed as XML tags")


def validate_compatibility(compat, report: Report) -> None:
    if compat is None:
        return  # optional
    if not isinstance(compat, str):
        report.error(
            f"compatibility: must be a string, got {type(compat).__name__}"
        )
        return
    if not compat.strip():
        report.error("compatibility: must be non-empty when provided")
        return
    if len(compat) > 500:
        report.error(f"compatibility: max 500 chars (got {len(compat)})")


def validate_body(body: str, skill_name: str, report: Report) -> None:
    line_count = body.count("\n") + (1 if body and not body.endswith("\n") else 0)
    if line_count > MAX_BODY_LINES:
        report.warn(
            f"SKILL.md body: {line_count} lines exceeds the {MAX_BODY_LINES}-line "
            f"recommendation. Consider moving detail into references/."
        )


def validate_reference(path: Path, report: Report) -> None:
    text = path.read_text(encoding="utf-8")
    line_count = text.count("\n") + (1 if text and not text.endswith("\n") else 0)
    rel = path.relative_to(REPO_ROOT)
    if line_count > MAX_REFERENCE_LINES:
        report.warn(
            f"{rel}: {line_count} lines exceeds the {MAX_REFERENCE_LINES}-line "
            f"recommendation. Consider splitting further."
        )
    if line_count > TOC_THRESHOLD_LINES and not TOC_PATTERN.search(text):
        report.warn(
            f"{rel}: {line_count} lines but no '## Contents' TOC. "
            f"Anthropic recommends a TOC for references over {TOC_THRESHOLD_LINES} lines."
        )


def validate_skill(skill_dir: Path) -> Report:
    report = Report()
    skill_name = skill_dir.name
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.is_file():
        report.error(f"SKILL.md missing in {skill_dir}")
        return report

    text = skill_md.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    if fm is None:
        report.error("SKILL.md: cannot parse YAML frontmatter")
        return report

    validate_name(fm.get("name"), skill_name, report)
    validate_description(fm.get("description"), report)
    validate_compatibility(fm.get("compatibility"), report)
    validate_body(body, skill_name, report)

    refs_dir = skill_dir / "references"
    if refs_dir.is_dir():
        for ref_path in sorted(refs_dir.glob("*.md")):
            validate_reference(ref_path, report)

    return report


def main() -> int:
    if not SKILLS_DIR.is_dir():
        sys.stderr.write(f"No skills directory at {SKILLS_DIR}\n")
        return 1

    skills = sorted(p for p in SKILLS_DIR.iterdir() if p.is_dir())
    if not skills:
        sys.stderr.write(f"No skills found under {SKILLS_DIR}\n")
        return 1

    total_errors = 0
    total_warnings = 0
    for skill in skills:
        rep = validate_skill(skill)
        if rep.errors or rep.warnings:
            print(f"\n=== {skill.name} ===")
            for msg in rep.errors:
                print(f"  ERROR: {msg}")
            for msg in rep.warnings:
                print(f"  WARN:  {msg}")
        total_errors += len(rep.errors)
        total_warnings += len(rep.warnings)

    print(
        f"\nChecked {len(skills)} skills. "
        f"{total_errors} error(s), {total_warnings} warning(s)."
    )

    return 1 if total_errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
