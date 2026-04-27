# Before/After Examples

巨大コミットを意味のある単位に分割した実例集。SKILL.md 本体から「分割パターンの具体イメージが必要なとき」「分割効果をユーザーに説明するとき」に参照する。

## Contents
- [例 1: 大規模な認証システム追加](#例-1-大規模な認証システム追加)
- [例 2: バグ修正とリファクタリングの混在](#例-2-バグ修正とリファクタリングの混在)
- [例 3: 複数機能の同時開発](#例-3-複数機能の同時開発)
- [分割効果の比較](#分割効果の比較)

## 例 1: 大規模な認証システム追加

### Before (1 つの巨大なコミット)

```bash
# 変更されたファイル (15 ファイル、850 行変更)
src/auth/login.js          # 新規作成
src/auth/register.js       # 新規作成
src/auth/password.js       # 新規作成
src/auth/types.js          # 新規作成
src/api/auth-routes.js     # 新規作成
src/middleware/auth.js     # 新規作成
src/database/migrations/001_users.sql  # 新規作成
src/database/models/user.js            # 新規作成
tests/auth/login.test.js   # 新規作成
tests/auth/register.test.js # 新規作成
tests/api/auth-routes.test.js # 新規作成
docs/authentication.md     # 新規作成
package.json               # 依存関係追加
README.md                  # 使用方法追加
.env.example               # 環境変数例追加

# 従来の問題のあるコミット
feat: implement complete user authentication system with login, registration, password reset, API routes, database models, tests and documentation
```

### After (意味のある 5 つのコミットに分割)

```bash
# コミット 1: データベース基盤
feat(db): add user model and authentication schema

含まれるファイル:
- src/database/migrations/001_users.sql
- src/database/models/user.js
- src/auth/types.js

理由: データベース構造は他の機能の基盤となるため最初にコミット

# コミット 2: 認証ロジック
feat(auth): implement core authentication functionality

含まれるファイル:
- src/auth/login.js
- src/auth/register.js
- src/auth/password.js
- src/middleware/auth.js

理由: 認証の核となるビジネスロジックを一括でコミット

# コミット 3: API エンドポイント
feat(api): add authentication API routes

含まれるファイル:
- src/api/auth-routes.js

理由: API レイヤーは認証ロジックに依存するため後でコミット

# コミット 4: 包括的なテスト
test(auth): add comprehensive authentication tests

含まれるファイル:
- tests/auth/login.test.js
- tests/auth/register.test.js
- tests/api/auth-routes.test.js

理由: 実装完了後にテストを一括追加

# コミット 5: 設定とドキュメント
docs(auth): add authentication documentation and configuration

含まれるファイル:
- docs/authentication.md
- package.json
- README.md
- .env.example

理由: ドキュメントと設定は最後にまとめてコミット
```

## 例 2: バグ修正とリファクタリングの混在

### Before

```bash
# 変更されたファイル (8 ファイル、320 行変更)
src/user/service.js       # バグ修正 + リファクタリング
src/user/validator.js     # 新規作成 (リファクタリング)
src/auth/middleware.js    # バグ修正
src/api/user-routes.js    # バグ修正 + エラーハンドリング改善
tests/user.test.js        # テスト追加
tests/auth.test.js        # バグ修正テスト追加
docs/user-api.md          # ドキュメント更新
package.json              # 依存関係更新

# 問題のあるコミット
fix: resolve user validation bugs and refactor validation logic with improved error handling
```

### After (種別別に 3 つのコミットに分割)

```bash
# コミット 1: 緊急バグ修正
fix: resolve user validation and authentication bugs

含まれるファイル:
- src/user/service.js (バグ修正部分のみ)
- src/auth/middleware.js
- tests/auth.test.js (バグ修正テストのみ)

理由: 本番環境に影響するバグは最優先で修正

# コミット 2: バリデーションロジックのリファクタリング
refactor: extract and improve user validation logic

含まれるファイル:
- src/user/service.js (リファクタリング部分)
- src/user/validator.js
- src/api/user-routes.js
- tests/user.test.js

理由: 構造改善は機能単位でまとめてコミット

# コミット 3: ドキュメントと依存関係更新
chore: update documentation and dependencies

含まれるファイル:
- docs/user-api.md
- package.json

理由: 開発環境の整備は最後にまとめてコミット
```

## 例 3: 複数機能の同時開発

### Before

```bash
# 変更されたファイル (12 ファイル、600 行変更)
src/user/profile.js       # 新機能 A
src/user/avatar.js        # 新機能 A
src/notification/email.js # 新機能 B
src/notification/sms.js   # 新機能 B
src/api/profile-routes.js # 新機能 A 用 API
src/api/notification-routes.js # 新機能 B 用 API
src/dashboard/widgets.js  # 新機能 C
src/dashboard/charts.js   # 新機能 C
tests/profile.test.js     # 新機能 A 用テスト
tests/notification.test.js # 新機能 B 用テスト
tests/dashboard.test.js   # 新機能 C 用テスト
package.json              # 全機能の依存関係

# 問題のあるコミット
feat: add user profile management, notification system and dashboard widgets
```

### After (機能別に 4 つのコミットに分割)

```bash
# コミット 1: ユーザープロフィール機能
feat(profile): add user profile management

含まれるファイル:
- src/user/profile.js
- src/user/avatar.js
- src/api/profile-routes.js
- tests/profile.test.js

# コミット 2: 通知システム
feat(notification): implement email and SMS notifications

含まれるファイル:
- src/notification/email.js
- src/notification/sms.js
- src/api/notification-routes.js
- tests/notification.test.js

# コミット 3: ダッシュボードウィジェット
feat(dashboard): add interactive widgets and charts

含まれるファイル:
- src/dashboard/widgets.js
- src/dashboard/charts.js
- tests/dashboard.test.js

# コミット 4: 依存関係とインフラ更新
chore: update dependencies for new features

含まれるファイル:
- package.json
```

## 分割効果の比較

| 項目 | Before (巨大コミット) | After (適切な分割) |
|------|---------------------|-------------------|
| **レビュー性** | 困難 | 各コミットが小さくレビュー可能 |
| **バグ追跡** | 問題箇所の特定が困難 | 問題のあるコミットを即座に特定 |
| **リバート** | 全体をリバートする必要 | 問題部分のみをピンポイントでリバート |
| **並行開発** | コンフリクトが発生しやすい | 機能別でマージが容易 |
| **デプロイ** | 全機能を一括デプロイ | 段階的なデプロイが可能 |
