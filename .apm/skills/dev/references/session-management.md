# Session Management

`/dev` のタスクごとセッションファイル (`~/.claude/dev-sessions/<slug>.json`) のスキーマと運用。SKILL.md 本体から「セッションファイルを書き出すとき」「中断・再開のロジックが必要なとき」に参照する。

## Contents
- [ファイル構造](#ファイル構造)
- [スキーマ](#スキーマ)
- [整合性チェック](#整合性チェック)
- [中断と再開](#中断と再開)
- [フェーズスキップ](#フェーズスキップ)

## ファイル構造

```
~/.claude/dev-sessions/
├── profile-image-upload.json   # status: "pr-open"     (Phase 5 完了、マージ待ち)
├── auth-refactor.json          # status: "in-progress" (Phase 2 途中)
└── bugfix-typo.json            # status: "cleaned"     (cleanup 済み、監査用に残す)
```

ステータス遷移: `in-progress` → `pr-open` → `cleaned`

`pr-open` の間は `review.loop_status` が CI + Codex レビュー対応のサブ状態を持つ (Phase 5 完了時に自動開始。`monitoring` → `ci-fixing` / `responding` → … → `approved`)。

## スキーマ

```json
{
  "slug": "profile-image-upload",
  "branch": "feat-profile-image-upload",
  "worktree_path": "/abs/path/to/repo/.wt/feat-profile-image-upload",
  "repo_root": "/abs/path/to/repo",
  "default_branch": "main",
  "plan_issue": "https://github.com/org/repo/issues/120",
  "pr_url": "https://github.com/org/repo/pull/123",
  "status": "pr-open",
  "created_at": "2026-04-17T10:00:00Z",
  "updated_at": "2026-04-18T09:15:00Z",
  "pr_opened_at": "2026-04-17T15:30:00Z",
  "cleaned_at": null,
  "post_pr_iterations": 1,
  "followups": [
    {
      "title": "main にも存在する型エラー (mypage.test.ts) を修正",
      "body": "PR #131 で混入した型エラーが mypage.test.ts line 42, 58 に残存。本 PR のスコープ外として持ち越し。",
      "decision": "separate-pr",
      "source": {
        "kind": "existing-verification-failure",
        "command": "npm test",
        "files": ["mypage.test.ts"]
      },
      "created_at": "2026-04-17T14:22:00Z",
      "issue_url": null
    }
  ],
  "review": {
    "loop_status": "approved",
    "rounds": 2,
    "max_rounds": 5,
    "ci_fix_rounds": 1,
    "last_push_at": "2026-04-18T09:10:00Z",
    "last_push_commit": "dd02a0b1c2d3e4f5",
    "processed_review_ids": [4385874078, 4390706057],
    "processed_comment_ids": [3321551294, 3325242373],
    "rebutted_comment_ids": [],
    "total_wait_seconds": 240,
    "escalate_after_seconds": 2400,
    "started_at": "2026-04-18T08:30:00Z",
    "approved_at": "2026-04-18T09:12:00Z"
  }
}
```

### フィールドの意味

- `slug`: タスクの識別子 (kebab-case)
- `branch`: 作成したブランチ名
- `worktree_path`: worktree の絶対パス
- `repo_root`: main リポジトリの絶対パス
- `default_branch`: `origin/HEAD` 由来 (main / master / develop 等)
- `plan_issue`: Phase 1 で作成 (issue 起動時は採用) された計画 issue の URL
  - **旧スキーマ互換**: 過去のセッションには `plan_issue` の代わりに `plan_file` (計画ファイルの worktree 相対パス) を持つものがある。resume 時に `plan_file` を見つけたら、そのファイルを計画書として従来どおり扱う (issue への移行は不要)
- `pr_url`: Phase 5 で作成された PR URL
- `status`: `"in-progress"` / `"pr-open"` / `"cleaned"`
- `created_at`: Phase 0 完了時刻
- `updated_at`: 最終更新時刻 (Phase 5-bis で更新)
- `pr_opened_at`: Phase 5 完了時刻
- `cleaned_at`: Phase 6 完了時刻
- `post_pr_iterations`: Phase 5-bis を回した回数 (任意、運用メトリクス)
- `followups[]`: Phase 4-B で「別 PR」「スコープ外」を選んだ項目。Phase 6 手順 2.5 で issue 化されると `issue_url` が埋まる
- `review`: **Phase 5.5 (CI + Review Loop) の状態**。Phase 5 完了時に自動初期化され、中断後は `/dev review` で再開する。中断再開を冪等にするための追跡情報 (詳細は [phase-5.5-review-loop.md](phase-5.5-review-loop.md))
  - `loop_status`: `null` (未開始) / `"monitoring"` (CI・レビュー待ち) / `"ci-fixing"` (CI FAIL 対応中) / `"responding"` (レビュー指摘対応中) / `"approved"` (CI 全成功 + 👍 検知) / `"timeout"` (latency 超過。Codex 未設定リポジトリの CI-only 終端もこれ) / `"escalated"` (要ユーザー判断)
  - `rounds` / `max_rounds`: 回したレビュー対応ラウンド数と上限 (既定 5)
  - `ci_fix_rounds`: CI FAIL を修正 push した回数 (運用メトリクス。CI 状態自体は `gh pr checks` で常に最新を取得するため永続化しない)
  - `last_push_at` / `last_push_commit`: **baseline-diff の基準**。これより新しい Codex イベントだけをシグナルとみなす (false-approve 防止)
  - `processed_review_ids` / `processed_comment_ids`: 対応済み review / comment の id (再 triage 防止)
  - `rebutted_comment_ids`: 反論済み comment の id (Codex が再提起しても新規扱いしない)
  - `total_wait_seconds` / `escalate_after_seconds`: 累積待機秒とエスカレーション閾値 (既定 2400 = 40 分)
  - `started_at` / `approved_at`: 監視開始時刻 / approved 検知時刻

## 整合性チェック

セッションファイル読み込み時に以下を確認し、不整合があれば AskUserQuestion で対処:

- `worktree_path` が存在するか (削除されていたらセッションを invalidate)
- `repo_root` が git リポジトリか
- `branch` がリモートに存在するか

## 中断と再開

### 中断時の状態

`~/.claude/dev-sessions/<slug>.json` と worktree がそのまま残る。

### 再開方法

- `/dev resume` — セッション一覧から選択 (`status != "cleaned"` のみ列挙)
- `/dev resume <slug>` — slug 指定
- `/dev` 引数なしで起動 → 既存セッションがあれば AskUserQuestion で「新規 / 再開 / cleanup」を選ばせる

### 再開時の動作

1. セッションファイルから `WT_PATH` / `BRANCH` / `plan_issue` (旧セッションは `plan_file`) / `pr_url` / `status` / `followups` を復元
2. 整合性チェック (worktree 存在確認)
3. **status による分岐**:
   - `status == "in-progress"`: 計画 issue の本文 (ステータス行・実装ステップ) とタスク状態から Phase 2 以降を再開し、**そのまま Phase 5.5 の終端まで自走する** (`gh issue view <番号> --json body` で取得)
   - `status == "pr-open"`: 起動コマンドで分岐する。`gh pr view` で state を確認し、MERGED なら cleanup へ誘導
     - **`/dev resume`** → **Phase 5-bis (Post-PR Iteration)**。人手主導の追加修正 + PR 本文同期 ([phases-5-6.md](phases-5-6.md#phase-5-bis-post-pr-iteration))。push 後は Phase 5.5 のループに戻る
     - **`/dev review`** → **Phase 5.5 (CI + Review Loop) の再開**。CI と Codex 自動レビューを能動監視し、CI FAIL 修正とレビュー指摘へのフル自動対応を CI 全成功 + approved まで続ける ([phase-5.5-review-loop.md](phase-5.5-review-loop.md))。`review` フィールドを使う (通常は Phase 5 完了時に自動突入しているため、これは中断からの再入口)
   - `status == "cleaned"`: 一覧には出さない (既に閉じている)

## フェーズスキップ

ユーザーが明示的に指示した場合、特定フェーズをスキップできる:

- 「計画はスキップして実装から始めて」→ Phase 2 から開始 (Phase 0 は実行)
- 「PR は手動で作るからここまでで」→ Phase 5 をスキップ
- 「検証だけやって」→ Phase 3 のみ実行
- 「worktree は作らなくていい」→ Phase 0 をスキップして従来動作 (セッションファイルも作らない)
