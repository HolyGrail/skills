---
name: refactor
description: |
  Extract Method・Replace Conditional with Polymorphism などの技法で外部動作を変えずに段階的にリファクタリングし、SOLID 原則遵守状況とコードの臭い（God Object・Long Method・Duplicate Code 等）を評価する。長大メソッド・重複コード・ネストした条件分岐・TODO/FIXME を解消して保守性を上げたいときに使う。
---

## Refactor

安全で段階的なコードリファクタリングを実施し、SOLID 原則の遵守状況を評価します。

### 呼び出し例（例示）

```bash
/refactor src/services/order.ts        # 対象パスを指定
/refactor "processOrder の条件分岐"     # 対象の関数や観点を指定
```

### リファクタリング技法

#### Extract Method（メソッド抽出）

```javascript
// Before: 長大なメソッド
function processOrder(order) {
  // 50 行の複雑な処理
}

// After: 責任分離
function processOrder(order) {
  validateOrder(order);
  calculateTotal(order);
  saveOrder(order);
}
```

#### Replace Conditional with Polymorphism

```javascript
// Before: switch 文
function getPrice(user) {
  switch (user.type) {
    case 'premium': return basPrice * 0.8;
    case 'regular': return basePrice;
  }
}

// After: Strategy パターン
class PremiumPricing {
  calculate(basePrice) { return basePrice * 0.8; }
}
```

### SOLID 原則チェック

```
S - Single Responsibility
├─ 各クラスが単一の責任を持つ
├─ 変更理由が 1 つに限定される
└─ 責任の境界が明確

O - Open/Closed
├─ 拡張に対して開かれている
├─ 修正に対して閉じている
└─ 新機能追加時の既存コード保護

L - Liskov Substitution
├─ 派生クラスの置換可能性
├─ 契約の遵守
└─ 期待される動作の維持

I - Interface Segregation
├─ 適切な粒度のインターフェース
├─ 使用しないメソッドへの依存回避
└─ 役割別インターフェース定義

D - Dependency Inversion
├─ 抽象への依存
├─ 具象実装からの分離
└─ 依存性注入の活用
```

### リファクタリング手順

1. **現状分析**
   - 複雑度測定（循環的複雑度）
   - 重複コード検出
   - 依存関係の分析

2. **段階的実行**
   - 1 技法 = 1 変更単位
   - 各単位でテストを通す
   - コミットはユーザーの指示に従う

3. **品質確認**
   - 既存テストが通り、カバレッジを下げていない
   - 性能に影響しうる変更（ループ、クエリ、I/O の構造）だけ計測する

### よくあるコードの臭い

- **God Object**: 過度に多くの責務を持つクラス
- **Long Method**: 50 行を超える長いメソッド
- **Duplicate Code**: 同じロジックの重複
- **Large Class**: 300 行を超える大きなクラス
- **Long Parameter List**: 4 個以上のパラメータ

### 自動化支援

複雑度・lint・テストのコマンドは、プロジェクトの package.json / Makefile / mise から探して使う。`--fix` や `--write` の自動修正は変更したファイルにだけかける（無関係な整形差分がリファクタリングの差分に混ざるため）。

### 注意事項

- **機能変更の禁止**: 外部動作を変えない
- **外部動作の固定**: 対象の振る舞いを守るテストが無ければ、リファクタリングの前に追加する。追加するのはリポジトリが同種のコードにテストを持つ場合だけで、隣接ファイルと同じ粒度にする。テストの仕組みが無ければ追加せず、どう確かめたかを要約で報告する。scratch の確認を恒久テストにしない
- **段階的アプローチ**: 一度に大きな変更をしない
- **継続的検証**: 各ステップでのテスト実行
- **挙動の変更やバグは直さない**: 見つけても直さず、要約で報告する（リファクタリングは挙動不変が定義）
