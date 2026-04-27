---
name: role-debate
description: |
  security / performance / architect / frontend / mobile / analyzer など複数のロールが立場表明 → 反駁 → 妥協点探索 → 統合結論の 4 フェーズで議論し、トレードオフを定量的に検討して最適解を導く。技術選定（JWT vs Session、PostgreSQL vs MongoDB 等）や設計判断（マイクロサービス化の是非、認証 UX）でロール間に対立がある問題を多角的に決着させたいときに使う。
---

# Role Debate

異なる専門性を持つロールが議論し、トレードオフを検討して最適解を導出するスキル。

## 使い方

```bash
/role-debate <ロール 1>,<ロール 2> [議題]
/role-debate <ロール 1>,<ロール 2>,<ロール 3> [議題]
```

利用可能なロール: `security` / `performance` / `architect` / `frontend` / `mobile` / `analyzer` / `qa` / `reviewer`

## デフォルト組み合わせ (頻出パターン)

迷ったら以下のいずれかを起点にする。3 ロール以上は議論が発散しやすいので原則 2 ロール推奨。

| 議題のタイプ | 推奨ロール | 例 |
|---|---|---|
| **セキュリティ vs UX/パフォーマンス** | `security,performance` または `security,frontend` | JWT 有効期限、暗号化レベル、2FA UX、CSRF 対応 |
| **アーキテクチャ判断** | `architect,security` または `architect,performance` | マイクロサービス化、認証方式、API Gateway |
| **データ層選定** | `architect,performance` | PostgreSQL vs MongoDB、Redis 採用、N+1 対策 |
| **クライアント実装** | `frontend,mobile` または `frontend,performance` | React Native vs Flutter、SSR vs SPA、リッチ UI |
| **問題分析** | `analyzer,architect` または `analyzer,performance` | 根本原因 vs 対症療法、ボトルネック特定 |
| **3 者必要時 (大型判断)** | `architect,security,performance` | マイクロサービス化、認証基盤刷新 |

## 議論プロセス (4 フェーズ)

```
Phase 1: 初期立場表明     各ロールが専門視点から推奨案・根拠・懸念・成功指標を提示
Phase 2: 相互議論・反駁    クロス議論。建設的反論、見落とし指摘、トレードオフ明確化、代替案
Phase 3: 妥協点探索       各視点の重要度評価、Win-Win 模索、段階的実装、リスク軽減
Phase 4: 統合結論         合意解決策、実装ロードマップ、成功指標、見直しポイント
```

各フェーズの具体的なテンプレートと出力サンプルは [references/phases.md](references/phases.md)。

## 議論の基本原則

### 建設的議論の心得

- **相互尊重**: 他ロールの専門性と視点を尊重する
- **事実ベース**: 感情的反論ではなく、データ・根拠に基づく議論
- **解決志向**: 批判のための批判ではなく、より良い解決策を目指す
- **実装重視**: 理想論ではなく実現可能性を考慮した提案

### 論拠の質的要件

- **公式文書**: 標準・ガイドライン・公式ドキュメントへの言及
- **実証事例**: 成功事例・失敗事例の具体的引用
- **定量評価**: 可能な限り数値・指標での比較
- **時系列考慮**: 短期・中期・長期での影響評価

### 議論倫理

- **誠実性**: 自身の専門分野の限界も認める
- **開放性**: 新しい情報・視点に対する柔軟性
- **透明性**: 判断根拠・前提条件の明示
- **責任性**: 提案の実装リスクも含めて言及

## いつどの reference を読むか

- **特定ロールの議論スタンス・典型論点・偏見傾向を確認するとき** → [references/roles.md](references/roles.md)
  - Security / Performance / Architect / Frontend / Mobile / Analyzer の 6 ロール詳細 (議論スタンス・典型論点・論拠ソース・議論での強み・注意すべき偏見)
- **議論を実際に組み立てるとき / 出力フォーマットの参照が必要なとき** → [references/phases.md](references/phases.md)
  - 4 フェーズの詳細プロセス、Phase 1-3 のテンプレート、2 ロール議論のフル出力例 (JWT 有効期限の議論)、3 ロール議論の例 (マイクロサービス化)、議論品質チェックリスト

## 効果的な議論パターン

```bash
# 技術選定
/role-debate architect,performance     「データベース選択: PostgreSQL vs MongoDB」
/role-debate frontend,mobile           「UI フレームワーク: React vs Vue」
/role-debate security,architect        「認証方式: JWT vs Session Cookie」

# 設計判断
/role-debate security,frontend         「ユーザー認証の UX 設計」
/role-debate performance,mobile        「データ同期戦略の最適化」
/role-debate architect,qa              「テスト戦略とアーキテクチャ設計」

# トレードオフ問題
/role-debate security,performance      「暗号化レベル vs 処理速度」
/role-debate frontend,performance      「リッチ UI vs ページ読み込み速度」
/role-debate mobile,security           「利便性 vs データ保護レベル」
```

## Claude との連携

```bash
# 設計文書を元にした議論
cat system-design.md
/role-debate architect,security
「この設計のセキュリティ面での課題を議論して」

# 問題を元にした解決策議論
cat performance-issues.md
/role-debate performance,architect
「パフォーマンス問題の根本的解決策を議論して」

# 要件を元にした技術選定議論
/role-debate mobile,frontend
「iOS ・ Android ・ Web の統一 UI 戦略について議論して」
```

## Gotchas

- **3 ロール以上は議論が発散しやすい** — 大型判断 (マイクロサービス化等) でだけ使う。それ以外は 2 ロールで十分
- **ロールの典型偏見を意識する** — 例: Security は過度な保守性、Performance はセキュリティ軽視、Architect は実装詳細への理解不足。詳細は [roles.md の各ロール「注意すべき偏見」節](references/roles.md)
- **論拠が公式ドキュメント・実例・数値を欠くと議論の質が落ちる** — 「論拠ソース」を意識的に引く ([roles.md の各ロール「論拠ソース」節](references/roles.md))
- **議論は時間がかかる** — 複雑なトピックほど長時間。緊急性の高い問題では single role や `/role` を先に検討

## 注意事項

- **最終判断は議論結果を参考にユーザーが行う** — 議論は意思決定そのものではなく、判断材料の生成
- **緊急性の高い問題では single role / multi-role を先に検討** — 議論は判断時間に余裕があるときに
