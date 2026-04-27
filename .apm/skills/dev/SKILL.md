---
name: dev
description: |
  git worktree (k1LoW/git-wt) 上にタスク専用環境を作り、Phase 0 (worktree 準備) → Plan → Implement → Verify → Fix → PR → Post-PR Iteration → Cleanup の一貫した開発ワークフローをセッション管理付きで実行する。新規タスクを隔離環境で進めたいとき、`/dev resume` で中断セッションを再開したいとき、`/dev cleanup` でマージ後の worktree とブランチを掃除したいときに使う。
---

## Dev

Plan から PR 作成まで一貫した開発ワークフローを、**git worktree 上に隔離して**実行する。`k1LoW/git-wt` (`git wt` サブコマンド) でタスクごとに worktree を作り、計画・実装・検証・PR 作成までその中で完結させる。PR マージ後は `/dev cleanup` で worktree とブランチをまとめて掃除する。

### 使い方

```bash
# 新規タスク開始（Phase 0〜5 を順次実行）
/dev [タスクの説明]

# 既存セッションの再開（途中中断した /dev を続行）
/dev resume [slug]

# PR マージ後の後片付け（worktree とブランチを削除）
/dev cleanup [branch]
```

- 引数なし: 既存セッションがあれば AskUserQuestion で「新規 / 再開 / cleanup」を確認
- `/dev <説明>`: 指定タスクで Phase 0 から開始
- `/dev resume [slug]`: セッション再開。**`status == "pr-open"` のセッションを選ぶと post-PR モード（Phase 5-bis）**に入り、追加修正 + PR 本文更新を行う
- `/dev cleanup`: cwd が worktree ならそのブランチが対象、違えばセッション一覧から選択。**merge 確認後に未着手の `followups[]` を GitHub issue として自動作成**（Phase 6 手順 2.5）
- **初回のみ**: 末尾「前提セットアップ」節の git-wt 設定（`wt.copyignored` 等）を済ませておくと `.dev.vars` / `.env*` のコピー漏れを防げる

### Claude Code 実行環境の前提（重要）

以下は本スキルで git 操作を組む際の絶対条件:

1. **Bash 呼び出し間で cwd は保持されない**（`cd` の効果は次の Bash 呼び出しに引き継がれない）。worktree で作業する全コマンドは `cd "$WT_PATH" && ...` を先頭に付けるか、`git -C "$WT_PATH" ...` を使う
2. **zsh の `git wt` シェル統合は Claude Code の bash では効かない**。`git-wt` サブコマンドを直接呼び、worktree パスは `--json` 出力から取得する
3. **worktree パス・リポジトリ root は絶対パスで保持する**（セッションファイルに記録）

### ワークフロー全体像

```
Phase 0: Prepare worktree（新規タスク時のみ）
  ├─ git-wt 前提設定（wt.copyignored / wt.copy 等）をチェック、未設定なら警告して続行
  ├─ リポジトリ root と default ブランチを検出
  ├─ タスクから slug・ブランチ名を自動決定（衝突時のみ AskUserQuestion）
  ├─ 既存 worktree があれば再利用、なければ git-wt で新規作成
  ├─ WT_PATH（worktree 絶対パス）を確定
  └─ セッションポインタを ~/.claude/dev-sessions/<slug>.json に保存

Phase 1: Plan（計画）
  ├─ /plan スキルの手順で実装計画を策定
  ├─ 曖昧な点・複数候補がある点は AskUserQuestion で確認
  ├─ 重大な設計判断は ADR に記録
  ├─ 計画を $WT_PATH/docs/plans/ に保存（PR に含まれる）
  └─ ユーザー承認を待機

Phase 2: Implement（実装）
  ├─ 計画に基づいてタスクを順次実行（全て worktree 内で）
  ├─ 不明点は AskUserQuestion で確認 → ADR 記録
  ├─ 各タスク完了時に進捗報告
  └─ 全実装完了後、/simplify スキルで変更コードを整理

Phase 3: Verify（検証）
  ├─ プロジェクトの検証コマンドを自動検出・実行（worktree 内で）
  ├─ 型チェック・lint・テスト・ビルド
  ├─ 失敗があれば「新規 vs 既存」を切り分け
  │   （default branch の別 worktree で再実行 — stash トリック不要）
  └─ 結果をサマリーで報告（種別を明示）

Phase 4: Fix（修正）
  ├─ 新規問題: 修正 → 再検証ループ（最大 3 回）
  ├─ 既存問題: AskUserQuestion で対応方針を確認
  │   ├─ 今回 PR で修正 → 修正 → 再検証
  │   ├─ 別 PR で対応 → PR 説明に明記
  │   └─ スコープ外 → PR 説明に明記
  └─ 全 PASS or 既存問題が明示対応済みになったら次へ

Phase 5: PR（プルリクエスト）
  ├─ 前提条件: 全検証 PASS（既存問題は別 PR/スコープ外で明示対応済みも可）
  ├─ /pr-create の手順で PR を作成（コマンドは worktree 内で実行）
  ├─ 計画・ADR へのリンクを PR 説明に含める
  ├─ Draft PR として作成
  └─ セッションファイルに pr_url を記録、status を "pr-open" に更新

Phase 5-bis: Post-PR Iteration（`/dev resume` で PR open 中の追加修正）
  ├─ 追加修正を実装 + Phase 3/4 再検証
  ├─ 追加コミット + push（PR のコミットは自動追従）
  ├─ PR 本文を再生成して gh pr edit --body-file で同期更新
  └─ セッションファイルの updated_at / followups を更新

Phase 6: Cleanup（`/dev cleanup` で個別に起動）
  ├─ gh pr view で PR state == MERGED を確認
  ├─ followups[] を GitHub issue として自動作成（重複チェック + ラベル推定）
  ├─ worktree に未コミット変更がないことを確認
  ├─ 実行中プロセスを警告（自動 kill はしない）
  ├─ git wt -d <branch> で worktree + ブランチを削除
  │   （squash/rebase 由来の safe-delete 拒否時は確認の上で -D にフォールバック）
  └─ セッションファイルを status: "cleaned" に更新（followups[].issue_url も保存）
```

### Claude が守るべき行動指針

#### 全フェーズ共通

1. **各フェーズ開始時に宣言する** — 「Phase N: [名前] を開始します」と明示
2. **フェーズ間で必ず承認を取る** — 次のフェーズに進む前にユーザーの「次に進んで」等を待つ
3. **不明点は必ず AskUserQuestion で確認** — 推測で進めない。確認した設計判断は ADR に記録する（ただし各 Phase で例外が明記されている箇所はそれに従う。例: Phase 0 手順 4 のブランチ名自動決定）
4. **TaskCreate/TaskUpdate で進捗管理** — 各フェーズ内のステップをタスクとして管理する

#### Phase 0: Prepare worktree（worktree 準備）

**目的**: タスク専用の git worktree を作成し、以後全ての作業をその中で隔離して進める。

以下の手順は **main リポジトリの作業ディレクトリから** 開始する前提。既に worktree 内から `/dev` を起動した場合は「既存 worktree 再利用」フローに分岐する。

**手順**:

