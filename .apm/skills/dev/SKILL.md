---
name: dev
description: |
  git worktree (k1LoW/git-wt) 上にタスク専用環境を作り、Phase 0 (worktree 準備) → Plan → Implement → Verify → Fix → PR → Post-PR Iteration → Cleanup の一貫した開発ワークフローをセッション管理付きで実行する。新規タスクを隔離環境で進めたいとき、`/dev resume` で中断セッションを再開したいとき、`/dev cleanup` でマージ後の worktree とブランチを掃除したいときに使う。
compatibility: Requires git, gh CLI, k1LoW/git-wt (`git wt`), and jq
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
Phase 2: Implement   計画通りに実装、ADR 記録、**最後に /simplify を必ず実行**
                     (skip 判断は禁止。差分サイズ・テスト PASS・主観的なリファクタ
                      余地の有無は skip の根拠にならない)
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
  - PR body テンプレート、**Test plan 構築ルール (ローカル検証可能 / 人手必須の分類、Phase 3 で未実行の項目を Phase 5 内で能動的に追加実行、捏造禁止)**、`--body-file` 必須・デフォルトテンプレートフォールバック禁止、Post-PR の本文同期更新 (`gh pr edit --body-file`)、Cleanup の followup 自動 issue 化 (重複チェック・ラベル推定・5 件以上で確認)、worktree 削除フォールバック (`-D`)
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

### Phase 2 完了条件 (exit checklist)

Phase 3 (Verify) に進む前に以下を **全て満たすこと**。1 つでも欠けていたら Phase 2 は未完了:

1. 計画書 (`docs/plans/...`) の実装ステップが全て完了している
2. ADR が必要な設計判断は `docs/adr/...` に記録済み
3. **`/simplify` skill を実行済み** ([phases-1-4.md 手順 7](references/phases-1-4.md#phase-2-implement-実装))
   - **skip 判断は禁止**。差分サイズ・テスト PASS 状況・「リファクタ余地はなさそう」という主観的見立ては skip の根拠にならない
   - リファクタ余地の有無を判定するのは `/simplify` 側の役割。実装直後の自分はその見立てを過小評価する傾向があるため、**機械的に呼ぶ**
   - どうしても skip したい場合は AskUserQuestion でユーザー確認を取る (黙って Phase 3 に進まない)
   - `/simplify` の戻り値が「変更なし」または書き換え承認後にのみ Phase 3 へ進む
   - **所要時間目安**: 小規模変更 (数十行 / typo / 文言修正) なら数十秒〜1 分で「変更なし」が返る。中規模 (100〜200 行) でも書き換え提案ありで 2〜3 分。「急いでいるから skip」は時間効率の観点でも誤判断 (skip 後に PR レビューで指摘される往復コストの方が大きい)

## Claude Code 実行環境の絶対条件

以下は本スキルで git 操作を組む際の前提:

1. **Bash 呼び出し間で cwd は保持されない** (`cd` の効果は次の Bash 呼び出しに引き継がれない)。worktree で作業する全コマンドは `cd "$WT_PATH" && ...` を先頭に付けるか、`git -C "$WT_PATH" ...` を使う
2. **zsh の `git wt` シェル統合は Claude Code の bash では効かない**。`git-wt` サブコマンドを直接呼び、worktree パスは `--json` 出力から取得する
3. **worktree パス・リポジトリ root は絶対パスで保持する** (セッションファイルに記録)

## Gotchas

- **`git wt --json <branch>` は list モードでのみ JSON 配列を返す**。作成時 (`git wt <branch> <start-point>`) には付けず、作成後の list で path を引く 2 段階手順を踏む ([phase-0-worktree.md 手順 7](references/phase-0-worktree.md#手順-7-worktree-新規作成))
- **`wt.copyignored=true` は gitignored なファイルだけ対象**。`.dev.vars` が `.gitignore` 未登録だと copy されない。判定ルールは [phase-0-worktree.md 手順 0](references/phase-0-worktree.md#手順-0-git-wt-前提セットアップの自動チェック)
- **検証失敗の切り分けで `git checkout` を使わない**。作業状態を壊すリスクがあるので、必ず別 worktree で再実行 ([phases-1-4.md Phase 3](references/phases-1-4.md#phase-3-verify-検証))
- **PR 作成・更新は常に `--body-file`**。Phase 5 の初回作成は `gh pr create --body-file`、Phase 5-bis の更新は `gh pr edit --body-file`。`--body ""` は事故のもと、`/pr-create` 経由や Claude Code デフォルトの `## Test plan` プレースホルダにフォールバックすると Phase 3 結果と整合しない PR が出る ([phases-5-6.md Phase 5](references/phases-5-6.md#phase-5-pr-プルリクエスト) / [Phase 5-bis](references/phases-5-6.md#phase-5-bis-post-pr-iteration))
- **Test plan を「未確認のまま PR」にしない**。計画の検証方法のうちローカル検証可能な項目は Phase 5 内で能動的に追加実行してチェック済みにし、`[x]` には実コマンド・実結果を併記する。実行していない項目を `[x]` にしたり、「ロールプレイで PASS」のような擬似結果を本文に書いたりしない (詳細: [phases-5-6.md Test plan 構築ルール](references/phases-5-6.md#test-plan-構築ルール))
- **`gh issue create` の長文 body は `--body-file` を使う**。shell 展開で改行・引用符がクラッシュする。`issue_url` が既に入っている followup を再作成しない (冪等性違反)
- **`--body-file` の指定先は `mktemp` で生成した動的パス**。`/tmp/followup-1.md` のような固定名は別 worktree / 別セッションが同じ `/tmp` を共有しているため、過去に他セッションが書き残した古い内容をそのまま投稿する事故が起こりうる。`BODY=$(mktemp -t followup.XXXXXX)` で取り、使い終わったら `rm -f "$BODY"`
- **`gh issue create` / `gh issue edit --body-file` の直前に書き出し内容を head で検証**。Write tool は `<tool_use_error>File has not been read yet` で拒否されることがあり、エラーを見逃すと意図と異なる中身を投稿してしまう。`head -c 200 "$BODY"` で先頭 200 byte を出力し、想定する書き出し (PR 番号や issue 番号など) が含まれることを目視で確認してから投稿する
- **PR state が MERGED でない状態で `-D` を勝手に使わない**。明示ユーザー同意のみ
- **未コミット変更を勝手に破棄しない / 実行中プロセスを勝手に kill しない** (警告のみ)
- **Phase 2 末尾の `/simplify` を skip しない**。「差分が小さい」「typecheck/test PASS した」「リファクタ余地はなさそう」「ユーザーが急いでいる」は skip の根拠にならない。実装直後の Claude は **typecheck/test PASS の安心感で `/simplify` を機械的に呼ぶことを忘れがち** だが、リファクタ余地の判定主体は `/simplify` 側。実例: 「3 ファイル / 150 行 / 純関数 1 個 / テスト付き」と判断して skip した結果、後で `/simplify` を実行すると Should-fix が 2 件 (コンポーネント抽出・冗長 sort 削除) 検出された。skip 判断ではなく **`/simplify` 呼び出し → 戻り値が "変更なし" を確認** の手順を踏むこと ([SKILL.md Phase 2 完了条件](#phase-2-完了条件-exit-checklist))

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
