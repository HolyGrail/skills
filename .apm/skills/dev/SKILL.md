---
name: dev
description: |
  git worktree (k1LoW/git-wt) 上にタスク専用環境を作り、Phase 0 (worktree 準備) → Plan → Implement → Verify → Fix → PR → Post-PR Iteration → Cleanup の一貫した開発ワークフローをセッション管理付きで実行する。新規タスクを隔離環境で進めたいとき、`/dev resume` で中断セッションを再開したいとき、`/dev cleanup` でマージ後の worktree とブランチを掃除したいときに使う。
---

# Dev

Plan から PR 作成・後片付けまで一貫した開発ワークフローを、**git worktree 上に隔離して**実行する。`k1LoW/git-wt` (`git wt` サブコマンド) でタスクごとに worktree を作り、計画・実装・検証・PR 作成までその中で完結させる。PR マージ後は `/dev cleanup` で worktree とブランチをまとめて掃除する。

## 使い方

```bash
/dev [タスクの説明]              # 新規タスク (Phase 0〜5 を順次実行)
/dev resume [slug]               # 既存セッション再開 (途中中断 or post-PR モード)
/dev cleanup [branch]            # PR マージ後の後片付け (worktree + ブランチ削除 + followup を issue 化)
```

- 引数なし: 既存セッションがあれば AskUserQuestion で「新規 / 再開 / cleanup」を確認
- `/dev <説明>`: 指定タスクで Phase 0 から開始
- `/dev resume [slug]`: セッション再開。**`status == "pr-open"` のセッションを選ぶと post-PR モード (Phase 5-bis)** に入り、追加修正 + PR 本文更新を行う
- `/dev cleanup`: cwd が worktree ならそのブランチが対象、違えばセッション一覧から選択。**merge 確認後に未着手の `followups[]` を GitHub issue として自動作成**
- **初回のみ**: `wt.copyignored` 等の git-wt 設定を済ませると `.dev.vars` / `.env*` のコピー漏れを防げる ([references/setup.md](references/setup.md) 参照)

## ワークフロー全体像

```
Phase 0: Prepare worktree (新規タスク時のみ)
  ├─ git-wt 前提設定をチェック、未設定なら警告して続行
  ├─ リポジトリ root と default ブランチを検出
  ├─ slug・ブランチ名を自動決定 (衝突時のみ AskUserQuestion)
  ├─ 既存 worktree 再利用 / なければ git-wt で新規作成
  ├─ WT_PATH (絶対パス) を確定
  └─ セッションポインタを ~/.claude/dev-sessions/<slug>.json に保存

Phase 1: Plan        計画策定 → docs/plans/ に保存、ユーザー承認待ち
Phase 2: Implement   計画通りに実装、ADR 記録、最後に /simplify
Phase 3: Verify      型 / lint / テスト / ビルドを自動検出して実行
                     失敗があれば「新規 vs 既存」を別 worktree で切り分け
Phase 4: Fix         新規問題は修正ループ (最大 3 回)、
                     既存問題は AskUserQuestion で対応方針確認
                     (今回 PR / 別 PR / スコープ外)
Phase 5: PR          全検証 PASS 後に Draft PR 作成
                     セッションを status: "pr-open" に更新
Phase 5-bis: Post-PR Iteration  /dev resume で起動。追加修正 + PR 本文更新
Phase 6: Cleanup     /dev cleanup で起動。PR MERGED 確認後、followup を
                     GitHub issue 化、worktree + ブランチ削除
```

## いつどの reference を読むか

- **Phase 0 を実装するとき / git-wt の整合性チェックロジックが必要なとき** → [references/phase-0-worktree.md](references/phase-0-worktree.md)
  - 9 段階の手順、`wt.copyignored` / `wt.copy` の状態判定ルール、ブランチ命名の自動決定、既存 worktree 再利用判定、フォールバック
- **Phase 1-4 (Plan / Implement / Verify / Fix) を実行するとき** → [references/phases-1-4.md](references/phases-1-4.md)
  - 計画インタビュープロセス (3 ステップ・質問の質の基準)、ADR フォーマット、検証コマンド自動検出、別 worktree での新規 vs 既存切り分け、followups[] への記録
- **Phase 5 / Post-PR / Cleanup を実行するとき** → [references/phases-5-6.md](references/phases-5-6.md)
  - PR 説明テンプレート、Post-PR の本文同期更新 (`gh pr edit --body-file`)、Cleanup の followup 自動 issue 化 (重複チェック・ラベル推定・5 件以上で確認)、worktree 削除フォールバック (`-D`)
- **セッションファイルを書くとき / 中断・再開ロジックが必要なとき** → [references/session-management.md](references/session-management.md)
  - JSON スキーマ全フィールド、状態遷移 (`in-progress` → `pr-open` → `cleaned`)、整合性チェック、フェーズスキップ
- **初回セットアップ / Phase 0 の警告に対処するとき** → [references/setup.md](references/setup.md)
  - 必須レベル (`wt.copyignored`)、推奨レベル (`wt.symlink`)、プロジェクト別 (`wt.hook`)、確認コマンド

## Claude が守るべき行動指針

### 全フェーズ共通