0. **git-wt 前提セットアップの自動チェック**（毎回実行、セットアップ漏れ防止）

   worktree 作成で `.dev.vars` / `.env*` のコピー忘れを防ぐには、**設定と対象ファイルの状態を両面で検査**する必要がある。`wt.copyignored=true` は gitignored なファイルしか対象にしないため、`.dev.vars` が `.gitignore` に載っていない（untracked 扱い）と copy されない点に注意。

   **実行タイミング**: 本手順は `REPO_ROOT` に依存するので **手順 1（REPO_ROOT 取得）の直後に実行する**。見出し番号は "0" だが、これは「セットアップ漏れ防止の責務」を他手順から分離するためのもので、実装順は 1 → 0 → 2 でよい。

   ```bash
   # 設定の検出（git config --get-all は改行区切りなので readarray で配列化）
   COPYIGNORED=$(git config --get wt.copyignored 2>/dev/null)
   COPYUNTRACKED=$(git config --get wt.copyuntracked 2>/dev/null)
   readarray -t COPY_PATTERNS < <(git config --get-all wt.copy 2>/dev/null)

   # 対象ファイルを untracked / ignored に限定して列挙（tracked は git-wt 既定で copy されるので不要）
   # `-z` 区切りでファイル名に空白等が含まれても安全に扱う
   readarray -d '' -t UNTRACKED_ENV < <(git -C "$REPO_ROOT" ls-files -z --others --exclude-standard -- '.dev.vars' '.env*' '.envrc' 2>/dev/null)
   readarray -d '' -t IGNORED_ENV   < <(git -C "$REPO_ROOT" ls-files -z --others --ignored --exclude-standard -- '.dev.vars' '.env*' '.envrc' 2>/dev/null)
   ```

   **判定ルール**（対象ファイルが存在する場合のみ適用。存在しなければ検査スキップ）:

   | 対象ファイルの git 上の状態 | copy が保証される条件 |
   |----------------------------|----------------------|
   | `IGNORED_ENV` にある（gitignored） | `COPYIGNORED=true` |
   | `UNTRACKED_ENV` にある（gitignore にも未登録） | `COPYUNTRACKED=true` **または** `COPY_PATTERNS` の各要素が `case "$f" in $pat)` 相当の **fnmatch（glob）で一致** |
   | tracked（`git ls-files` で検出） | 常に copy される（git-wt 既定動作、検査不要） |

   `wt.symlink` は `node_modules/` / `.venv/` など大型ディレクトリ共有用で、env ファイルコピー判定には無関係。本表の対象外（前提セットアップ節で別途推奨）。

   判定手順:
   1. `IGNORED_ENV` も `UNTRACKED_ENV` も空なら **OK**（検査対象なし）
   2. `IGNORED_ENV` のファイルは `COPYIGNORED=true` なら OK
   3. `UNTRACKED_ENV` のファイルは `COPYUNTRACKED=true` なら OK。または `for p in "${COPY_PATTERNS[@]}"; do case "$f" in $p) matched=1;; esac; done` で一致すれば OK
   4. 上記いずれでも OK にならないファイルがあれば **警告して続行**:

      ```
      警告: git-wt の設定では以下のファイルが新規 worktree に copy されません:
        - .dev.vars  (untracked、wt.copyuntracked 未設定、wt.copy に未登録)

      推奨セットアップ（いずれか 1 つ）:
        git config --global wt.copyignored true       # .gitignore に .dev.vars を追加する前提
        git config --global wt.copyuntracked true     # untracked も copy（範囲広め）
        git config --global --add wt.copy ".dev.vars" # このファイルだけ明示的に copy

      詳細は dev.md 末尾の「前提セットアップ」節を参照。今回はこのまま続行します。
      ```

   - セットアップを今すぐ入れるかどうかは**聞かない**（作業中断を避ける）。ユーザー側で後から設定する

1. **リポジトリ判定と root 取得**
   ```bash
   REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
   ```
   取れなかった場合は git 管理外。AskUserQuestion で「worktree なしで従来動作に戻す / 中止」を確認する。

2. **既に worktree 内か判定**（起動場所チェック）

   **注**: `REPO_ROOT` は現在 cwd から `git rev-parse --show-toplevel` で取ったものなので、既に worktree 内から起動した場合は **worktree のパス** になっている（変数名は便宜上 REPO_ROOT のまま使う）。main リポジトリと worktree の判別は `git-dir` と `git-common-dir` の比較で行う:

   ```bash
   # --absolute-git-dir で symlink 解決済みの絶対パスを取る
   GIT_DIR=$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)
   COMMON_DIR_REL=$(git -C "$REPO_ROOT" rev-parse --git-common-dir)
   # COMMON_DIR が相対パスの場合があるので GIT_DIR 基準で絶対化
   COMMON_DIR=$(cd "$(dirname "$GIT_DIR")" && cd "$COMMON_DIR_REL" 2>/dev/null && pwd || echo "$COMMON_DIR_REL")
   ```

   `GIT_DIR != COMMON_DIR` なら既に worktree 内。その場合 `WT_PATH="$REPO_ROOT"` として Phase 0 の以降の作成手順はスキップし、手順 8 のセッション登録だけ行う。また、main リポジトリの絶対パスが必要な場合は `dirname "$COMMON_DIR"` で取れる（通常 `<main-repo>/.git` の親）。

3. **default ブランチ検出**
   ```bash
   DEFAULT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
   ```

4. **slug とブランチ名の自動決定**（原則ユーザー確認なし）
   - タスク説明から英語ケバブケース slug を自動生成（例: `profile-image-upload`）
   - 接頭辞はタスク説明から判定（追加/新機能 → `feat-`、修正 → `fix-`、リファクタ → `refactor-`、雑務 → `chore-`、ドキュメント → `docs-`）
   - プロジェクト慣習があれば `git -C "$REPO_ROOT" branch -a | head -30` を見て既存命名パターンに寄せる（例: `feature/` / `bugfix/` が多数派ならそれに従う）
   - **AskUserQuestion は原則使わない**。以下の例外のみ確認する:
     - ローカル/リモートで同名ブランチが既に存在し、再利用 (Phase 0 手順 6) に該当しない
     - タスク説明が極端に短く（20 文字未満など）slug が意味のある英単語にならない
   - 例外時は候補 2〜3 つを提示し、ユーザーが簡単に別名を入力できるようにする

5. **origin を fetch**
   ```bash
   git -C "$REPO_ROOT" fetch origin "$DEFAULT_BRANCH"
   ```

6. **既存 worktree の再利用チェック**
   ```bash
   EXISTING=$(git -C "$REPO_ROOT" wt --json \
     | jq -r --arg b "$BRANCH" '.[] | select(.branch == $b) | .path')
   ```
   `EXISTING` が空でなければ `WT_PATH="$EXISTING"` として再利用し、手順 7 はスキップ。

