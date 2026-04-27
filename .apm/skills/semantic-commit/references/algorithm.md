# Splitting Algorithm

`git diff HEAD` の大きな変更を「意味のある最小単位」に分割するためのアルゴリズム詳細・bash スニペット集。SKILL.md 本体から「分割ロジックを実装するとき」「言語判定が必要なとき」に参照する。

## Contents
- [大きな変更の検出](#大きな変更の検出)
- [分割戦略](#分割戦略)
- [ファイル単位の詳細分析](#ファイル単位の詳細分析)
- [論理的グループ化の基準](#論理的グループ化の基準)
- [Git 標準コマンドによる順次コミット実装](#git-標準コマンドによる順次コミット実装)
- [分割アルゴリズム ステップ 1-6](#分割アルゴリズム-ステップ-1-6)
- [言語判定ロジック](#言語判定ロジック)

## 大きな変更の検出

以下の条件のいずれかに該当する場合「大きな変更」とみなして分割を推奨:

1. 変更ファイル数 ≥ 5
2. 変更行数 ≥ 100
3. 機能領域が 2 つ以上にまたがる
4. `feat` + `fix` + `docs` 等の種別が混在

```bash
CHANGED_FILES=$(git diff HEAD --name-only | wc -l)
CHANGED_LINES=$(git diff HEAD --stat | tail -1 | grep -o '[0-9]\+ insertions\|[0-9]\+ deletions' | awk '{sum+=$1} END {print sum}')

if [ $CHANGED_FILES -ge 5 ] || [ $CHANGED_LINES -ge 100 ]; then
  echo "大きな変更を検出: 分割を推奨"
fi
```

## 分割戦略

### 1. 機能境界による分割

```bash
git diff HEAD --name-only | cut -d'/' -f1-2 | sort | uniq
# → src/auth, src/api, components/ui など
```

### 2. 変更種別による分離

```bash
git diff HEAD --name-status | grep '^A' # 新規ファイル
git diff HEAD --name-status | grep '^M' # 修正ファイル
git diff HEAD --name-status | grep '^D' # 削除ファイル
```

### 3. 依存関係の分析

```bash
git diff HEAD | grep -E '^[+-].*import|^[+-].*require' | \
  cut -d' ' -f2- | sort | uniq
```

## ファイル単位の詳細分析

```bash
# 変更されたファイル一覧
git diff HEAD --name-only

# 各ファイルの変更内容
git diff HEAD -- <file>

# 変更タイプの判定
git diff HEAD --name-status | while read status file; do
  case $status in
    A) echo "$file: 新規作成" ;;
    M) echo "$file: 修正" ;;
    D) echo "$file: 削除" ;;
    R*) echo "$file: リネーム" ;;
  esac
done
```

## 論理的グループ化の基準

1. **機能単位**: 同一機能に関連するファイル
   - `src/auth/` 配下のファイル → 認証機能
   - `components/` 配下のファイル → UI コンポーネント
2. **変更種別**: 同じ種類の変更
   - テストファイルのみ → `test:`
   - ドキュメントのみ → `docs:`
   - 設定ファイルのみ → `chore:`
3. **依存関係**: 相互に関連するファイル
   - モデル + マイグレーション
   - コンポーネント + スタイル
4. **変更規模**: 適切なコミットサイズの維持
   - 1 コミットあたり 10 ファイル以下
   - 関連性の高いファイルをグループ化

## Git 標準コマンドによる順次コミット実装

### 1. 前処理

```bash
git reset HEAD
git status --porcelain > /tmp/original_state.txt
CURRENT_BRANCH=$(git branch --show-current)
echo "作業中のブランチ: $CURRENT_BRANCH"
```

### 2. グループ別の順次コミット実行

```bash
while IFS= read -r commit_plan; do
  group_num=$(echo "$commit_plan" | cut -d':' -f1)
  files=$(echo "$commit_plan" | cut -d':' -f2- | tr ' ' '\n')

  echo "=== コミット $group_num の実行 ==="

  echo "$files" | while read file; do
    if [ -f "$file" ]; then
      git add "$file"
      echo "ステージング: $file"
    fi
  done

  staged_files=$(git diff --staged --name-only)
  if [ -z "$staged_files" ]; then
    echo "警告: ステージングされたファイルがありません"
    continue
  fi

  commit_msg=$(generate_commit_message_for_staged_files)

  echo "提案コミットメッセージ: $commit_msg"
  echo "ステージングされたファイル:"
  echo "$staged_files"
  read -p "このコミットを実行しますか? (y/n): " confirm

  if [ "$confirm" = "y" ]; then
    git commit -m "$commit_msg"
    echo "コミット $group_num 完了"
  else
    git reset HEAD
    echo "コミット $group_num をスキップ"
  fi
done < /tmp/commit_plan.txt
```

### 3. エラーハンドリングとロールバック

```bash
commit_with_retry() {
  local commit_msg="$1"
  local max_retries=2
  local retry_count=0

  while [ $retry_count -lt $max_retries ]; do
    if git commit -m "$commit_msg"; then
      echo "コミット成功"
      return 0
    else
      echo "コミット失敗 (試行 $((retry_count + 1))/$max_retries)"

      # プリコミットフックによる自動修正を取り込み
      if git diff --staged --quiet; then
        echo "プリコミットフックにより変更が自動修正されました"
        git add -u
      fi

      retry_count=$((retry_count + 1))
    fi
  done

  echo "コミットに失敗しました。手動で確認してください。"
  return 1
}

resume_from_failure() {
  echo "中断されたコミット処理を検出しました"
  echo "現在のステージング状態:"
  git status --porcelain

  read -p "処理を続行しますか? (y/n): " resume
  if [ "$resume" = "y" ]; then
    last_commit=$(git log --oneline -1 --pretty=format:"%s")
    echo "最後のコミット: $last_commit"
  else
    git reset HEAD
    echo "処理をリセットしました"
  fi
}
```

### 4. 完了後の検証

```bash
remaining_changes=$(git status --porcelain | wc -l)
if [ $remaining_changes -eq 0 ]; then
  echo "すべての変更がコミットされました"
else
  echo "未コミットの変更が残っています:"
  git status --short
fi

echo "作成されたコミット:"
git log --oneline -n 10 --graph
```

### 5. 自動プッシュの抑制

`git push` は自動実行しない。完了後にユーザーへ案内する:

```
git push origin <CURRENT_BRANCH>
```

## 分割アルゴリズム ステップ 1-6

### ステップ 1: 初期分析

```bash
git diff HEAD --name-status | while read status file; do
  echo "$status:$file"
done > /tmp/changes.txt

git diff HEAD --name-only | cut -d'/' -f1-2 | sort | uniq -c
```

### ステップ 2: 機能境界による初期グループ化

```bash
GROUPS=$(git diff HEAD --name-only | cut -d'/' -f1-2 | sort | uniq)
for group in $GROUPS; do
  echo "=== グループ: $group ==="
  git diff HEAD --name-only | grep "^$group" | head -10
done
```

### ステップ 3: 変更内容の類似性分析

```bash
git diff HEAD --name-only | while read file; do
  NEW_FUNCTIONS=$(git diff HEAD -- "$file" | grep -c '^+.*function\|^+.*class\|^+.*def ')
  BUG_FIXES=$(git diff HEAD -- "$file" | grep -c '^+.*fix\|^+.*bug\|^-.*error')

  if [[ "$file" =~ test|spec ]]; then
    echo "$file: TEST"
  elif [ $NEW_FUNCTIONS -gt 0 ]; then
    echo "$file: FEAT"
  elif [ $BUG_FIXES -gt 0 ]; then
    echo "$file: FIX"
  else
    echo "$file: REFACTOR"
  fi
done
```

### ステップ 4: 依存関係による調整

```bash
git diff HEAD | grep -E '^[+-].*import|^[+-].*from.*import' | \
  while read line; do
    echo "$line" | sed 's/^[+-]//' | awk '{print $2}'
  done | sort | uniq > /tmp/imports.txt

git diff HEAD --name-only | while read file; do
  basename=$(basename "$file" .js .ts .py)
  related=$(git diff HEAD --name-only | grep "$basename" | grep -v "^$file$")
  if [ -n "$related" ]; then
    echo "関連ファイル群: $file <-> $related"
  fi
done
```

### ステップ 5: コミットサイズの最適化

```bash
MAX_FILES_PER_COMMIT=8
current_group=1
file_count=0

git diff HEAD --name-only | while read file; do
  if [ $file_count -ge $MAX_FILES_PER_COMMIT ]; then
    current_group=$((current_group + 1))
    file_count=0
  fi
  echo "コミット $current_group: $file"
  file_count=$((file_count + 1))
done
```

### ステップ 6: 最終グループ決定

```bash
for group in $(seq 1 $current_group); do
  files=$(grep "コミット $group:" /tmp/commit_plan.txt | cut -d':' -f2-)
  lines=$(echo "$files" | xargs git diff HEAD -- | wc -l)
  echo "コミット $group: $(echo "$files" | wc -w) ファイル, $lines 行変更"
done
```

## 言語判定ロジック

### 判定材料

1. **CommitLint 設定** (+3 点)
   ```bash
   grep -E '"subject-case".*\[0\]|subject-case.*0' commitlint.config.*
   ```
2. **git log 分析** (最大 +2 点)
   ```bash
   git log --oneline -20 --pretty=format:"%s" | \
     grep -E '^[あ-ん]|[ア-ン]|[一-龯]' | wc -l
   # 50% 以上が日本語なら日本語モード
   ```
3. **README.md 確認** (+1 点)
   ```bash
   head -10 README.md | grep -E '^[あ-ん]|[ア-ン]|[一-龯]' | wc -l
   ```
4. **package.json description 確認** (+1 点)
   ```bash
   grep -E '"description".*[あ-ん]|[ア-ン]|[一-龯]' package.json
   ```
5. **変更ファイル内コメント** (+1 点)
   ```bash
   git diff HEAD | grep -E '^[+-].*//.*[あ-ん]|[ア-ン]|[一-龯]' | wc -l
   ```

### 判定アルゴリズム

```bash
JAPANESE_SCORE=0

# 1. CommitLint 設定 (+3)
if grep -q '"subject-case".*\[0\]' commitlint.config.* 2>/dev/null; then
  JAPANESE_SCORE=$((JAPANESE_SCORE + 3))
fi

# 2. git log 分析 (最大 +2)
JAPANESE_COMMITS=$(git log --oneline -20 --pretty=format:"%s" | \
  grep -cE '[あ-ん]|[ア-ン]|[一-龯]' 2>/dev/null || echo 0)
if [ $JAPANESE_COMMITS -gt 10 ]; then
  JAPANESE_SCORE=$((JAPANESE_SCORE + 2))
elif [ $JAPANESE_COMMITS -gt 5 ]; then
  JAPANESE_SCORE=$((JAPANESE_SCORE + 1))
fi

# 3. README.md 確認 (+1)
if head -5 README.md 2>/dev/null | grep -qE '[あ-ん]|[ア-ン]|[一-龯]'; then
  JAPANESE_SCORE=$((JAPANESE_SCORE + 1))
fi

# 4. 変更ファイル内容確認 (+1)
if git diff HEAD 2>/dev/null | grep -qE '^[+-].*[あ-ん]|[ア-ン]|[一-龯]'; then
  JAPANESE_SCORE=$((JAPANESE_SCORE + 1))
fi

# 判定: 3 点以上で日本語モード
if [ $JAPANESE_SCORE -ge 3 ]; then
  LANGUAGE="ja"
else
  LANGUAGE="en"
fi
```
