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

`pr-open` の間は `review.loop_status` が CI + Codex レビュー対応のサブ状態を持つ (Phase 5 完了時に自動開始。`monitoring` → `ci-fixing` / `responding` → … → `approved` / `converged` / `review-incomplete`)。

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
    "push_rounds": 1,
    "max_push_rounds": 3,
    "ci_fix_rounds": 1,
    "local_review_requested": true,
    "local_review_passes": 3,
    "head_local_review": "clean",
    "codex_review_requested": false,
    "last_push_at": "2026-04-18T09:10:00Z",
    "last_push_commit": "dd02a0b1c2d3e4f5",
    "wait_started_at": "2026-05-30T01:00:00Z",
    "processed_review_ids": [4385874078, 4390706057],
    "processed_comment_ids": [3321551294, 3325242373],
    "rebutted_comment_ids": [],
    "findings": [
      {"id": 3321551294, "round": 1, "severity": "P2", "path": "app/routes/mypage.tsx",
       "title": "削除確認ダイアログの二重送信", "validity": "valid", "disposition": "fixed",
       "evidence": "連打で 2 回 POST されることをテストで再現、修正後は 1 回", "repair": null,
       "sha": "dd02a0b1", "issue_url": null}
    ],
    "total_wait_seconds": 240,
    "escalate_after_seconds": 2400,
    "started_at": "2026-04-18T08:30:00Z",
    "approved_at": "2026-04-18T09:12:00Z",
    "terminal_reason": "approved",
    "timeout_reason": null
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
  - `loop_status`: `null` (未開始) / `"monitoring"` (CI・レビュー待ち) / `"ci-fixing"` (CI FAIL 対応中) / `"responding"` (レビュー指摘対応中) / `"approved"` (CI 全成功 + 👍 検知) / `"converged"` (👍 は無いが head レビュー済みで P1/P2 全件 disposition 済み) / `"review-incomplete"` (利用上限などで head が未レビュー) / `"timeout"` (Codex 未設定リポジトリの CI-only 終端) / `"escalated"` (要ユーザー判断)
  - `rounds`: 受信した Codex レビューの数 (計測用)。旧セッションではこれが上限判定に使われていた
  - `push_rounds` / `max_push_rounds`: 指摘対応で push した回数と上限 (既定 3)。CI 修正だけの push は含めない。**エスカレーションの中で上限を上げない**
  - `ci_fix_rounds`: CI FAIL を修正 push した回数 (運用メトリクス。CI 状態自体は `gh pr checks` で常に最新を取得するため永続化しない)
  - `local_review_requested`: ユーザーがこのタスクでローカル Codex レビューを明示的に求めたか (既定 `false`)。求められた時点で `true` にし、Phase 5 の PR 作成前と Phase 5.5 の push 前は、再開後もこの値だけで掛けるかを決める。`head_local_review` の記録 (1 行修正のラウンドの `cloud-first` など) では変えない
  - `local_review_passes` / `head_local_review`: Phase 5 と 5.5 で掛けたローカル Codex レビューのパス数と、head がローカルレビューを通っているか (`clean` / `unreviewed` / `skipped` / `cloud-first` = 掛けなかった (既定) / `cloud-reviewed` = `unreviewed` だった head を Codex がレビューした)
  - `codex_review_requested`: この PR で `@codex review` を投げたか (1 PR 1 回)
  - `last_push_at` / `last_push_commit`: 最後の push のコミット時刻 (UTC の Z 形式) と sha。`last_push_at` は **baseline-diff の基準**で、これより新しい 👍 とコメントだけをシグナルとみなす (false-approve 防止)。**push のときだけ動かす** ([phase-5.5-review-loop.md 手順 8](phase-5.5-review-loop.md#8-台帳と-baseline-の更新))
  - `wait_started_at`: 最後に実際に push した時刻 (コミット時刻ではない)。待機時間 (`total_wait_seconds`) と、relay モードの時間切れ用タイマーが古いかどうかの基準
  - `processed_review_ids` / `processed_comment_ids`: 対応済み review / comment の id (再 triage 防止)。`processed_review_ids` は `poll-codex-review.sh --processed-reviews` に渡し、ポーリングが返す review から除く
  - `usage_limit`: `{at, head}`。観測した最新の利用上限コメントの時刻と、そのときの PR の head (既定 `null`)。`head` は `poll-codex-review.sh --limit-head` に渡し、上限の前に依頼されて遅れて届いた review を、上限が戻った証拠から外す。ポーリングのたびに、上限コメントの時刻が `at` と違えば更新する ([phase-5.5-review-loop.md](phase-5.5-review-loop.md#使い方))
  - 旧セッションの `last_review_commit` は使わない (head がレビュー済みかはポーリングの `head_review` で判定する)
  - `rebutted_comment_ids`: 反論済み comment の id (Codex が再提起しても新規扱いしない)
  - `findings[]`: 指摘の台帳。`severity` (triage 後の重大度 P1/P2/P3。振る舞いに影響しない P2 を reply-only にしたら P3 にし、元のバッジは `evidence` に書く)、`validity` (`valid` / `excessive` / `wrong`)、`disposition` (`fixed` / `rebutted` / `followup` / `reply-only` / `accepted-risk` / `pending`)、`evidence` (成立確認と検証の要約)、`repair` (修復記録。P1 と並行制御・状態遷移・永続化の P2)、`sha` / `issue_url`。CONVERGED 判定とエスカレーションの一覧表、および事後の集計に使う
  - `total_wait_seconds` / `escalate_after_seconds`: 累積待機秒とエスカレーション閾値 (既定 2400 = 40 分)
  - `started_at` / `approved_at`: 監視開始時刻 / approved 検知時刻
  - `terminal_reason` / `timeout_reason`: 終端の種別 (`approved` / `converged` / `review-incomplete` / `ci-only` / `escalated`) と、review-incomplete の内訳 (`usage-limit` / `error` / `no-head-review`)
  - 旧スキーマ (`max_rounds` があり `push_rounds` や `findings` が無い) のセッションは、無いフィールドを初期値で補って読む

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
     - **`/dev review`** → **Phase 5.5 (CI + Review Loop) の再開**。CI と Codex 自動レビューを能動監視し、CI FAIL 修正とレビュー指摘へのフル自動対応を、終端 (APPROVED / CONVERGED / REVIEW_INCOMPLETE) かエスカレーションまで続ける ([phase-5.5-review-loop.md](phase-5.5-review-loop.md))。`review` フィールドを使う (通常は Phase 5 完了時に自動突入しているため、これは中断からの再入口)
   - `status == "cleaned"`: 一覧には出さない (既に閉じている)

## フェーズスキップ

ユーザーが明示的に指示した場合、特定フェーズをスキップできる:

- 「計画はスキップして実装から始めて」→ Phase 2 から開始 (Phase 0 は実行)
- 「PR は手動で作るからここまでで」→ Phase 5 をスキップ
- 「検証だけやって」→ Phase 3 のみ実行
- 「worktree は作らなくていい」→ Phase 0 をスキップして従来動作 (セッションファイルも作らない)
