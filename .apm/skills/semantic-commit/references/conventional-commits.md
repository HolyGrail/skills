# Conventional Commits & CommitLint Detection

Conventional Commits の基本仕様と、プロジェクト固有規約 (CommitLint 設定 / 既存コミット履歴) の検出ロジック。SKILL.md 本体から「コミットメッセージのフォーマットを決めるとき」「プロジェクト規約を尊重するとき」に参照する。

## Contents
- [基本形式](#基本形式)
- [標準タイプ](#標準タイプ)
- [スコープ](#スコープ)
- [Breaking Change](#breaking-change)
- [プロジェクト規約の自動検出](#プロジェクト規約の自動検出)
- [プロジェクト規約の例](#プロジェクト規約の例)
- [プロジェクト規約の優先度](#プロジェクト規約の優先度)
- [規約検出の実例](#規約検出の実例)

## 基本形式

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## 標準タイプ

**必須タイプ**:
- `feat`: 新機能 (ユーザーに見える機能追加)
- `fix`: バグ修正

**任意タイプ**:
- `build`: ビルドシステムや外部依存関係の変更
- `chore`: その他の変更 (リリースに影響しない)
- `ci`: CI 設定ファイルやスクリプトの変更
- `docs`: ドキュメントのみの変更
- `style`: コードの意味に影響しない変更 (空白、フォーマット、セミコロンなど)
- `refactor`: バグ修正や機能追加を伴わないコード変更
- `perf`: パフォーマンス改善
- `test`: テストの追加や修正

## スコープ

変更の影響範囲を示す:

```
feat(api): add user authentication endpoint
fix(ui): resolve button alignment issue
docs(readme): update installation instructions
```

## Breaking Change

API の破壊的変更がある場合:

```
feat!: change user API response format

BREAKING CHANGE: user response now includes additional metadata
```

または

```
feat(api)!: change authentication flow
```

## プロジェクト規約の自動検出

### 1. CommitLint 設定の検索

以下を順に検索し、最初に見つかったファイルを使用:

```
commitlint.config.mjs
commitlint.config.js
commitlint.config.cjs
commitlint.config.ts
.commitlintrc.js
.commitlintrc.json
.commitlintrc.yml
.commitlintrc.yaml
package.json (commitlint セクション)
```

```bash
find . -name "commitlint.config.*" -o -name ".commitlintrc.*" | head -1
cat commitlint.config.mjs
cat .commitlintrc.json
grep -A 10 '"commitlint"' package.json
```

### 2. 設定内容の解析

- 使用可能なタイプの一覧
- スコープの制限
- メッセージ長制限
- 言語設定 (詳細は [algorithm.md の言語判定ロジック](algorithm.md#言語判定ロジック))

### 3. 既存コミット履歴の分析

```bash
# 最近のコミットから使用パターンを学習
git log --oneline -100 --pretty=format:"%s" | head -20

# 使用タイプ統計
git log --oneline -100 --pretty=format:"%s" | \
  grep -oE '^[a-z]+(\([^)]+\))?' | \
  sort | uniq -c | sort -nr
```

### 4. フォールバック動作

設定ファイルが見つからない場合:

1. `git log` 分析でタイプを推測
2. Conventional Commits 標準 (`feat, fix, docs, style, refactor, perf, test, chore, build, ci`) をデフォルトに
3. 言語判定 ([algorithm.md](algorithm.md#言語判定ロジック))

## プロジェクト規約の例

### 標準的な commitlint.config.mjs

```javascript
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'docs', 'style', 'refactor', 'perf', 'test', 'chore']
    ],
    'scope-enum': [
      2,
      'always',
      ['api', 'ui', 'core', 'auth', 'db']
    ]
  }
}
```

### 日本語対応

```javascript
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'subject-case': [0],  // 日本語のため無効化
    'subject-max-length': [2, 'always', 72],
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'docs', 'style', 'refactor', 'test', 'chore']
    ]
  }
}
```

### カスタムタイプを含む設定

```javascript
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat', 'fix', 'docs', 'style', 'refactor', 'test', 'chore',
        'wip',      // 作業中
        'hotfix',   // 緊急修正
        'release',  // リリース
        'deps',     // 依存関係更新
        'config'    // 設定変更
      ]
    ]
  }
}
```

### Angular スタイル

```
feat(scope): add new feature
fix(scope): fix bug
docs(scope): update documentation
```

### Gitmoji 併用スタイル

```
✨ feat: add user registration
🐛 fix: resolve login issue
📚 docs: update API docs
```

### 日本語プロジェクト

```
feat: ユーザー登録機能を追加
fix: ログイン処理のバグを修正
docs: API ドキュメントを更新
```

## プロジェクト規約の優先度

コミットメッセージ生成時の優先度:

1. **CommitLint 設定** (最優先)
   - `commitlint.config.*` の設定
   - カスタムタイプやスコープの制限
   - メッセージ長やケースの制限
2. **既存コミット履歴** (第 2 優先)
   - 実際に使用されているタイプの統計
   - メッセージの言語 (日本語 / 英語)
   - スコープの使用パターン
3. **プロジェクト種別** (第 3 優先)
   - `package.json` → Node.js プロジェクト
   - `Cargo.toml` → Rust プロジェクト
   - `pom.xml` → Java プロジェクト
4. **Conventional Commits 標準** (フォールバック)
   - 設定が見つからない場合の標準動作

## 規約検出の実例

### Monorepo での scope 自動検出

```bash
# packages/ フォルダから scope を推測
ls packages/ | head -10
# → api, ui, core, auth などを scope として提案
```

### フレームワーク固有の規約

```javascript
// Angular プロジェクト
{
  'scope-enum': [2, 'always', [
    'animations', 'common', 'core', 'forms', 'http', 'platform-browser',
    'platform-server', 'router', 'service-worker', 'upgrade'
  ]]
}

// React プロジェクト
{
  'scope-enum': [2, 'always', [
    'components', 'hooks', 'utils', 'types', 'styles', 'api'
  ]]
}
```

### 企業・チーム固有の規約

```javascript
// 日本の企業でよく見られるパターン
{
  'type-enum': [2, 'always', [
    'feat', 'fix', 'docs', 'style', 'refactor', 'test', 'chore',
    'wip',      // 作業中 (プルリクエスト用)
    'hotfix',   // 緊急修正
    'release'   // リリース準備
  ]],
  'subject-case': [0],  // 日本語対応
  'subject-max-length': [2, 'always', 72]  // 日本語は長めに設定
}
```
