---
description: |
  変更を分析して Draft PR を作成する（テンプレート保持、ラベル選択、日本語推敲ゲート付き）
---

## PR Create

Git 変更分析に基づく自動 PR 作成で効率的な Pull Request ワークフローを実現します。

### 使い方

```bash
# 変更分析による自動 PR 作成
git add . && git commit -m "feat: ユーザー認証機能の実装"
「変更内容を分析して適切な説明文とラベルで Draft PR を作成してください」

# 既存テンプレート保持での更新
BODY=$(mktemp -t pr-body.XXXXXX); cp .github/PULL_REQUEST_TEMPLATE.md "$BODY"
「テンプレート構造を完全に保持して変更内容を補完してください」

# 段階的品質向上
gh pr ready
「品質確認完了後、Ready for Review に変更してください」
```

### 基本例

```bash
# 1. ブランチ作成とコミット
git checkout main && git pull
git checkout -b feat-user-profile
git add . && git commit -m "feat: ユーザー プロフィール機能の実装"
git push -u origin feat-user-profile

# 2. PR 作成
「以下の手順で PR を作成してください：
1. git diff main...HEAD で変更内容を確認
2. .github/PULL_REQUEST_TEMPLATE.md を使用して説明文を作成
3. 変更内容に合う既存ラベルを選択
4. Draft PR として作成（HTML コメント保持）」

# 3. CI 確認後に Ready 化
「CI が通ったら PR を Ready for Review に変更してください」
```

### 実行手順

#### 1. ブランチ作成

```bash
# ガイドラインに従った命名規則: {type}-{subject}
git checkout main
git pull
git checkout -b feat-user-authentication

# ブランチ確認（現在のブランチ名を表示）
git branch --show-current
```

#### 2. コミット

```bash
# 変更をステージング
git add .

# ガイドラインに従ったコミットメッセージ
git commit -m "feat: ユーザー認証 API の実装"
```

#### 3. リモートに Push

```bash
# 初回 Push（upstream 設定）
git push -u origin feat-user-authentication

# 2 回目以降
git push
```

#### 4. ビルド検証（PR 作成前の必須ステップ）

**Push する前に、プロジェクトの検証コマンドを実行する。失敗した場合は修正してから次に進む。**

検証コマンドの検出順序:
1. プロジェクトの CLAUDE.md に記載された検証コマンド
2. `mise tasks` / `Makefile` / `package.json` scripts / `Cargo.toml` / `Gemfile` 等から自動検出
3. 不明な場合はユーザーに確認

実行する検証:
- **型チェック・静的解析**（該当する言語・フレームワークのもの）
- **ビルド**（プロジェクトのビルドコマンド）
- **Lint**（設定がある場合）

- **全て PASS するまで PR 作成に進まない**
- エラーがあれば修正 → 再検証のループを最大 3 回まで実行
- 3 回で解決しない場合はユーザーに報告して判断を仰ぐ

#### 5. 自動分析による Draft PR 作成

**Step 1: 変更内容の分析**

```bash
# ファイル変更の取得（commit 済みなので staged diff は空。main との差分を見る）
git diff main...HEAD --name-only

# 内容分析（最大 1000 行）
git diff main...HEAD | head -1000
```

**Step 2: 説明文の自動生成（ビルド検証 PASS 後）**

```bash
# テンプレート処理の優先順位
# 1. 既存 PR 説明（完全保持）
# 2. .github/PULL_REQUEST_TEMPLATE.md
# 3. デフォルトテンプレート

BODY=$(mktemp -t pr-body.XXXXXX)   # 固定名は複数 worktree・セッションで衝突するため mktemp
cp .github/PULL_REQUEST_TEMPLATE.md "$BODY"
# "$BODY" を編集し、HTML コメント・区切り線を保持したまま空セクションのみ補完
```

**Step 2.5: cognitive-rhythm-writing による文章チェック（PR 作成前の必須ステップ）**

PR のタイトルと本文（日本語部分）を投稿する前に、必ず Skill(cognitive-rhythm-writing) を発火させて推敲する。PR は人間が読む文章なので japanese-tech-writing 単独ではなく cognitive-rhythm-writing を優先する（併用規範として japanese-tech-writing も読み込まれる）。既存テンプレートの HTML コメント・区切り線・既存記述は完全に保持したまま、自分が新規に書き起こした日本語の説明文とタイトルだけを規範に沿って整える。

投稿コマンド実行時には PreToolUse hook (`~/.claude/hooks/jtw-guard.sh`) が推敲済みかを確認する safety net が走る（グローバル CLAUDE.md「日本語文章」を参照）。

**Step 3: ラベルの自動選択**

