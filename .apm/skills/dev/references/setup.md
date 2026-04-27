# Setup: git-wt 前提セットアップ

`/dev` の Phase 0 で警告が出たとき、または初回利用前にユーザーが `~/.gitconfig` に入れておく git-wt 設定。SKILL.md 本体から「Phase 0 の警告メッセージで参照を促されたとき」「初回利用前にセットアップするとき」に参照する。

`/dev` は `wt.*` 設定を自動変更しない (ユーザーの git config を勝手に書き換えない原則)。Phase 0 冒頭で `wt.copyignored` / `wt.copy` の設定状況を自動チェックして警告を出すだけ。作業効率に直結するため、未セットアップなら以下を事前に実行しておく。

## Contents
- [必須レベル (全ユーザー推奨)](#必須レベル-全ユーザー推奨)
- [推奨レベル (重いリポジトリで特に効く)](#推奨レベル-重いリポジトリで特に効く)
- [プロジェクトごとに設定するもの](#プロジェクトごとに設定するもの)
- [初回セットアップのチェックリスト](#初回セットアップのチェックリスト)
- [セットアップ確認コマンド](#セットアップ確認コマンド)

## 必須レベル (全ユーザー推奨)

`.env` / `.dev.vars` などの **設定ファイルの手動コピー忘れ**を防ぐ。Cloudflare Workers (`wrangler dev`)、Next.js、Rails など env ファイル必須の環境では特に重要。

**重要な前提**: `wt.copyignored=true` は「gitignore 対象」のファイルだけコピーする。`.dev.vars` などを対象にしたい場合、**そのファイルが `.gitignore` に登録されている**必要がある。未登録 (untracked) なら別の設定が要る。

| `.dev.vars` 等の状態 | 必要な設定 | 備考 |
|---------------------|-----------|------|
| `.gitignore` に登録済み (gitignored) | `wt.copyignored=true` | リポジトリ方針として env は必ず gitignore するのが安全。推奨 |
| 未登録 (untracked) | `wt.copyuntracked=true` または `wt.copy <pattern>` | untracked を広く扱いたいなら前者、ファイル指定なら後者 |
| git 管理下 (tracked) | 追加設定不要 (git-wt 既定) | 機密ファイルは tracked にしない |

```bash
# 最小セットアップ: gitignored なファイルを全て新規 worktree にコピー (.gitignore 登録前提)
git config --global wt.copyignored true

# 未登録の .dev.vars も確実にコピーしたい場合 (いずれか 1 つ)
git config --global wt.copyuntracked true          # untracked を全部コピー (範囲広め)
git config --global --add wt.copy ".dev.vars"      # このファイルだけ明示的にコピー
git config --global --add wt.copy ".env*"          # パターン指定
git config --global --add wt.copy ".envrc"
```

## 推奨レベル (重いリポジトリで特に効く)

```bash
# node_modules / .venv を毎回コピーしない (遅い)。symlink で共有
git config --global --add wt.symlink "node_modules/"
git config --global --add wt.symlink ".venv/"

# 万一 IDE ワークスペース等が gitignore されていてもコピー
git config --global --add wt.copy ".vscode/"
git config --global --add wt.copy "*.code-workspace"

# 除外したいもの (巨大ログ等)
git config --global --add wt.nocopy "*.log"
```

## プロジェクトごとに設定するもの

`.git/config` にリポジトリ別で設定 (`--global` なし):

```bash
# worktree 作成後に依存関係をインストール
git config --add wt.hook "pnpm install"
git config --add wt.hook "mise install"

# worktree 削除前にリモートブランチも消す場合
# (Phase 6 で AskUserQuestion する代わりに自動化)
git config --add wt.deletehook 'git push origin --delete $(git branch --show-current) || true'
```

## 初回セットアップのチェックリスト

1. **必須**: `git config --global wt.copyignored true` で `.env` / `.dev.vars` の自動コピーを有効化
2. `.gitignore` に `.wt/` を追加 (worktree のデフォルト basedir を無視)
3. `wt.symlink` で `node_modules/` / `.venv/` 等を共有
4. プロジェクト単位の init コマンドを `wt.hook` に登録

## セットアップ確認コマンド

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
