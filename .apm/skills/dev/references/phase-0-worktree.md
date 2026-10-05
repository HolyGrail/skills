# Phase 0: Prepare Worktree

git worktree (k1LoW/git-wt) でタスク専用環境を準備する詳細手順。SKILL.md 本体から「新規タスクで Phase 0 を実装するとき」「git-wt の設定検査ロジックが必要なとき」に参照する。

## Contents
- [目的と実行コンテキスト](#目的と実行コンテキスト)
- [手順 0: git-wt 前提セットアップの自動チェック](#手順-0-git-wt-前提セットアップの自動チェック)
- [手順 1: リポジトリ判定と root 取得](#手順-1-リポジトリ判定と-root-取得)
- [手順 2: 既に worktree 内か判定](#手順-2-既に-worktree-内か判定)
- [手順 3: default ブランチ検出](#手順-3-default-ブランチ検出)
- [手順 4: slug とブランチ名の自動決定](#手順-4-slug-とブランチ名の自動決定)
- [手順 5: origin を fetch](#手順-5-origin-を-fetch)
- [手順 6: 既存 worktree の再利用チェック](#手順-6-既存-worktree-の再利用チェック)
- [手順 7: worktree 新規作成](#手順-7-worktree-新規作成)
- [手順 8: セッションポインタ保存](#手順-8-セッションポインタ保存)
- [手順 9: 以降の Bash 呼び出しの基本形](#手順-9-以降の-bash-呼び出しの基本形)
- [フォールバックと例外時の自動対応](#フォールバックと例外時の自動対応)

## 目的と実行コンテキスト

タスク専用の git worktree を作成し、以後全ての作業をその中で隔離する。

以下は **main リポジトリの作業ディレクトリから** 開始する前提。既に worktree 内から `/dev` を起動した場合は手順 2 で判定し「既存 worktree 再利用」フローに分岐する。

## 手順 0: git-wt 前提セットアップの自動チェック

毎回実行、セットアップ漏れ防止。worktree 作成で `.dev.vars` / `.env*` のコピー忘れを防ぐには、**設定と対象ファイルの状態を両面で検査**する。`wt.copyignored=true` は gitignored なファイルしか対象にしないため、`.dev.vars` が `.gitignore` に載っていない (untracked 扱い) と copy されない。

**実行タイミング**: `REPO_ROOT` に依存するので **手順 1 (REPO_ROOT 取得) の直後に実行する**。見出し番号は "0" だが、これは「セットアップ漏れ防止の責務」を分離するためのもので、実装順は 1 → 0 → 2 でよい。

```bash
# 設定の検出
COPYIGNORED=$(git config --get wt.copyignored 2>/dev/null)
COPYUNTRACKED=$(git config --get wt.copyuntracked 2>/dev/null)
readarray -t COPY_PATTERNS < <(git config --get-all wt.copy 2>/dev/null)

# 対象ファイルを untracked / ignored に限定して列挙
readarray -d '' -t UNTRACKED_ENV < <(git -C "$REPO_ROOT" ls-files -z --others --exclude-standard -- '.dev.vars' '.env*' '.envrc' 2>/dev/null)
readarray -d '' -t IGNORED_ENV   < <(git -C "$REPO_ROOT" ls-files -z --others --ignored --exclude-standard -- '.dev.vars' '.env*' '.envrc' 2>/dev/null)
```

### 判定ルール

対象ファイルが存在する場合のみ適用。存在しなければ検査スキップ。

| 対象ファイルの git 上の状態 | copy が保証される条件 |
|----------------------------|----------------------|
| `IGNORED_ENV` にある (gitignored) | `COPYIGNORED=true` |
| `UNTRACKED_ENV` にある (gitignore 未登録) | `COPYUNTRACKED=true` または `COPY_PATTERNS` の各要素が `case "$f" in $pat)` 相当の **fnmatch (glob) で一致** |
| tracked (`git ls-files` で検出) | 常に copy される (git-wt 既定動作、検査不要) |

`wt.symlink` は `node_modules/` / `.venv/` 等の大型ディレクトリ共有用で、env コピー判定には無関係。

### 判定手順

1. `IGNORED_ENV` も `UNTRACKED_ENV` も空なら **OK** (検査対象なし)
2. `IGNORED_ENV` のファイルは `COPYIGNORED=true` なら OK
3. `UNTRACKED_ENV` のファイルは `COPYUNTRACKED=true` なら OK。または `for p in "${COPY_PATTERNS[@]}"; do case "$f" in $p) matched=1;; esac; done` で一致すれば OK
4. 上記いずれでも OK にならないファイルがあれば **警告して続行**:

   ```
   警告: git-wt の設定では以下のファイルが新規 worktree に copy されません:
     - .dev.vars  (untracked、wt.copyuntracked 未設定、wt.copy に未登録)

   推奨セットアップ (いずれか 1 つ):
     git config --global wt.copyignored true       # .gitignore に .dev.vars を追加する前提
     git config --global wt.copyuntracked true     # untracked も copy (範囲広め)
     git config --global --add wt.copy ".dev.vars" # このファイルだけ明示的に copy

   詳細は references/setup.md を参照。今回はこのまま続行します。
   ```

セットアップを今すぐ入れるかどうかは**聞かない** (作業中断を避ける)。ユーザー側で後から設定する。

## 手順 1: リポジトリ判定と root 取得

```bash
# git-wt の存在確認は必ず command -v で行う。
# git wt version / git wt check のような「裸の単語」は worktree+branch を誤作成するので絶対に使わない。
command -v git-wt >/dev/null || echo "git-wt 未検出"
# バージョンを出したい場合のみ: git-wt --version

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
```

`git-wt` が未検出なら、後段の worktree 作成は失敗するので従来動作 (worktree なし) に自動フォールバックする (詳細は末尾「フォールバックと例外時の自動対応」)。`REPO_ROOT` が取れなかった場合は git 管理外なので、状況を報告して中断する。

## 手順 2: 既に worktree 内か判定

`REPO_ROOT` は cwd から `git rev-parse --show-toplevel` で取ったものなので、既に worktree 内から起動した場合は **worktree のパス**になっている。main リポジトリと worktree の判別は `git-dir` と `git-common-dir` の比較で行う:

```bash
GIT_DIR=$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)
COMMON_DIR_REL=$(git -C "$REPO_ROOT" rev-parse --git-common-dir)
COMMON_DIR=$(cd "$(dirname "$GIT_DIR")" && cd "$COMMON_DIR_REL" 2>/dev/null && pwd || echo "$COMMON_DIR_REL")
```

`GIT_DIR != COMMON_DIR` なら既に worktree 内。`WT_PATH="$REPO_ROOT"` として手順 3-7 はスキップ、手順 8 のセッション登録だけ行う。main リポジトリの絶対パスは `dirname "$COMMON_DIR"` で取れる。

## 手順 3: default ブランチ検出

```bash
DEFAULT_BRANCH=$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
```

## 手順 4: slug とブランチ名の自動決定

原則ユーザー確認なし。

- タスク説明から英語ケバブケース slug を自動生成 (例: `profile-image-upload`)
- 接頭辞はタスク説明から判定: 追加/新機能 → `feat-`、修正 → `fix-`、リファクタ → `refactor-`、雑務 → `chore-`、ドキュメント → `docs-`
- プロジェクト慣習があれば `git -C "$REPO_ROOT" branch -a | head -30` を見て既存命名パターンに寄せる (例: `feature/` / `bugfix/` が多数派ならそれに従う)
- **AskUserQuestion は使わない**。例外的な状況も自動解決する:
  - ローカル/リモートで同名ブランチが既に存在し、再利用 (手順 6) に該当しない → 末尾に `-2`, `-3` … の連番を付与して回避し、ナレーションで報告する
  - タスク説明が極端に短く (20 文字未満など) slug が意味のある英単語にならない → コードベース調査の結果から最も内容を説明する slug を自分で決めて続行する

## 手順 5: origin を fetch

```bash
git -C "$REPO_ROOT" fetch origin "$DEFAULT_BRANCH"
```

## 手順 6: 既存 worktree の再利用チェック

```bash
EXISTING=$(git -C "$REPO_ROOT" wt --json \
  | jq -r --arg b "$BRANCH" '.[] | select(.branch == $b) | .path')
```

`EXISTING` が空でなければ `WT_PATH="$EXISTING"` として再利用、手順 7 はスキップ。

## 手順 7: worktree 新規作成

git-wt で作成、シェル統合に依存せず `--nocd` でパスのみ出力させる。

**注意**: `git wt --json <branch>` は **list モードでのみ** JSON 配列を返す。作成時 (`git wt <branch> <start-point>`) は `--nocd` を付けると最終行にプレーンパスを出力するが、フォーマットはバージョン依存。最も安全な手順は「作成 → list でパスを引く」の 2 段階:

```bash
# 作成 (stdout/stderr に informational 出力あり。終了コード 0 を確認)
git -C "$REPO_ROOT" wt --nocd "$BRANCH" "origin/$DEFAULT_BRANCH"

# パス取得 (list 出力は JSON 配列で安定)
WT_PATH=$(git -C "$REPO_ROOT" wt --json \
  | jq -r --arg b "$BRANCH" '.[] | select(.branch == $b) | .path')
```

`WT_PATH` が空なら作成失敗扱い。絶対パスが返る。

### basedir の .gitignore チェック

`wt.basedir` の設定値を `git -C "$REPO_ROOT" config --get wt.basedir` で取得 (未設定なら `.wt`)。その basedir がリポジトリ内に解決される場合のみ `.gitignore` にエントリがあるか確認、なければ警告して追加を促す (自動編集はしない)。`../{gitroot}-wt` のようにリポジトリ外なら .gitignore チェック不要。

## 手順 8: セッションポインタ保存

`~/.claude/dev-sessions/<slug>.json` に書き出す:

```json
{
  "slug": "profile-image-upload",
  "branch": "feat-profile-image-upload",
  "worktree_path": "/abs/path/to/repo/.wt/feat-profile-image-upload",
  "repo_root": "/abs/path/to/repo",
  "default_branch": "main",
  "plan_issue": null,
  "pr_url": null,
  "status": "in-progress",
  "created_at": "<ISO 8601 now>"
}
```

`plan_issue` は Phase 1 終了時 (計画 issue の作成 / 採用後) に更新、`pr_url` / `status: "pr-open"` は Phase 5 終了時に更新する。詳細スキーマは [session-management.md](session-management.md) 参照。

## 手順 9: 以降の Bash 呼び出しの基本形

- `cd "$WT_PATH" && <コマンド>` を基本形にする
- 単発の git 操作は `git -C "$WT_PATH" <コマンド>` でも可
- **メインセッションでは、`cd` の効果は既定で次の Bash 呼び出しに残る**。残った cwd に頼って `cd "$WT_PATH" &&` を省かない。直前の呼び出しが別の場所へ `cd` していれば、コマンドはそこで実行される
- `cd` が残らない場合もある。行き先がプロジェクトディレクトリと追加の作業ディレクトリの外だったとき (出力に `Shell cwd was reset to <dir>` が出る)、`CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` が設定されているとき、subagent のセッション、バックグラウンドに回ったコマンドがそれに当たる (SKILL.md「Claude Code 実行環境の絶対条件」参照)。基本形ならどの場合でも結果は変わらない。どこにいるかは推測せず、判断が要る場面では `pwd` を出力に含める
- 「間違った場所を編集した」と思ったら、復旧操作 (`cp` / `git checkout --`) の前に worktree と main リポジトリの両方で `git status --short --untracked-files=all` と `git diff --stat HEAD` を確認し、編集がどちらにあるかを確かめる。出力が空でも上書きして安全とは限らない (gitignored なファイルの編集は出ない) ので、上書きの直前に、消える内容を `diff` で出力して読む (SKILL.md の Gotchas 参照)

## フォールバックと例外時の自動対応

### ブランチ衝突・命名不能

手順 4 のとおり自動解決する (連番付与 / 調査結果からの命名)。ユーザー確認のために停止しない。

### worktree 作成失敗時

- **git リポジトリでない** (`REPO_ROOT` が取れない): ワークフローの前提を満たさないので、状況を報告して中断する (リポジトリの用意はユーザーにしか決められない)
- **git-wt 未検出 / worktree 作成失敗**: 警告して **従来動作 (worktree なし、main リポジトリ上に新規ブランチを作成) に自動フォールバックする**。`WT_PATH="$REPO_ROOT"` とし、セッションファイルの `worktree_path` にも同じパスを記録する。フォールバックした事実と理由をナレーションで報告し、計画 issue の「結果」節にも残す (後から worktree 隔離が無かったことを追える状態にする)

git-wt の存在確認は `command -v git-wt` で行い、**`git wt version` 等の裸の単語で確認しない** (worktree+branch を誤作成する。手順 1 と SKILL.md の Gotchas 参照)。