7. **worktree 新規作成**（git-wt で作成、シェル統合に依存せず `--nocd` でパスのみ出力させる）

   **注意**: `git wt --json <branch>` は **list モードでのみ** JSON 配列を返す。作成時 (`git wt <branch> <start-point>`) は `--nocd` を付けると最終行にプレーンパスを出力するが、フォーマットはバージョン依存。最も安全な手順は「作成 → list でパスを引く」の 2 段階:

   ```bash
   # 作成（stdout/stderr に informational な出力あり。終了コード 0 を確認）
   git -C "$REPO_ROOT" wt --nocd "$BRANCH" "origin/$DEFAULT_BRANCH"

   # パス取得（list 出力は JSON 配列で安定）
   WT_PATH=$(git -C "$REPO_ROOT" wt --json \
     | jq -r --arg b "$BRANCH" '.[] | select(.branch == $b) | .path')
   ```

   `WT_PATH` が空の場合は作成失敗なのでエラー扱い。絶対パスが返る。

   **basedir の .gitignore チェック**: `wt.basedir` の設定値を `git -C "$REPO_ROOT" config --get wt.basedir` で取得（未設定なら `.wt`）。その basedir がリポジトリ内に解決される場合のみ `.gitignore` にエントリがあるか確認し、なければ警告して追加を促す（自動編集はしない）。`../{gitroot}-wt` のようにリポジトリ外なら .gitignore チェックは不要。

8. **セッションポインタ保存**

   `~/.claude/dev-sessions/<slug>.json` に以下を書き出す:

   ```json
   {
     "slug": "profile-image-upload",
     "branch": "feat-profile-image-upload",
     "worktree_path": "/abs/path/to/repo/.wt/feat-profile-image-upload",
     "repo_root": "/abs/path/to/repo",
     "default_branch": "main",
     "plan_file": null,
     "pr_url": null,
     "status": "in-progress",
     "created_at": "<ISO 8601 now>"
   }
   ```

   `plan_file` は Phase 1 終了時に更新、`pr_url` / `status: "pr-open"` は Phase 5 終了時に更新する。

9. **以後の全 Bash 呼び出しで worktree 絶対パスを使う**
   - `cd "$WT_PATH" && <コマンド>` を基本形にする
   - 単発の git 操作は `git -C "$WT_PATH" <コマンド>` でも可
   - **`cd` 単体コマンドは意味がない**（次の呼び出しに cwd は引き継がれない）

**AskUserQuestion の例（衝突・命名不能の例外時のみ）**:

```
質問: ブランチ `feat-profile-image-upload` は既に別作業で使われています

選択肢:
  A. feat-profile-image-upload-v2
     末尾に連番を付与
  B. feat-profile-avatar-upload
     意味的に近い別名
  C. 別名を指定する
     ユーザー入力
```

**フォールバック**: リポジトリでない / git-wt コマンド未検出 / worktree 作成失敗時は、AskUserQuestion で「従来動作（worktree なし）で続行 / 中止」を選ばせる。

#### Phase 1: Plan（計画）

**目的**: 実装の全体像を明確にし、`$WT_PATH/docs/plans/` に保存する

**注意**: Phase 0 以降の全コマンドは `cd "$WT_PATH" && ...` または `git -C "$WT_PATH" ...` を使うこと。計画ファイルも worktree 内に保存され、PR と一緒にコミットされる。

1. タスクの説明を分析し、影響範囲を特定する
2. 既存のコードベースを調査して現状を把握する（Agent ツールで Explore）
3. **曖昧な点・複数候補がある点は AskUserQuestion で確認する**（後述の「計画時の質問ガイドライン」参照）
4. 実装計画を策定する（以下を含む）:
   - **目的**: 何を実現するか
   - **スコープ**: 変更対象のファイル・モジュール
   - **実装ステップ**: 番号付きの具体的な作業手順
   - **検証方法**: どう正しさを確認するか
   - **リスク**: 注意すべき点
   - **設計判断**: AskUserQuestion で確認した判断とその根拠
5. 計画ファイルを保存する:
   - パス: `docs/plans/{YYYY-MM-DD}-{slug}.md`
   - slug はタスク内容から英語のケバブケースで自動生成
6. 計画をユーザーに提示し、承認を待つ

**計画時のインタビュープロセス**:

コードベース調査後、計画を確定する前に以下のインタビュープロセスを実行する。

**Step 1: 分析と質問点の特定**

コードベース調査で得た情報を元に、以下の観点で曖昧・未確定な箇所を洗い出す:
- 技術的決定が未確定な箇所（アプローチが複数存在）
- 競合するパターンや慣習がコードベース内に混在している箇所
- エラーケース・エッジケースの扱いが不明な箇所
- スコープの境界が曖昧な箇所（どこまで変更するか）
- パフォーマンス・セキュリティ・互換性のトレードオフがある箇所

**Step 2: AskUserQuestion による深掘りインタビュー（ループ）**

特定した質問点について、**各ラウンド 2〜4 問**を AskUserQuestion で提示する。回答を受けて次のラウンドに進み、計画に必要な情報が揃うまで繰り返す。

必要に応じて確認すべきカテゴリ（タスクに関連するもののみ）:

- **実装アプローチ**: 複数パターンのトレードオフ比較、既存コードとの整合性
- **スコープ判断**: 変更範囲の境界、関連する変更を含めるか分離するか
- **技術選定**: ライブラリ・フレームワーク・パターンの選択
- **データ設計**: スキーマ構造、API インターフェース、型定義
- **エラー・失敗シナリオ**: 異常系の挙動、リトライ戦略、フォールバック
- **パフォーマンス要件**: レイテンシ閾値、キャッシュ戦略、最適化の優先度
- **互換性・破壊的変更**: 後方互換の要否、マイグレーション戦略
- **テスト戦略**: テストの粒度と範囲、検証の優先順位

**Step 3: 完了判定**

以下を全て満たしたらインタビュー完了:
- [ ] 実装アプローチが 1 つに確定した
- [ ] スコープの境界が明確になった
- [ ] 主要なエッジケースの扱いが決まった
- [ ] 残る曖昧さが計画に影響しない程度に軽微である

**質問の質の基準**:

✅ **良い質問**（計画の精度を上げる）:
- 「A と B のアプローチを比較したとき、[具体的トレードオフ] を考慮するとどちらを優先しますか？」
- 「既存コードに X 方式と Y 方式が混在しています。今回は [具体的な影響] を踏まえてどちらに揃えますか？」
- 「X の変更に伴い Y も修正すると [メリット] がありますが、スコープが広がります。含めますか？」
- 「この処理が失敗した場合、[選択肢 A: リトライ] と [選択肢 B: エラー通知] のどちらが適切ですか？」
- 「MVP として最初に外すべき機能はどれですか？」
- 「実装で一番リスクが高いと感じている部分はどこですか？」

❌ **悪い質問**（禁止）:
- 「この機能の目的は何ですか？」（タスク説明に書いてある）
- 「どの言語で実装しますか？」（プロジェクトから自明）
- 「テストは書きますか？」（当然書く）
- 「コードレビューは必要ですか？」（ワークフロー外の質問）
- コードベースや設定ファイルを読めば分かること

**AskUserQuestion の使い方**:
- 選択肢は「具体的な技術名・数値・設計パターン」を提示する
- 各選択肢の description に**トレードオフを簡潔に明記**する（メリット・デメリットなしの選択肢は出さない）
- 前の回答を踏まえて follow-up する。回答で新たな選択肢が生まれたら追加ラウンドで深掘りする
- 計画に重大な影響を与える判断は、Phase 1 の時点でも **ADR に記録**する

**計画ファイルのフォーマット**:

