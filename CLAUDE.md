# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリの性質

Claude Code 向けの Skill / Prompt / Agent 定義を、[APM](https://github.com/microsoft/apm) と [Agent Skills 仕様](https://agentskills.io/specification) の両方に準拠した形で配布するリポジトリ。中身はほぼ Markdown で、アプリケーションコードもビルドもない。

- `.apm/skills/<name>/SKILL.md`: agent が `description` を見て自動発動する手続き的知識。長いものは `references/*.md` に分割する（progressive disclosure）。補助スクリプトは `references/scripts/` に置く（例: `dev`）
- `.apm/prompts/<name>.prompt.md`: ユーザーが `/<name>` で明示的に呼ぶワンショットのエントリ。frontmatter は Claude Code の slash command と同じ意味を持つ
- `.apm/agents/<name>.agent.md`: Claude Code subagent 互換の frontmatter（`name` / `description` / `tools`）を持つロール定義。`role` 系 skill から呼ばれる
- `apm.yml`: APM マニフェスト（`includes: auto` で `.apm/` 配下を自動収集）

Skill か Prompt かの判定軸は「ユーザーが呼ばなくても agent が自動で参照すべき手続きか」。Yes なら Skill。`dev` / `spec` / `role-debate` のような多段ワークフローも Skill に置く。

## コマンド

```bash
pip install pyyaml               # 検証スクリプトの依存
python3 scripts/validate-skills.py
```

`scripts/validate-skills.py` は `.apm/skills/` の全 skill を一度に検証する（単体指定はない）。CI（`.github/workflows/validate-skills.yml`）も同じスクリプトを走らせ、`.apm/skills/**` の変更で起動する。prompts と agents は検証対象外。

エラー（exit 1）になるのは frontmatter 違反だけ:

- `name`: 必須、kebab-case 小文字、64 字以内、親ディレクトリ名と一致、`anthropic` / `claude` は不可
- `description`: 必須、1024 字以内。`<foo>` のような山括弧は XML タグ扱いの警告が出るので避ける
- `compatibility`: 任意、500 字以内

警告（exit 0）: SKILL.md 本文が 500 行超、`references/*.md` が 500 行超、または 100 行超で `## Contents` 見出しがない。

## 作業上の注意

- APM のコンパイル成果物（`.claude/`、`.cursor/`、`.codex/`、`.github/skills/` など）は `.gitignore` で除外している。
  ルートの `AGENTS.md` と `CLAUDE.md`、`.github/workflows/` は管理対象。
  このリポジトリで `apm install` / `apm compile` を走らせると、`AGENTS.md` と `CLAUDE.md` が生成物で上書きされうるので差分を確認する。
- 多くの skill の実使用版はユーザーのローカル `~/.claude/skills/<name>/` にあり、このリポジトリはそこから同期して公開する運用（例: コミット「Sync /dev skill with the local version」）。同期作業ではローカル版を正として差分を取り込む
- Skill / Prompt / Agent を追加・削除したら README.md の一覧表と件数見出し（「Skills (20)」など）も更新する
- skill 本文は日本語で書かれている。コミットメッセージは英語の命令形
