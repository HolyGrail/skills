---
description: |
  `mcp__codex__codex` ツール経由で OpenAI Codex (gpt-5.3-codex) にコード生成タスクを委任する。仕様が明確で自己完結した実装単位（関数・ボイラープレート・ユニットテスト・言語間変換）を生成したいときに使う。既存コードの分析・レビュー・複数ファイルにまたがるリファクタリングには使わない。
---

## Codex

Codex (OpenAI gpt-5.3-codex) にコード生成タスクを委任します。MCP 経由で Codex エージェントを呼び出し、実装コードを生成します。

### 使い方

/codex の後に実装したい内容を説明してください。

### 基本例

- 「UserService クラスに認証メソッドを実装して」
- 「src/utils/parser.ts のユニットテストを生成して」
- 「REST API の CRUD エンドポイントを Express.js で実装して」
- 「この Python スクリプトを Rust に変換して」

### Claude との連携

このコマンドが呼ばれたら：

1. 現在のプロジェクト構造・関連ファイル・型定義を確認
2. Codex に渡す明確で自己完結したプロンプトを英語で構築
3. `mcp__codex__codex` ツールを以下のパラメータで呼び出す:
   - `prompt`: 英語で具体的な実装指示
   - `approval-policy`: `"on-failure"`
   - `sandbox`: `"workspace-write"`（ファイル生成時）
   - `cwd`: 現在の作業ディレクトリ
   - **model は指定しない**（config.toml の `gpt-5.3-codex` を使用）
4. 生成コードをプロジェクト規約に合わせて調整
5. 結果をユーザーに提示

### 注意事項

- Codex は OpenAI の gpt-5.3-codex モデルを使用
- 生成コードは Claude がレビュー後にユーザーに提示
- 複雑なリファクタリングや既存コードの分析には不向き
