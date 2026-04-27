---
name: semantic-commit
description: |
  `git diff HEAD` の大きな変更を機能境界・変更種別・依存関係で論理的に分割し、Conventional Commits 準拠（CommitLint 設定・既存履歴を尊重）のセマンティックなメッセージで順次コミットする。`--dry-run` で分割案だけ確認することも可能。複数機能・複数種別が混在する 5 ファイル/100 行以上の大きな変更を意味のある最小単位の連続コミットに整理したいときに使う。
---

# Semantic Commit

大きな変更を意味のある最小単位に分割し、セマンティックなコミットメッセージと共に順次コミットする。外部ツール非依存、git 標準コマンドのみを使用。

## 使い方

```bash
/semantic-commit [オプション]
```

### オプション

- `--dry-run`: 実際のコミットは行わず、提案される分割のみ表示
- `--lang <en|ja>`: コミットメッセージの言語を強制指定
- `--max-commits <N>`: 最大コミット数 (既定: 10)

### 基本例

```bash
/semantic-commit                  # 分析してコミット
/semantic-commit --dry-run        # 分割案のみ確認
/semantic-commit --lang en        # 英語で生成
/semantic-commit --max-commits 5  # 5 個に分割
```

## 動作フロー (5 ステップ)

```
- [ ] Step 1: 変更分析     git diff HEAD で全変更を取得
- [ ] Step 2: ファイル分類 機能境界・変更種別・依存関係でグループ化
- [ ] Step 3: 規約検出     CommitLint 設定 / 既存履歴 / プロジェクト種別を確認
- [ ] Step 4: コミット提案 各グループにセマンティックメッセージを生成
- [ ] Step 5: 順次実行     ユーザー確認後に各グループを順次コミット
```

各ステップで詳細が必要なときは下記の references/ を読む:

- **Step 2 の分割ロジック実装** → [references/algorithm.md](references/algorithm.md)
  - 大きな変更の検出条件、機能境界 / 変更種別 / 依存関係による分割、bash スニペット、6 ステップのアルゴリズム、言語判定
- **Step 3 の規約検出 / Step 4 のメッセージ生成** → [references/conventional-commits.md](references/conventional-commits.md)
  - Conventional Commits の形式・標準タイプ、CommitLint 設定の検出順序、Angular / Gitmoji / 日本語プロジェクトの実例
- **分割パターンの具体イメージが必要なとき** → [references/examples.md](references/examples.md)
  - 認証システム追加 / バグ修正とリファクタリング混在 / 複数機能同時開発の Before/After

## 出力例

```
変更分析中...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

検出された変更:
• src/auth/login.ts (修正)
• src/auth/register.ts (新規)
• src/auth/types.ts (修正)
• tests/auth.test.ts (新規)
• docs/authentication.md (新規)

提案されるコミット分割:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
コミット 1/3: feat: implement user registration and login system
  • src/auth/login.ts
  • src/auth/register.ts
  • src/auth/types.ts

コミット 2/3: test: add comprehensive tests for authentication system
  • tests/auth.test.ts

コミット 3/3: docs: add authentication system documentation
  • docs/authentication.md

この分割案でコミットを実行しますか? (y/n/edit):
```

## 実行時の選択肢

- `y`: 提案されたコミット分割で実行
- `n`: キャンセル
- `edit`: コミットメッセージを個別に編集
- `merge <番号 1> <番号 2>`: 指定したコミットをマージ
- `split <番号>`: 指定したコミットをさらに分割

## Gotchas

- **ステージ済みの変更は一旦リセットされる**: 実行前に重要な変更があれば `git stash` でバックアップ。
- **自動プッシュは行わない**: 完了後の `git push` は手動実行。
- **ブランチ作成は行わない**: 現在のブランチでコミット。新しいブランチが必要なら事前に `git checkout -b` する。
- **プリコミットフックで自動修正された場合**: `git add -u` で取り込んでから再コミットを試みる ([algorithm.md の retry ロジック](references/algorithm.md#3-エラーハンドリングとロールバック))。
- **CommitLint 設定があれば必ず優先する**: プロジェクトのカスタムタイプを無視して標準タイプにすると CI で reject される。優先順位は [conventional-commits.md](references/conventional-commits.md#プロジェクト規約の優先度) 参照。

## 前提条件

- Git リポジトリ内で実行
- 未コミットの変更が存在すること
- ステージングされた変更は一旦リセットされる

## ベストプラクティス

1. **プロジェクト規約の尊重**: CommitLint 設定 / 既存履歴を最優先
2. **小さな変更単位**: 1 コミット = 1 論理的変更
3. **明確なメッセージ**: 何を変更したかが一目で分かる
4. **関連性の重視**: 機能的に関連するファイルをグループ化
5. **テストの分離**: テストファイルは別コミットに
6. **設定ファイルの活用**: CommitLint を導入してチームで規約を統一

## トラブルシューティング

- **コミット失敗**: プリコミットフック / 依存関係 / 個別ファイル再試行 ([algorithm.md](references/algorithm.md#3-エラーハンドリングとロールバック))
- **分割が適切でない**: `--max-commits` で調整、`edit` モードで手動修正、より細かい単位で再実行
