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

## スキーマ

```json
{
  "slug": "profile-image-upload",
  "branch": "feat-profile-image-upload",
  "worktree_path": "/abs/path/to/repo/.wt/feat-profile-image-upload",
  "repo_root": "/abs/path/to/repo",
  "default_branch": "main",
  "plan_file": "docs/plans/2026-04-17-profile-image-upload.md",
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
  ]
}
```

### フィールドの意味

- `slug`: タスクの識別子 (kebab-case)
- `branch`: 作成したブランチ名
- `worktree_path`: worktree の絶対パス
- `repo_root`: main リポジトリの絶対パス
- `default_branch`: `origin/HEAD` 由来 (main / master / develop 等)
- `plan_file`: Phase 1 で生成された計画ファイルへのパス (worktree 相対)
- `pr_url`: Phase 5 で作成された PR URL
- `status`: `"in-progress"` / `"pr-open"` / `"cleaned"`
- `created_at`: Phase 0 完了時刻
- `updated_at`: 最終更新時刻 (Phase 5-bis で更新)
- `pr_opened_at`: Phase 5 完了時刻
- `cleaned_at`: Phase 6 完了時刻
- `post_pr_iterations`: Phase 5-bis を回した回数 (任意、運用メトリクス)
- `followups[]`: Phase 4-B で「別 PR」「スコープ外」を選んだ項目。Phase 6 手順 2.5 で issue 化されると `issue_url` が埋まる

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

1. セッションファイルから `WT_PATH` / `BRANCH` / `plan_file` / `pr_url` / `status` / `followups` を復元
2. 整合性チェック (worktree 存在確認)
3. **status による分岐**:
   - `status == "in-progress"`: 計画ファイルのステータスとタスク状態から Phase 2 以降を再開
   - `status == "pr-open"`: **Phase 5-bis (Post-PR Iteration) モードに入る**。`gh pr view` で state を確認し、OPEN なら追加修正フロー、MERGED なら cleanup へ誘導
   - `status == "cleaned"`: 一覧には出さない (既に閉じている)

## フェーズスキップ

ユーザーが明示的に指示した場合、特定フェーズをスキップできる:

- 「計画はスキップして実装から始めて」→ Phase 2 から開始 (Phase 0 は実行)
- 「PR は手動で作るからここまでで」→ Phase 5 をスキップ
- 「検証だけやって」→ Phase 3 のみ実行
- 「worktree は作らなくていい」→ Phase 0 をスキップして従来動作 (セッションファイルも作らない)