```markdown
# {タスクタイトル}

- **日付**: {YYYY-MM-DD}
- **ステータス**: in-progress | completed | abandoned

## 目的

{何を実現するか}

## スコープ

{変更対象のファイル・モジュール一覧}

## 実装ステップ

1. {ステップ 1}
2. {ステップ 2}
...

## 検証方法

- {検証項目 1}
- {検証項目 2}

## リスク

- {リスク 1}

## 設計判断

{計画策定時のインタビューで確定した判断。各判断に根拠を付記}

- {判断 1}: {選択内容} — {根拠}
- {判断 2}: {選択内容} — {根拠}

## ADR

{設計判断のうち重大なものは ADR として記録。リンク一覧}

## 結果

{完了後に記入。初期状態は空}
```

#### Phase 2: Implement（実装）

**目的**: 計画に基づいてコードを実装する

**注意**: 全てのファイル操作・コマンド実行は worktree (`$WT_PATH`) 内で行う。Read/Write/Edit ツールは絶対パスを使い、Bash は `cd "$WT_PATH" && ...` を先頭に付ける。

1. 計画の実装ステップを TaskCreate でタスク化する
2. 各ステップを順次実行する
3. **設計判断が必要な場面では必ず AskUserQuestion を使う**:
   - 複数のアプローチがあり、計画で明示されていない場合
   - トレードオフがある技術的選択
   - 仕様の解釈に曖昧さがある場合
4. AskUserQuestion の結果は ADR として記録する:
   - パス: `docs/adr/{NNNN}-{slug}.md`
   - NNNN は連番（既存 ADR の最大番号 + 1、なければ 0001）
5. 計画ファイルの ADR セクションにリンクを追加する
6. 各タスク完了時に TaskUpdate で更新する
7. **全実装タスクが完了したら、最後に `/simplify` スキルを実行する**:
   - 対象: 今回の変更で追加・修正されたコード
   - 目的: 再利用性・品質・効率の観点で整理し、冗長な記述や重複ロジックを解消
   - simplify による書き換えが発生した場合は、差分をユーザーに提示して承認を取る
   - 承認後に Phase 3 (Verify) へ進む（simplify の書き換えは Verify で回帰検出する）
   - 書き換えが設計判断レベルの内容を含む場合は ADR に追記する

**ADR ファイルのフォーマット**:

```markdown
# ADR-{NNNN}: {タイトル}

- **日付**: {YYYY-MM-DD}
- **ステータス**: accepted
- **関連計画**: {計画ファイルへの相対パス}

## コンテキスト

{なぜこの判断が必要になったか}

## 選択肢

### 選択肢 A: {名前}

{説明、メリット・デメリット}

### 選択肢 B: {名前}

{説明、メリット・デメリット}

## 決定

{選ばれた選択肢とその理由}

## 影響

{この決定がもたらす影響}
```

**ADR を残すべき場面**:
- アーキテクチャやデータ構造の設計選択
- ライブラリ・フレームワークの選定
- パフォーマンスとリーダビリティのトレードオフ
- 命名規約やパターンの決定
- スコープの削減・拡張の判断

**ADR を残さなくてよい場面**:
- 変数名の確認など軽微な質問
- 既にプロジェクトの規約で決まっていること
- 一時的な回避策で後から消えるもの

#### Phase 3: Verify（検証）

**目的**: 実装の正しさを自動検証し、失敗があれば「新規（今回の変更で発生）」と「既存（main にもある）」に切り分ける

**注意**: 全ての検証コマンドは worktree 内で実行する。`cd "$WT_PATH" && <検証コマンド>` の形で呼び出し、`git -C "$WT_PATH"` で状態確認する。

1. プロジェクトの検証コマンドを自動検出する:
   - `package.json` の scripts（test, lint, typecheck, check, build）
   - `Makefile` のターゲット（test, lint, check）
   - `mise.toml` / `.mise.toml` のタスク
   - `Cargo.toml`（cargo test, cargo clippy）
   - `pyproject.toml` / `setup.py`（pytest, ruff, mypy）
   - その他のプロジェクト設定ファイル
2. 検出したコマンドを以下の順序で実行:
   1. **型チェック** (tsc, mypy, cargo check 等)
   2. **Lint** (eslint, ruff, clippy 等)
   3. **テスト** (jest, pytest, cargo test 等)
   4. **ビルド** (npm run build, cargo build 等)
3. 検証コマンドが見つからない場合は AskUserQuestion でユーザーに確認
4. **失敗があれば「新規 vs 既存」を切り分ける**（次の手順）
5. 結果をサマリーで報告（種別を明示）

**失敗時の切り分け手順（重要）**:

検証で 1 件でも FAIL があった場合、**default ブランチが checkout された別の worktree で再実行する**。worktree 方式では stash も checkout も不要で冪等に比較できる。

1. default ブランチを checkout 済みの worktree を探す:
   ```bash
   MAIN_WT=$(git -C "$REPO_ROOT" wt --json \
     | jq -r --arg b "$DEFAULT_BRANCH" '.[] | select(.branch == $b) | .path')
   ```
   `MAIN_WT` が空でなければケース A、空ならケース B に進む。

2. **ケース A: `MAIN_WT` が見つかった場合（通常ケース）**
   - FAIL した検証コマンドをその worktree で再実行:
     ```bash
     cd "$MAIN_WT" && <failing-command>
     ```
   - worktree は独立しているので、作業中の変更に影響を与えない（stash 不要、冪等）
   - `MAIN_WT` が古い可能性があれば任意で `git -C "$MAIN_WT" pull --ff-only origin "$DEFAULT_BRANCH"` を実行（副作用ありなのでユーザー確認推奨）

3. **ケース B: `MAIN_WT` が見つからない場合（フォールバック）**
   - default ブランチが checkout された worktree が存在しない稀なケース
   - `$REPO_ROOT` 自体のブランチが default ブランチなら `MAIN_WT="$REPO_ROOT"` とし、ケース A に戻る
   - それ以外は、AskUserQuestion で方針確認:
     - 一時的に `main` 用の worktree を作る。作成: `git -C "$REPO_ROOT" wt --nocd _main-verify "origin/$DEFAULT_BRANCH"`（`--json` は list モード専用なので作成時には付けない）。パス取得: Phase 0 手順 7 と同様に `git -C "$REPO_ROOT" wt --json | jq` で引く。検証後に `git -C "$REPO_ROOT" wt -D _main-verify`
     - または旧来の stash + checkout 方式で切り分ける

4. **結果の判定**:
   - `MAIN_WT` でも同じエラー → **既存問題**（main 由来、今回の変更とは無関係）
   - `MAIN_WT` では出ない → **新規問題**（今回の変更で発生）

**禁止事項**: worktree 内で `git checkout <他のブランチ>` を使った切り分けは行わない（作業状態を壊すリスク、stash pop コンフリクトの手間が再発）。必ず別 worktree で再実行すること。

**検証結果のサマリー形式**:

```
## 検証結果

| チェック | コマンド | 結果 | 種別 |
|---------|---------|------|------|
| 型チェック | tsc --noEmit | PASS | - |
| Lint | eslint . | FAIL (3 errors) | 新規（今回の変更で発生） |
| テスト | npm test | FAIL (1 test) | 既存（main にも存在） |
| ビルド | npm run build | PASS | - |
```

