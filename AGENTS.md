# Repository Guidelines

## Project Structure & Module Organization

This repository distributes Claude Code skills, prompts, and agent definitions through APM (Agent Package Manager).

- `.apm/skills/<name>/SKILL.md`: skill entry points; supporting material belongs in each skill's `references/` directory.
- `.apm/prompts/<name>.prompt.md`: explicitly invoked prompts.
- `.apm/agents/<name>.agent.md`: specialist agent definitions.
- `apm.yml`: package metadata; `README.md`: catalog, installation, and design decisions.
- `scripts/validate-skills.py`: validator, run by `.github/workflows/validate-skills.yml`.

There are no application assets or dedicated test directories. Edit `.apm/` sources; generated destinations such as `.claude/` and `.codex/` are ignored.

## Build, Test, and Development Commands

Run from the repository root:

```sh
python3 -m pip install pyyaml       # Install the validator dependency
python3 scripts/validate-skills.py  # Validate skills and reference structure
git diff --check                   # Check tracked changes for whitespace errors
```

CI uses Python 3.12. There is no application build or development server. To try the package in a consuming project, add `HolyGrail/skills` to its APM dependencies and run `apm install` there.

## Coding Style & Naming Conventions

Use YAML frontmatter for `SKILL.md`, `*.prompt.md`, and `*.agent.md` entry points. Keep `README.md` and reference documents as ordinary Markdown without frontmatter. Use descriptive headings and fenced command examples. Match the surrounding language and formatting; most instructional content is Japanese. Use two-space YAML indentation and four-space Python indentation. No formatter or general-purpose linter is configured.

Skill names must match their directory, use lowercase kebab-case, and contain at most 64 characters. Supply a nonempty `description` of at most 1,024 characters; describe environment requirements in optional `compatibility` metadata. Keep skill bodies within the recommended 500 lines by moving detail into linked references. References over 100 lines should include `## Contents`.

## Testing Guidelines

Run the validator when changing skills or validation logic. Fix hard errors and review warnings. It checks skill metadata and reference length/contents conventions; it does not execute workflows or validate prompt and agent files. Manually check changed links, examples, and instruction consistency. No unit-test framework, test naming convention, or coverage threshold is configured.

## Commit & Pull Request Guidelines

Follow the observed short, imperative English subjects, such as `Add compatibility frontmatter` or `Split role-debate references`. Keep commits focused on one logical change.

PR descriptions should explain the problem, affected skills or prompts, behavior changes, and validation results. Link related issues when applicable, update the README catalog when entries change, and ensure applicable CI passes. No repository PR template is present.
