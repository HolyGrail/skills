# holygrail-skills

HolyGrail がローカルで使っている Claude Code 向けの **Skill / Prompt** を [APM (Agent Package Manager)](https://github.com/microsoft/apm) と [Agent Skills](https://agentskills.io) の双方に準拠した形式で公開するリポジトリ。

ほかの環境や別のユーザーが `apm install` 一行 (もしくは手動コピー) で同じ Skill / Prompt セットを取り込めることを目的にしている。

## 仕様準拠

- **Agent Skills**: `SKILL.md` の frontmatter (`name` / `description`) と命名規則 (kebab-case, ≤64 字, 親ディレクトリ名と一致) を遵守。
- **Microsoft APM**: ソースは `.apm/` 配下に配置。`apm.yml` を Working Draft (v0.1) のスキーマに沿って記述。コンパイル後の `.claude/` などはこのリポジトリでは管理しない (`.gitignore` 済み)。

## Skill と Prompt の使い分け

| 種別 | 配置 | 性質 | 例 |
|---|---|---|---|
| **Skill** | `.apm/skills/<name>/SKILL.md` | タスクに応じて agent が自動発動する手続き的知識・方法論 (progressive disclosure) | `pentest`, `fix-error`, `spec-review` |
| **Prompt** | `.apm/prompts/<name>.prompt.md` | ユーザーが `/<name>` で明示的に呼び出すワンショットのオーケストレーション | `codex`, `screenshot`, `pr-create` |

長大な multi-phase workflow (例: `dev`, `spec`) は **Skill 扱い** にしている。Skill が Claude Code 側で slash command として呼べるかは Claude Code のロード方式次第なので、`~/.claude/commands/` への手動コピーで `/dev` を維持したい場合は本リポジトリの Skill 本文を流用する。

## 収録 Skill / Prompt / Agent

### Skills (20)

`empirical-prompt-tuning` を含む 20 個。

| name | 概要 (description 抜粋) |
|---|---|
| `check-prompt` | AI Agent 向けプロンプトを 6 カテゴリ・100 点満点で評価し改善案を提示 |
| `design-patterns` | GoF パターン提案と SOLID/アンチパターン評価 |
| `dev` | git worktree ベースで Plan → Implement → PR → Cleanup までの開発ワークフロー |
| `empirical-prompt-tuning` | 別エージェントに動かせて両面評価で指示文を反復改善 |
| `fix-error` | エラーの 3 フェーズ根本原因分析 (情報収集 → 5 Whys → 修正) |
| `pentest` | OWASP / CWE Top 25 と照合する攻撃者目線レビュー |
| `plan` | Requirements → Design → Implementation の 3 段階実装計画策定 |
| `pr-review` | 削除・データフロー破壊を含む 5 分類体系的 PR レビュー |
| `refactor` | 段階的リファクタリングと SOLID/コードの臭い評価 |
| `role` / `role-debate` / `role-help` | 専門ロール切替・ロール間討議・ロール選定支援 |
| `semantic-commit` | 大きな変更を意味のある最小単位に分割し Conventional Commits でコミット |
| `spec` | Kiro 式 spec-driven development (requirements/design/tasks) |
| `spec-new` / `spec-interview` / `spec-review` | spec の新規作成 / 深掘り / 曖昧さゼロまでのレビュー |
| `task` | 自律エージェントによる多ソース反復調査 |
| `tech-debt` | 技術的負債の優先度付き改善計画 |
| `ultrathink` | 構造化された MECE 深思考プロセス |

### Prompts (18)

| name | 概要 |
|---|---|
| `analyze-dependencies` | 依存関係分析とアーキテクチャ健全性評価 |
| `analyze-performance` | パフォーマンス問題分析と最適化提案 |
| `check-fact` | コードベース・docs と照合した情報検証 |
| `check-github-ci` | GitHub Actions CI 状況確認 |
| `codex` | Codex MCP へのコード生成委任 |
| `commit-message` | Conventional Commits 準拠のメッセージ生成 |
| `context7` | Context7 MCP でライブラリ最新ドキュメント検索 |
| `explain-code` | 多角的なコード解説 |
| `gemini-search` | Gemini CLI 経由 Web 検索 |
| `pr-auto-update` | PR 説明文・ラベル自動更新 |
| `pr-create` | Draft PR 作成 |
| `pr-feedback` | レビューコメント分類と対応計画 |
| `pr-issue` / `pr-list` | Issue / PR の優先度付き一覧 |
| `screenshot` | macOS スクリーンショット撮影と解析 |
| `show-plan` | 現セッションのプラン表示 |
| `update-doc-string` | 言語別スタイル準拠の docstring 整備 |
| `update-node-deps` | npm 依存関係更新の安全性評価 |

### Agents (8)

`role` / `role-debate` / `role-help` などの skill から呼び出される専門サブエージェント定義。Claude Code subagent 互換 frontmatter (`name` / `description` / `tools`) のまま `.apm/agents/` にフラット配置している。

| name | 概要 (description 抜粋) |
|---|---|
| `analyzer` | 根本原因分析 (5 Whys、システム思考、Evidence-First) |
| `architect` | システム設計 (Evidence-First、MECE、進化的アーキテクチャ) |
| `frontend` | UI/UX (WCAG 2.1、デザインシステム、React/Vue/Angular) |
| `mobile` | モバイル開発 (iOS HIG、Material Design、Touch-First) |
| `performance` | パフォーマンス最適化 (Core Web Vitals、RAIL、ROI) |
| `qa` | テスト戦略 (E2E/統合/単体、自動化、品質メトリクス) |
| `reviewer` | コードレビュー (Evidence-First、Clean Code、公式スタイル) |
| `security` | セキュリティ (OWASP Top 10、CVE、LLM/AI セキュリティ) |

## ディレクトリ構造

```
holygrail-skills/
├── apm.yml                   # APM マニフェスト
├── .apm/                     # ソース (APM 規約)
│   ├── skills/<name>/SKILL.md
│   ├── prompts/<name>.prompt.md
│   └── agents/<name>.agent.md
├── .gitignore                # コンパイル成果物は除外
└── README.md
```

## 利用方法

### A. APM CLI 経由 (推奨)

別プロジェクトの `apm.yml` に追加:

```yaml
dependencies:
  apm:
    - HolyGrail/skills
```

特定の Skill / Prompt だけ取りたい場合 (Primitive form):

```yaml
dependencies:
  apm:
    - HolyGrail/skills/.apm/skills/empirical-prompt-tuning
    - HolyGrail/skills/.apm/prompts/codex.prompt.md
```

その後 `apm install` でコンパイル先 (`.claude/`, `.cursor/`, `.codex/` など) に展開される。

### B. 手動コピー (APM CLI を入れない場合)

```bash
# Skill を Claude Code 個人グローバルに入れる
cp -r .apm/skills/<name> ~/.claude/skills/

# Prompt を Claude Code の slash command として使う
cp .apm/prompts/<name>.prompt.md ~/.claude/commands/<name>.md

# Agent (subagent ロール) を Claude Code に入れる
cp .apm/agents/<name>.agent.md ~/.claude/agents/<name>.md
```

Claude Code は slash command の frontmatter (`description` / `allowed-tools` / `model` 等) を読み取って一覧表示等に活用するため、`.prompt.md` の frontmatter はそのまま意味を持つ。

## 設計判断メモ

### Skill か Prompt かの判定軸

- **Skill**: 「いつ・どう・何をすべきか」の手続き的知識を `description` でトリガーされて agent が自律的にロードする (例: PR レビュー方法論、デバッグ手順、専門ロール切替)
- **Prompt**: ユーザーが `/<name>` で明示呼び出しするワンショットの起動エントリ (例: `/codex` で委任、`/screenshot` で撮影)

判定に迷ったときは「ユーザーがあえて呼ばなくても、agent が自動でこの手続きを参照すべきか」で決める。Yes → Skill, No → Prompt。

### Hybrid (multi-phase workflow) の扱い

`dev` / `spec` / `role-debate` 等の多段ワークフローは Skill 配置にした。理由は本体ロジックが「方法論」であり Prompt より長尺で、agent 側で自律発動できる方が再利用性が高いため。ユーザーが `/dev` 起動エントリを維持したい場合は手動コピー B で `~/.claude/commands/dev.md` を残すのが楽。

### `agents/` (subagent ロール定義) の取り扱い

`~/.claude/agents/roles/` 配下の 8 ロール (analyzer / architect / frontend / mobile / performance / qa / reviewer / security) は `.apm/agents/<name>.agent.md` のフラット配置で取り込み済み。frontmatter は Claude Code subagent 互換 (`name` / `description` / `tools`) をそのまま流用しており、APM コンパイル先 (`.claude/agents/`) と手動コピー両方で同じファイルが使える。

## 既存 skill の見直し結果

`empirical-prompt-tuning` には公開前に下記 3 点の軽微修正を入れた:

1. 収束判定 (連続 2 イテレーション) の AND 条件を明示
2. 失敗時の不明瞭点 1 行フォーマットを `[critical] 項目 N が × — <落ちた理由>` 形式で具体化
3. 「再試行回数」の取得経路 (subagent 自己申告) を「指示側計測」から「自己申告」サブグループへ移動 — 計測カテゴリの整合性を回復

その他、references/ への progressive disclosure 分割や外部 skill 参照 (`superpowers:writing-skills` 等) の任意化は次回イテレーションで検討。

## ライセンス

MIT