「既存」が含まれる場合は Phase 4 で必ず AskUserQuestion による対応方針確認に進む。

#### Phase 4: Fix（修正）

**目的**: 検証で発見された問題を、種別に応じた方針で対応する

##### 4-A. 新規問題（今回の変更で発生）

1. 失敗内容を分析
2. 問題を修正する
3. 該当する検証コマンドを再実行する
4. **修正 → 再検証ループは最大 3 回**
5. 3 回で解決しない場合は AskUserQuestion でユーザーに判断を仰ぐ:
   - 「手動で修正する」→ ワークフロー一時停止
   - 「このまま PR を作る」→ Phase 5 へ（既知の問題として記載）
   - 「中止する」→ ワークフロー終了

##### 4-B. 既存問題（main にも存在）

main 由来の問題は、独立した課題として扱う。**必ず AskUserQuestion で対応方針を確認する**:

- **今回 PR で併せて修正する**: 修正コストが小さい / 関連が深い / Pre-PR チェック必須の場合に推奨。修正は別コミット（例: `fix: ...`）として残す
- **別 PR で対応する**: 修正に時間がかかる / 範囲が大きい / 専門知識が必要な場合。今回 PR の説明に「既存問題は別 PR で対応予定」と明記する。**セッションファイルの `followups[]` に `decision: "separate-pr"` で追記**（Phase 6 で自動 issue 化される）
- **スコープ外として今回は触らない**: 既知のままでよい場合（例: 長期計画の一部）。PR 説明に「main 既存の課題、本 PR では対応しない」と明記する。**セッションファイルの `followups[]` に `decision: "out-of-scope"` で追記**（Phase 6 で自動 issue 化される）

##### followups[] への記録（「別 PR」「スコープ外」選択時）

セッションファイル `~/.claude/dev-sessions/<slug>.json` の `followups[]` 配列に以下を追記する:

```json
{
  "title": "main にも存在する型エラー（mypage.test.ts の 2 箇所）を修正",
  "body": "PR #131 で混入した型エラーが mypage.test.ts line 42, 58 に残存している。今回 PR のスコープ外として持ち越し。検証ログ: <貼り付け>",
  "decision": "separate-pr",
  "source": {
    "kind": "existing-verification-failure",
    "command": "npm test",
    "files": ["mypage.test.ts"]
  },
  "created_at": "<ISO 8601 now>",
  "issue_url": null
}
```

- `title`: 1 行サマリ（そのまま issue title になる）
- `body`: issue 本文の素材。検証結果の抜粋、影響範囲、再現手順など
- `decision`: `"separate-pr"` or `"out-of-scope"`
- `source`: 何の検査で発見したか（検証失敗、レビュー指摘、計画のスコープ外項目 など）
- `issue_url`: Phase 6 で issue 化された時に URL を記録（cleanup が途中で失敗した際の再実行冪等性のため）

質問例:

```
質問: main にも存在する型エラー（mypage.test.ts の 2 箇所、
       PR #131 で混入）をどうしますか？

選択肢:
  A. この PR で併せて修正（推奨）
     スコープ外だが、Pre-PR チェック必須のため修正する
  B. 別 PR で対応する
     今回 PR の説明に明記して進める
  C. スコープ外として今回は触らない
     既知の問題として PR 説明に明記
```

##### 完了条件

以下のいずれかを満たしたら Phase 5 へ進む:

- 全検証が PASS している
- 新規問題は全て解消、かつ既存問題はユーザー選択（修正 / 別 PR / スコープ外）で明示対応済み

**禁止事項**: 既存問題をユーザー確認なしに「スルー」して PR を作らない。「main にもあるから無視」は NG。

#### Phase 5: PR（プルリクエスト）

**目的**: 変更を Draft PR として作成する

**注意**: git 操作は `git -C "$WT_PATH" ...`、`/pr-create` 等の委譲先スキルも `cd "$WT_PATH" && ...` で起点を揃える。

##### 前提条件（厳守）

Phase 5 に進む前に、以下を必ず満たすこと:

- Phase 3 の全検証が PASS、または
- 残る FAIL は全て「既存問題」かつ Phase 4-B でユーザーが「別 PR」または「スコープ外」を選択済み

新規問題が未解消、または既存問題でユーザー確認が未実施の状態で Phase 5 に進むのは禁止。

##### 手順

1. git の状態を確認（変更ファイル、ブランチ名）: `git -C "$WT_PATH" status` / `git -C "$WT_PATH" branch --show-current`
2. 変更内容を分析してコミットメッセージを作成
3. コミット・プッシュする: `cd "$WT_PATH" && git add ... && git commit ... && git push -u origin "$BRANCH"`
4. PR を作成する（/pr-create の手順に準拠）:
   - Draft PR として作成
   - PR 説明に以下を含める:
     - 変更内容のサマリー
     - 計画ファイルへのリンク（`docs/plans/...`）
     - 関連 ADR へのリンク（`docs/adr/...`）
     - 検証結果のサマリー（種別を含む表）
     - **既存問題の対応方針**（あった場合のみ）:
       - 「今回 PR で修正」を選んだ場合: コミット履歴に `fix:` 等として残す
       - 「別 PR で対応」を選んだ場合: PR 説明に「main 既存の課題（〜〜）は別 PR で対応予定」と明記
       - 「スコープ外」を選んだ場合: PR 説明に「main 既存の課題（〜〜）は本 PR では対応しない」と明記
5. 計画ファイルのステータスを `completed` に更新し、結果セクションを記入する
6. **セッションファイル更新**: `~/.claude/dev-sessions/<slug>.json` を以下に更新
   - `pr_url`: `gh pr view --json url -q .url` で取得
   - `status`: `"pr-open"`
   - `pr_opened_at`: ISO 8601 タイムスタンプ
   - `updated_at`: 同上（以後の post-PR 修正で更新される）
7. ユーザーに PR URL を提示し、**「マージ後に `/dev cleanup` を実行すると worktree を掃除する」ことを明示する**。必要なら post-PR の追加修正が `/dev resume <slug>` で再開できることも伝える

#### Phase 5-bis: Post-PR Iteration（PR 作成後の追加修正）

**目的**: Draft PR 作成後・マージ前の期間に追加修正が必要になった場合、コード修正だけでなく **PR 本文・検証結果・ADR リンクも同期的に更新**してドキュメント整合性を保つ。

**起動方法**:

- `/dev resume` で `status == "pr-open"` のセッションを選択 → 自動で post-PR モード
- `/dev resume <slug>` で直接指定
- cwd が `status == "pr-open"` の worktree 配下 → セッション逆引きで post-PR モード
- **通常の `/dev <説明>` では post-PR モードに入らない**（別タスク扱い）

**前提条件**:

- セッションが存在し `status == "pr-open"`
- `gh pr view "$PR_URL" --json state -q .state` が `OPEN`（`MERGED` なら cleanup へ、`CLOSED` なら AskUserQuestion で再 open or 中止を確認）
- worktree が存在し、リモート追跡ブランチが設定済み

**フロー**:

1. **セッション復元**
   - `WT_PATH` / `BRANCH` / `PR_URL` / `plan_file` をセッションファイルから読み込む
   - Phase 0 の整合性チェック（worktree 存在、前提セットアップ設定）を再実行
   - 現在の PR 本文を `gh pr view "$PR_URL" --json body -q .body` で取得してキャッシュ