```bash
# 利用可能ラベルの取得（非インタラクティブ）
「.github/labels.yml または GitHub リポジトリから利用可能なラベルを取得して、変更内容に基づいて適切なラベルを自動選択してください」
```

**Step 4: `gh pr create --body-file` での PR 作成（HTML コメント保持）**

```bash
# 投稿直前に中身が意図した本文か確認（別セッションの古い本文を投稿する事故が起きている）
head -c 300 "$BODY"

# Draft PR 作成。本文はファイル経由で渡す
gh pr create --draft --base main --title "<コミットメッセージから生成>" --body-file "$BODY" --label "<選択したラベル>"

# 使用後は削除
rm -f "$BODY"
```

作成時の指定:

- タイトル: コミットメッセージから自動生成
- 説明文: `.github/PULL_REQUEST_TEMPLATE.md` の構造を保って記入
- ラベル: 変更内容から既存ラベルを選択
- ベースブランチ: main
- HTML コメントは完全に保持

**方法 B: GitHub MCP（フォールバック）**

```javascript
// HTML コメント保持での PR 作成
mcp__github__create_pull_request({
  owner: 'organization',
  repo: 'repository',
  base: 'main',
  head: 'feat-user-authentication',
  title: 'feat: ユーザー認証の実装',
  body: prBodyContent, // HTML コメントを含む完全な内容
  draft: true,
  maintainer_can_modify: true,
});
```

### ラベル選択

`.github/labels.yml` か `gh label list --limit 200 --json name,description` で既存ラベルを取り、diff の内容に合うものを選ぶ。該当が無ければ付けない。新しいラベルは作らない（ラベルはリポジトリ全体で共有する分類で、PR ごとに増えると体系が崩れるため）。

### プロジェクトガイドライン

#### 基本姿勢

- Draft で作る（CI とレビュー前に人に通知しないため）
- ラベルは既存のものから変更内容に合うものを選び、該当が無ければ付けない
- `.github/PULL_REQUEST_TEMPLATE.md` があればその構造を保って埋める
- テストと docs はタスクが求める範囲だけ
- 日本語と半角英数字の間は半角スペース

#### ブランチ命名規則

```text
{type}-{subject}

例:
- feat-user-profile
- fix-login-error
- refactor-api-client
```

#### コミットメッセージ

```text
{type}: {description}

例:
- feat: ユーザー認証 API の実装
- fix: ログイン エラーの修正
- docs: README の更新
```

### テンプレート処理システム

#### 処理優先順位

1. **既存 PR 説明**: 既に記述されている内容を**完全に踏襲**
2. **プロジェクトテンプレート**: `.github/PULL_REQUEST_TEMPLATE.md` 構造を維持
3. **デフォルトテンプレート**: 上記が存在しない場合

#### 既存内容保持ルール

- **一文字も変更しない**: 既に記述されている内容
- **空セクションのみ補完**: プレースホルダー部分を変更内容で埋める
- **機能的コメント保持**: `<!-- Copilot review rule -->` などを維持
- **HTML コメント保持**: `<!-- ... -->` を完全に保持
- **区切り線保持**: `---` などの構造を維持

#### HTML コメント保持の対処法

本文をコマンドライン引数や heredoc で渡すと、シェル処理で `EOF < /dev/null` などの不正な文字列が混入した事例があります。`--body-file` でファイル経由で渡せば回避できます。

**根本的解決策**:

1. **`gh pr create --body-file "$BODY"` の使用**: 本文をファイル経由で渡す。`gh api` は日本語推敲の PreToolUse hook の対象外で推敲ゲートを迂回するため使わない
2. **テンプレート処理の簡素化**: 複雑なパイプ処理やリダイレクトを避ける
3. **完全保持アプローチ**: HTML コメントは削除せず、テンプレートをそのまま保持する

### レビューコメント対応

```bash
# 変更後の再コミット
git add -p
git commit -m "fix: レビュー フィードバックに基づく修正"
git push
```

### 注意事項

#### HTML コメント保持の重要性

- **引数・heredoc 渡しの問題**: シェル処理で不正文字列が混入した事例がある
- **根本的回避策**: `--body-file` で本文をファイル経由で渡す（`gh api` は推敲 hook を迂回するため使わない）
- **テンプレート完全保持**: HTML コメントを削除せず、構造をそのまま維持

#### 自動化の制約

- **既存内容優先**: 手動で記述された内容は一切変更しない

#### 段階的品質向上

- **Draft で開始**: CI とレビューが通る前にレビュアーへ通知しないため
- **CI 確認**: `gh pr checks` で状態確認
- **Ready 移行**: 品質確認完了後に `gh pr ready`
- **テンプレート完全遵守**: プロジェクト固有の構造を維持
