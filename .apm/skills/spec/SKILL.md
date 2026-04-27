---
name: spec
description: |
  Kiro 式 spec-driven development に準拠し、最小要件入力から Requirements Discovery → Design Exploration → Implementation Planning の 3 フェーズで EARS 記法・Mermaid 図・TypeScript インターフェースを生成し、各フェーズ承認後に requirements.md / design.md / tasks.md の 3 ファイルを出力する。新機能開発・複雑な機能改修・API/DB/UI 設計などプロトタイプから本番品質まで一貫した構造化仕様駆動で進めたいときに使う。
---

# Spec

**「コードを書く前に構造を与える」** — Kiro の spec-driven development に完全準拠。

わずかな要件入力から、プロダクトマネージャーレベルの詳細な仕様と実装可能な設計まで段階的に展開し、**プロトタイプから本番環境**まで一貫した品質を保証する。

## 使い方

```
「[機能説明] の spec を作成して」
```

最小限の要件入力から:
1. 詳細なユーザーストーリーを自動生成
2. EARS 記法で構造化要件
3. 段階的対話を通じた仕様の精緻化
4. 3 つの独立したファイルを生成 (`requirements.md` / `design.md` / `tasks.md`)

## 3 フェーズ概要

```
Phase 1: Requirements Discovery & Discussion
  ├─ 最小入力 → 詳細なユーザーストーリーへ自動拡張
  ├─ EARS 記法で構造化要件を起こす
  ├─ セキュリティ要件 / エッジケースを自動補完
  └─ 承認 → requirements.md 生成

Phase 2: Design Exploration & Discussion
  ├─ コードベース分析 (既存パターン・スタック検出)
  ├─ Mermaid 図でアーキテクチャ・データフローを視覚化
  ├─ TypeScript インターフェースで型定義を自動生成
  └─ 承認 → design.md 生成

Phase 3: Implementation Planning & Discussion
  ├─ ベストプラクティスを自動適用 (OWASP / Clean Architecture / 性能)
  ├─ 段階別品質チェックポイントを自動設定
  ├─ 依存関係・リスク軽減策を自動分析して実装順序を最適化
  └─ 承認 → tasks.md 生成
```

各フェーズの完了 → ファイル生成のタイミングは `「次に進んで」` トリガーで明示制御する。

## いつどの reference を読むか

- **各 Phase の対話プロセスを進めるとき / 出力サンプル (EARS / Mermaid / TypeScript) が必要なとき** → [references/phases.md](references/phases.md)
  - 各 Phase の対話例、最小入力からのユーザーストーリー自動拡張、EARS 記法フル形式、アーキテクチャ Mermaid、Domain entity TypeScript、品質チェックポイントの段階別チェックリスト、実装順序の Week 単位ロードマップ、実行例
- **Kiro の独自機能 / 実証された効果 / `/spec` と `/plan` の比較が必要なとき** → [references/features.md](references/features.md)
  - 自動生成機能 (Mermaid / TypeScript / ベストプラクティス / 品質チェックポイント)、hooks 連携、Kiro 実績 (2 日でセキュアアプリ等)、基本例・詳細例、/plan との比較表、推奨ユースケース

## トリガーフレーズとコントロール

### 開始トリガー

- 「[機能名] の spec を作成して」
- 「spec 駆動で [機能名] を開発したい」
- 「仕様書から [機能名] を設計して」

### フェーズ進行制御

- **「次に進んで」**: 現在のフェーズを完了してファイル生成、次フェーズへ
- **「修正して」**: 現在のフェーズ内で内容を調整・改善
- **「やり直して」**: 現在のフェーズを最初からやり直し
- **「詳しく説明して」**: より詳細な説明や選択肢を提示
- **「スキップして」**: 現フェーズをスキップして次へ (非推奨)

### ファイル生成タイミング

```
Phase 1 完了 → 「次に進んで」 → requirements.md 生成
Phase 2 完了 → 「次に進んで」 → design.md 生成
Phase 3 完了 → 「次に進んで」 → tasks.md 生成
```

## Gotchas

- **要件の曖昧さは Phase 1 で解消する** — 設計段階で要件を後追い修正すると design.md が破綻する
- **設計完了後に実装タスクを生成する** — Phase 2 をスキップして Phase 3 に進むと依存関係分析が効かない
- **各段階の承認プロセスを軽視しない** — 「次に進んで」を待たず勝手にファイル生成すると、ユーザーが意図しない方向に固定されてしまう
- **小さな修正には適用しない** — 単純な変更や 1 ファイルの修正には通常の実装フローを使う。`/spec` は新規機能・複雑な改修専用

## 注意事項

- **適用範囲**: 機能実装に最適化。単純な修正や小規模変更には通常の実装フローを使う
- **品質保証**: 各段階での完了基準を明確化し、テストとアクセシビリティを含む包括的な品質基準を適用する
- **大規模な系全体の設計は `/plan`** を使う ([features.md の比較表](references/features.md#plan-との違い))