2. **追加修正を Phase 2 同等で実装**
   - 変更内容は TaskCreate で管理
   - 設計判断が絡むなら ADR を追記（新規 ADR 番号を採番）
   - 計画ファイル (`docs/plans/...`) の「変更履歴」節を追記（なければ作る）

3. **Phase 3（検証）を再実行**
   - 全検証コマンドを再実行（変更箇所に限定しない — 回帰検出のため）
   - 失敗があれば Phase 4 の切り分けを再実行

4. **Phase 4 を再実行**（必要時）
   - 新規 FAIL は修正
   - 既存 FAIL が新たに見つかれば followups[] に追記（Phase 4-B の手順）

5. **コミット + push**
   ```bash
   cd "$WT_PATH" && git add ... && git commit -m "..." && git push
   ```
   PR のコミットは自動追従する（`gh pr edit` 不要）

6. **PR 本文の再生成と更新**（重要、手動では忘れやすい）

   PR 本文テンプレート（冒頭に変更履歴、以降は再生成）:

   ```markdown
   ## Summary

   <当初の変更内容サマリ + 追加修正のサマリを統合>

   ## 変更履歴

   - YYYY-MM-DD: 初回実装（計画 ${plan_file}）
   - YYYY-MM-DD: <追加修正の要約>  ← 今回追加
   <...以降の追加修正も順に追記>

   ## 計画 / ADR

   - 計画: `docs/plans/...`
   - ADR: `docs/adr/...` (N 件)

   ## 検証結果（最新）

   | チェック | コマンド | 結果 | 種別 |
   |---------|---------|------|------|
   | ...     | ...     | PASS | -    |

   ## 既存問題の対応方針（あれば）

   - [別 PR] <followup[0].title> — 本 PR スコープ外、cleanup で issue 化予定
   - [スコープ外] <followup[1].title> — 本 PR では対応しない、cleanup で issue 化予定
   ```

   更新コマンド:
   ```bash
   # 本文を一時ファイルに生成
   NEW_BODY=$(mktemp)
   cat > "$NEW_BODY" <<EOF
   <上記テンプレートを slug / followups / 検証結果で埋めたもの>
   EOF
   gh pr edit "$PR_URL" --body-file "$NEW_BODY"
   rm -f "$NEW_BODY"
   ```

7. **title の更新**（必要時のみ）
   - スコープが実質的に変わった場合のみ `gh pr edit "$PR_URL" --title "..."`
   - 軽微な追加修正では title を変えない

8. **セッションファイル更新**
   - `updated_at`: ISO 8601 now
   - 必要なら `followups[]` 追記（Phase 4-B で発生した分）
   - `post_pr_iterations`: カウンタ（何度 Phase 5-bis を回したか、任意）

9. **ユーザー報告**
   - 追加コミットの SHA、更新した PR 本文の要点、残 followup 数を提示
   - 「さらに追加修正する場合は `/dev resume <slug>`」を再掲

**禁止事項**:

- PR 本文を更新せずにコミット + push だけで終えない（レビュアーから変更履歴が追えなくなる）
- `gh pr edit --body` で本文を空にしない（`--body-file` を使う、`--body ""` は事故のもと）
- マージ済み（`state == MERGED`）の PR を post-PR モードで再開しない（cleanup へ誘導）

#### Phase 6: Cleanup（後片付け）

**目的**: PR がマージされた後、worktree とブランチをローカルから削除し、セッションファイルを `cleaned` にする。

**起動方法**: 通常の `/dev` フロー (Phase 0→5) からは自動実行しない。PR マージ確認は分〜日単位の非同期タスクなので、ユーザーが明示的に `/dev cleanup` で起動する。

##### 呼び出し形態

- `/dev cleanup` — 引数なし
  - 実行時の cwd を `git rev-parse --show-toplevel` で確認し、worktree 内なら対応セッションを特定
  - cwd が main リポジトリ側 or セッション外なら、`~/.claude/dev-sessions/*.json` のうち `status == "pr-open"` を列挙して AskUserQuestion で選択
- `/dev cleanup <branch>` — ブランチ名指定
  - ブランチ名からセッションファイルを逆引き（`branch` フィールドで検索）

##### 手順

1. **セッションファイル読み込み**
   ```
   WT_PATH / REPO_ROOT / BRANCH / PR_URL を取得
   ```
   セッションが存在しない場合は AskUserQuestion で「PR URL を指定 / 中止」を確認（緊急回復フロー）。

2. **PR state の確認（gh を真実とする）**
   ```bash
   STATE=$(gh pr view "$BRANCH" --json state -q .state 2>/dev/null)
   # または PR_URL が分かっていれば
   STATE=$(gh pr view "$PR_URL" --json state -q .state 2>/dev/null)
   ```
   - `MERGED` → 続行
   - `OPEN` / `CLOSED` / 取得失敗 → **自動削除はしない**。AskUserQuestion で方針確認:
     - 「PR マージを待つ」→ cleanup を中断
     - 「強制的に削除する（-D）」→ ユーザー明示同意のみ。理由を確認してログに残す
     - 「中止」→ 終了

2.5. **followup の自動 issue 化**（`MERGED` 確認後、worktree 削除前に実行）

   **目的**: Phase 4-B で「別 PR で対応」「スコープ外」として記録された項目 (`followups[]`) を、merge タイミングで GitHub issue として登録し、永遠の放置を防ぐ。

   手順:

   1. **followups の抽出**: セッションファイルの `followups[]` を読む
      - 空なら本手順スキップ
      - 各要素のうち `issue_url != null` は既に issue 化済みなのでスキップ（再実行冪等性）

   2. **既存 issue との重複チェック**: 各 followup について:
      ```bash
      # title の前半 40 文字で既存 issue を検索（open/closed 両方、自リポジトリ限定）
      SEARCH_KEY=$(echo "$title" | head -c 40)
      EXISTING=$(gh issue list --state all --search "$SEARCH_KEY in:title" --json number,url --limit 5)

      # PR リンクで逆引きする補助チェック（body に元 PR URL を含む issue があれば重複とみなす）
      EXISTING_BY_PR=$(gh issue list --state all --search "\"$PR_URL\" in:body" --json number,url --limit 5)
      ```
      どちらかで 1 件以上ヒット → **重複扱い**。該当 issue URL を `followup.issue_url` に記録して次へ。0 件 → 作成フェーズへ進む。

   3. **ラベル候補の取得**: `gh label list --json name` で既存ラベルを取得し、以下のキーワードマッチで推定:
      - `decision == "separate-pr"` → `followup` / `tech-debt` / `enhancement` のうち存在するもの
      - `decision == "out-of-scope"` → `backlog` / `out-of-scope` / `followup` のうち存在するもの
      - 加えて `source.kind` が `existing-verification-failure` なら `bug` を追加候補に

      該当ラベルが 1 つも無ければラベルなしで作成（ユーザーが後付けする前提）。

   4. **一括作成前のまとめ確認**（件数 ≥ 5 のときのみ AskUserQuestion を出す）:
      ```
      質問: 未着手の followup を 7 件検出しました。GitHub issue として一括作成しますか？
      選択肢:
        A. 全件作成する
        B. 選択して作成する（1 件ずつ確認）
        C. 今回は作成しない（セッションには残す、次回 cleanup で再チェック）
      ```
      4 件以下なら確認せず全件自動作成する（低 friction 方針）。

   5. **issue 作成**: 各 followup について:
      ```bash
      ISSUE_BODY=$(mktemp)
      cat > "$ISSUE_BODY" <<EOF
      ## Context

      このタスクは [$PR_URL]($PR_URL) のマージ時に followup として自動登録されました。

      **元の決定**: $decision (${decision == "separate-pr" ? "別 PR で対応" : "スコープ外"})
      **発見経緯**: ${source.kind}
      **関連計画**: \`${plan_file}\`

      ## 詳細

      $body

      ---
      _Auto-created by \`/dev cleanup\` from session \`${slug}\`_
      EOF

      ISSUE_URL=$(gh issue create \
        --title "$title" \
        --body-file "$ISSUE_BODY" \
        ${labels:+--label "$labels"} \
        --json url -q .url)

      rm -f "$ISSUE_BODY"
      ```
      作成失敗時（権限不足・API エラー等）は警告を出してその followup は `issue_url: null` のまま残す。次回 cleanup で再試行される。

   6. **セッションファイル更新**: 各 followup の `issue_url` フィールドに作成 URL を書き戻す（手順 7 の `status: cleaned` 更新と一緒にアトミックに書く）

   7. **ユーザー報告**: 作成した issue の一覧、重複扱いで既存 issue にマップされた件数を表示

   **禁止事項**:
   - `gh issue create` の `--body` 引数に shell 展開で長文を渡さない（改行・引用符でクラッシュする）→ 必ず `--body-file`
   - `issue_url` が既に入っている followup を再作成しない（冪等性違反）
   - プロジェクトの issue テンプレートを無視しない — リポジトリに `.github/ISSUE_TEMPLATE/` があれば `--template` オプションで指定するか、テンプレート本文を取り込んでから body 生成する