1. **各フェーズ開始時に宣言する** — 「Phase N: [名前] を開始します」と明示
2. **フェーズ間で必ず承認を取る** — 次のフェーズに進む前にユーザーの「次に進んで」等を待つ
3. **不明点は必ず AskUserQuestion で確認** — 推測で進めない。確認した設計判断は ADR に記録する (ただし各 Phase で例外が明記されている箇所はそれに従う。例: Phase 0 のブランチ名自動決定)
4. **TaskCreate / TaskUpdate で進捗管理** — 各フェーズ内のステップをタスクとして管理する

## Claude Code 実行環境の絶対条件

以下は本スキルで git 操作を組む際の前提:

1. **Bash 呼び出し間で cwd は保持されない** (`cd` の効果は次の Bash 呼び出しに引き継がれない)。worktree で作業する全コマンドは `cd "$WT_PATH" && ...` を先頭に付けるか、`git -C "$WT_PATH" ...` を使う
2. **zsh の `git wt` シェル統合は Claude Code の bash では効かない**。`git-wt` サブコマンドを直接呼び、worktree パスは `--json` 出力から取得する
3. **worktree パス・リポジトリ root は絶対パスで保持する** (セッションファイルに記録)

## Gotchas

- **`git wt --json <branch>` は list モードでのみ JSON 配列を返す**。作成時 (`git wt <branch> <start-point>`) には付けず、作成後の list で path を引く 2 段階手順を踏む ([phase-0-worktree.md 手順 7](references/phase-0-worktree.md#手順-7-worktree-新規作成))
- **`wt.copyignored=true` は gitignored なファイルだけ対象**。`.dev.vars` が `.gitignore` 未登録だと copy されない。判定ルールは [phase-0-worktree.md 手順 0](references/phase-0-worktree.md#手順-0-git-wt-前提セットアップの自動チェック)
- **検証失敗の切り分けで `git checkout` を使わない**。作業状態を壊すリスクがあるので、必ず別 worktree で再実行 ([phases-1-4.md Phase 3](references/phases-1-4.md#phase-3-verify-検証))
- **Post-PR で PR 本文を `--body-file` で更新する**。`--body ""` は事故のもと。コミット + push だけで終えるとレビュアーから変更履歴が追えなくなる ([phases-5-6.md Phase 5-bis](references/phases-5-6.md#phase-5-bis-post-pr-iteration))
- **`gh issue create` の長文 body は `--body-file` を使う**。shell 展開で改行・引用符がクラッシュする。`issue_url` が既に入っている followup を再作成しない (冪等性違反)
- **PR state が MERGED でない状態で `-D` を勝手に使わない**。明示ユーザー同意のみ
- **未コミット変更を勝手に破棄しない / 実行中プロセスを勝手に kill しない** (警告のみ)

## 注意事項

- **承認前の実装開始は厳禁** — Phase 1 の計画がユーザーに承認されるまで Phase 2 に進まない
- **既存コードの尊重** — 変更箇所以外のコードスタイルやパターンに合わせる
- **コミットは適切な粒度で** — 1 つの論理的変更 = 1 コミットを原則とする
- **main を壊さない** — Phase 5 (PR 作成) 前に全検証 PASS を必須とする。検証失敗を発見したら必ず「新規 vs 既存」を切り分け、既存問題は AskUserQuestion で対応方針を確認する。「main にも同じエラーがあるから無視」は禁止
- **検証失敗のスルー禁止** — 「自分の変更による失敗ではない」と判断しても、ユーザー確認なしに無視して PR を作成しない
- **main リポジトリ側で作業しない** — Phase 0 以降は必ず worktree 内で作業。Read/Write/Edit は `$WT_PATH` 配下の絶対パスを使う
- **cleanup の自動化禁止** — PR マージ確認は `gh pr view --json state` が `MERGED` を返した場合のみ削除。未マージで勝手に `-D` しない

## 実行例

```
# 基本的な使い方 (Phase 0〜5)
/dev ユーザープロフィールページに画像アップロード機能を追加する

# 期待される動作
# Phase 0: worktree 準備 → .wt/feat-profile-image-upload/ 作成
#          → ~/.claude/dev-sessions/profile-image-upload.json 保存
# Phase 1: 計画策定 → $WT_PATH/docs/plans/2026-04-17-profile-image-upload.md 保存
# Phase 2: 実装 (worktree 内、不明点は質問 → ADR 記録)
# Phase 3: 検証 (テスト・lint・型チェック自動実行、失敗は default branch worktree で切り分け)
# Phase 4: 修正 (問題があれば修正ループ)
# Phase 5: Draft PR 作成 → セッションファイルに pr_url 記録

# 途中再開
/dev resume                              # セッション一覧から選択
/dev resume profile-image-upload         # slug 指定

# PR マージ後の後片付け
/dev cleanup                             # cwd が worktree ならそのまま対応
/dev cleanup feat-profile-image-upload   # ブランチ指定
```

## 関連スキル

- `/plan` : 計画策定のみ (Phase 1 相当)
- `/pr-create` : PR 作成のみ (Phase 5 相当)
- `/spec` : 仕様駆動開発 (より大規模な機能向け)
- `/spec-new` : ゼロからの仕様策定
- `/simplify` : Phase 2 の最後に呼ばれるリファクタリング