3. **worktree の未コミット変更チェック**
   ```bash
   git -C "$WT_PATH" status --porcelain
   ```
   出力があれば中断し、ユーザーに報告する。**自動で破棄しない**（意図しない作業を消さないため）。

4. **実行中プロセスの警告**（ベストエフォート、限定的）
   ```bash
   lsof +D "$WT_PATH" 2>/dev/null | head
   ```
   **注意**: この検査は worktree 内のファイルを開いているプロセス（worktree に `cd` したシェル等）しか捕まえない。**ポートだけを掴む dev server（例: `next dev`, `vite`, `rails server`）は検出されない**。ユーザーには「worktree で開いている shell や editor、バインドされた dev server をこちらで確認してから cleanup 実行」を促すフレーズを出す。出力があれば警告のみ（kill はしない）。

5. **worktree + ブランチ削除**
   ```bash
   git -C "$REPO_ROOT" wt -d "$BRANCH"
   ```
   - 成功 → 次へ
   - 「not merged into default branch」等で拒否された場合（squash/rebase merge で起こる）:
     - 既に手順 2 で `MERGED` を確認済みなので、AskUserQuestion で「強制削除 (`-D`) を実行する？」を確認
     - 同意後: `git -C "$REPO_ROOT" wt -D "$BRANCH"`

6. **リモートブランチの削除確認**
   - GitHub 側で自動削除設定になっていれば不要
   - そうでなければ AskUserQuestion で「リモートブランチも削除？」を確認
     ```bash
     git -C "$REPO_ROOT" push origin --delete "$BRANCH"
     ```

7. **セッションファイル更新**
   ```json
   {
     ...既存フィールド,
     "status": "cleaned",
     "cleaned_at": "<ISO 8601 now>"
   }
   ```

8. **最終確認レポート**
   - 削除した worktree パス
   - 削除したローカルブランチ
   - リモートブランチの扱い（削除 / 保持）
   - **作成した GitHub issue 一覧**（手順 2.5 の結果、新規 / 既存にマップされた件数）
   - 参考: 残っている他セッション一覧（`status: "pr-open"` / `"in-progress"`）

##### 前提条件

以下が満たされない場合は中断:

- gh CLI で認証済み（`gh auth status`）
- セッションファイルが存在する or PR URL を引数で指定できる
- worktree に未コミット変更がない（あれば中断してユーザーに対応依頼）

##### 禁止事項

- **PR state が MERGED でない状態で自動削除しない**（`-D` フォールバックは明示ユーザー同意時のみ）
- **未コミット変更を勝手に破棄しない**
- **実行中プロセスを勝手に kill しない**（警告のみ）

### セッション管理

`/dev` はタスクごとに `~/.claude/dev-sessions/<slug>.json` を作成し、worktree / リポジトリ / PR 情報を durable に保持する。Claude Code のセッションをまたいでも cleanup や再開が可能。

#### ファイル構造

```
~/.claude/dev-sessions/
├── profile-image-upload.json   # status: "pr-open"    (Phase 5 完了、マージ待ち)
├── auth-refactor.json          # status: "in-progress" (Phase 2 途中)
└── bugfix-typo.json            # status: "cleaned"    (cleanup 済み、監査用に残す)
```

ステータス遷移: `in-progress` → `pr-open` → `cleaned`

#### スキーマ

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
      "title": "main にも存在する型エラー（mypage.test.ts）を修正",
      "body": "PR #131 で混入した型エラーが mypage.test.ts line 42, 58 に残存している。本 PR のスコープ外として持ち越し。",
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

フィールド追加の意味:

- `updated_at`: 最終更新時刻。Phase 5-bis で更新
- `post_pr_iterations`: Phase 5-bis を回した回数（任意、運用メトリクス）
- `followups[]`: Phase 4-B で「別 PR」「スコープ外」を選んだ項目。Phase 6 手順 2.5 で issue 化されると `issue_url` が埋まる

#### 整合性チェック

セッションファイル読み込み時に以下を確認し、不整合があれば AskUserQuestion で対処:

- `worktree_path` が存在するか（削除されていたらセッションを invalidate）
- `repo_root` が git リポジトリか
- `branch` がリモートに存在するか

### フェーズスキップ

ユーザーが明示的に指示した場合、特定フェーズをスキップできる:

- 「計画はスキップして実装から始めて」→ Phase 2 から開始（Phase 0 は実行）
- 「PR は手動で作るからここまでで」→ Phase 5 をスキップ
- 「検証だけやって」→ Phase 3 のみ実行
- 「worktree は作らなくていい」→ Phase 0 をスキップして従来動作（セッションファイルも作らない）

### 中断と再開

- 中断時は `~/.claude/dev-sessions/<slug>.json` と worktree がそのまま残る
- **再開方法**:
  - `/dev resume` — セッション一覧から選択（`status != "cleaned"` のみ列挙）
  - `/dev resume <slug>` — slug 指定
  - `/dev` 引数なしで起動 → 既存セッションがあれば AskUserQuestion で「新規 / 再開 / cleanup」を選ばせる
- 再開時の動作:
  1. セッションファイルから `WT_PATH` / `BRANCH` / `plan_file` / `pr_url` / `status` / `followups` を復元
  2. 整合性チェック（worktree 存在確認）
  3. **status による分岐**:
     - `status == "in-progress"`: 計画ファイルのステータスとタスク状態から Phase 2 以降を再開
     - `status == "pr-open"`: **Phase 5-bis (Post-PR Iteration) モードに入る**。`gh pr view` で state を確認し、OPEN なら追加修正フロー、MERGED なら cleanup へ誘導
     - `status == "cleaned"`: 一覧には出さない（既に閉じている）

### 注意事項

- **承認前の実装開始は厳禁** — Phase 1 の計画がユーザーに承認されるまで Phase 2 に進まない
- **推測で進めない** — 不明点は必ず AskUserQuestion で確認する（Phase 0 のブランチ命名など、フェーズ固有の例外を除く）
- **ADR は設計判断のみ** — 軽微な確認事項は ADR に残さない
- **既存コードの尊重** — 変更箇所以外のコードスタイルやパターンに合わせる
- **コミットは適切な粒度で** — 1 つの論理的変更 = 1 コミットを原則とする
- **main を壊さない** — Phase 5 (PR 作成) 前に全検証 PASS を必須とする。検証失敗を発見したら必ず「新規 vs 既存」を切り分け、既存問題は AskUserQuestion で対応方針を確認する。「main にも同じエラーがあるから無視」は禁止
- **検証失敗のスルー禁止** — 「自分の変更による失敗ではない」と判断しても、ユーザー確認なしに無視して PR を作成しない。既存問題の発見は新たな課題の発見と捉え、必ず方針を確認する
- **cwd は毎回明示する** — Bash 呼び出し間で cwd は保持されないので、全コマンドで `cd "$WT_PATH" && ...` または `git -C "$WT_PATH"` を使う
- **main リポジトリ側で作業しない** — Phase 0 以降は必ず worktree 内で作業。Read/Write/Edit は `$WT_PATH` 配下の絶対パスを使う
- **cleanup の自動化禁止** — PR マージ確認は `gh pr view --json state` が `MERGED` を返した場合のみ削除。未マージで勝手に `-D` しない

### 実行例

```
# 基本的な使い方（Phase 0〜5）
/dev ユーザープロフィールページに画像アップロード機能を追加する

# 期待される動作
# Phase 0: worktree 準備 → .wt/feat-profile-image-upload/ 作成
#          → ~/.claude/dev-sessions/profile-image-upload.json 保存
# Phase 1: 計画策定 → $WT_PATH/docs/plans/2026-04-17-profile-image-upload.md 保存
# Phase 2: 実装（worktree 内で、不明点は質問 → ADR 記録）
# Phase 3: 検証（テスト・lint・型チェック自動実行、失敗は default branch worktree で切り分け）
# Phase 4: 修正（問題があれば修正ループ）
# Phase 5: Draft PR 作成 → セッションファイルに pr_url 記録

# 途中再開
/dev resume                          # セッション一覧から選択
/dev resume profile-image-upload    # slug 指定

# PR マージ後の後片付け
/dev cleanup                         # cwd が worktree ならそのまま対応
/dev cleanup feat-profile-image-upload  # ブランチ指定
```

### 関連コマンド

- `/plan` : 計画策定のみ（Phase 1 相当）
- `/pr-create` : PR 作成のみ（Phase 5 相当）
- `/spec` : 仕様駆動開発（より大規模な機能向け）
- `/spec-new` : ゼロからの仕様策定

### 前提セットアップ（初回に一度だけ、重要）

`/dev` は Phase 0 冒頭で `wt.copyignored` / `wt.copy` の設定状況を自動チェックし、未設定なら警告を出す。**作業効率に直結するため、未セットアップのユーザーは以下を事前に実行しておくこと**。本スキルは `wt.*` 設定を自動変更しない（ユーザーの git config を勝手に書き換えない原則）。

#### 必須レベル（全ユーザー推奨）

`.env` / `.dev.vars` などの **設定ファイルの手動コピー忘れ**を防ぐ。Cloudflare Workers (`wrangler dev`)、Next.js、Rails など env ファイル必須の環境では特に重要。

**重要な前提**: `wt.copyignored=true` は「gitignore 対象」のファイルだけコピーする。`.dev.vars` などを対象にしたい場合、**そのファイルが `.gitignore` に登録されている**必要がある。未登録（untracked）なら別の設定が要る（下表）。

| `.dev.vars` 等の状態 | 必要な設定 | 備考 |
|---------------------|-----------|------|
| `.gitignore` に登録済み（gitignored） | `wt.copyignored=true` | リポジトリ方針として env は必ず gitignore するのが安全。推奨 |
| 未登録（untracked）                  | `wt.copyuntracked=true` **または** `wt.copy <pattern>` | untracked を広く扱いたいなら前者、ファイル指定なら後者 |
| git 管理下（tracked）                | 追加設定不要（git-wt 既定） | 機密ファイルは tracked にしない |

```bash
# 最小セットアップ: gitignored なファイルを全て新規 worktree にコピー（.gitignore 登録前提）
git config --global wt.copyignored true

# 未登録の .dev.vars も確実にコピーしたい場合（いずれか 1 つ）
git config --global wt.copyuntracked true          # untracked を全部コピー（範囲広め）
git config --global --add wt.copy ".dev.vars"      # このファイルだけ明示的にコピー
git config --global --add wt.copy ".env*"          # パターン指定
git config --global --add wt.copy ".envrc"
```

#### 推奨レベル（重いリポジトリで特に効く）

```bash
# node_modules / .venv を毎回コピーしない（遅い）。symlink で共有
git config --global --add wt.symlink "node_modules/"
git config --global --add wt.symlink ".venv/"

# 万一 IDE ワークスペース等が gitignore されていてもコピー
git config --global --add wt.copy ".vscode/"
git config --global --add wt.copy "*.code-workspace"

# 除外したいもの（巨大ログ等）
git config --global --add wt.nocopy "*.log"
```

#### プロジェクトごとに設定するもの

`.git/config` にリポジトリ別で設定（`--global` なし）:

```bash
# worktree 作成後に依存関係をインストール
git config --add wt.hook "pnpm install"
git config --add wt.hook "mise install"

# worktree 削除前にリモートブランチも消す場合
# (Phase 6 で AskUserQuestion する代わりに自動化)
git config --add wt.deletehook 'git push origin --delete $(git branch --show-current) || true'
```

#### 初回セットアップのチェックリスト

1. **必須**: `git config --global wt.copyignored true` で `.env` / `.dev.vars` の自動コピーを有効化
2. `.gitignore` に `.wt/` を追加（worktree のデフォルト basedir を無視）
3. `wt.symlink` で `node_modules/` / `.venv/` 等を共有
4. プロジェクト単位の init コマンドを `wt.hook` に登録

#### セットアップ確認コマンド（手動診断）

現在の git-wt 設定を確認するワンライナー:

```bash
echo "=== git-wt config ==="
echo "wt.copyignored: $(git config --get wt.copyignored || echo '(unset)')"
echo "wt.copy:"
git config --get-all wt.copy | sed 's/^/  - /' || echo "  (unset)"
echo "wt.symlink:"
git config --get-all wt.symlink | sed 's/^/  - /' || echo "  (unset)"
echo "wt.hook:"
git config --get-all wt.hook | sed 's/^/  - /' || echo "  (unset)"
```
