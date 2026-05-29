# Phases 5-6: PR / Post-PR / Cleanup

PR 作成からマージ後の片付けまでの 3 フェーズ詳細。SKILL.md 本体から「Phase 5 以降を実行するとき」「followup 自動 issue 化のロジックが必要なとき」に参照する。

## Contents
- [Phase 5: PR (プルリクエスト)](#phase-5-pr-プルリクエスト)
- [Phase 5-bis: Post-PR Iteration](#phase-5-bis-post-pr-iteration)
- [Phase 6: Cleanup (後片付け)](#phase-6-cleanup-後片付け)

---

## Phase 5: PR (プルリクエスト)

**目的**: 変更を Draft PR として作成する。

**注意**: git 操作は `git -C "$WT_PATH" ...`、`/pr-create` 等の委譲先スキルも `cd "$WT_PATH" && ...` で起点を揃える。

### 前提条件 (厳守)

Phase 5 に進む前に、以下を必ず満たす:

- Phase 3 の全検証が PASS、または
- 残る FAIL は全て「既存問題」かつ Phase 4-B でユーザーが「別 PR」または「スコープ外」を選択済み

新規問題が未解消、または既存問題でユーザー確認が未実施の状態で Phase 5 に進むのは禁止。

### 手順

1. git の状態確認: `git -C "$WT_PATH" status` / `git -C "$WT_PATH" branch --show-current`
2. 変更内容を分析してコミットメッセージを作成
3. コミット・プッシュ: `cd "$WT_PATH" && git add ... && git commit ... && git push -u origin "$BRANCH"`
4. **Test plan 構築**: 計画ファイルの「検証方法」節と Phase 3 結果から、PR body に含める Test plan チェックリストを作る (詳細は次節「Test plan 構築ルール」)
5. **PR body をファイルに書き出してから `gh pr create --body-file` で作成** (詳細は次節「PR body テンプレート」と「PR 作成コマンド」):
   - `--draft` 必須
   - **Claude Code デフォルトテンプレート (`## Summary` / `## Test plan` の素のプレースホルダ `[Bulleted markdown checklist of TODOs...]`) にフォールバックしない**。本フェーズで構築済みの body をそのまま使う
   - `/pr-create` slash command に **委譲しない** (デフォルトテンプレートに戻る原因になる)
6. 計画ファイルのステータスを `completed` に更新し、結果セクションを記入
7. **セッションファイル更新**:
   - `pr_url`: `gh pr view --json url -q .url` で取得
   - `status`: `"pr-open"`
   - `pr_opened_at`: ISO 8601 タイムスタンプ
   - `updated_at`: 同上 (以後の post-PR 修正で更新される)
8. ユーザーに PR URL を提示し、**「マージ後に `/dev cleanup` を実行すると worktree を掃除する」ことを明示**。必要なら post-PR 追加修正が `/dev resume <slug>` で再開できることも伝える

### Test plan 構築ルール

PR body の Test plan は **「自分で確認できる範囲は確認した状態で PR を出す」** ことを目的とする。Phase 3 の自動検証だけでは計画ファイル「検証方法」節の項目をカバーしきれないことがある (例: dev server を起動した上での疎通、ローカル DB へのマイグレーション適用など)。これらを **Phase 5 内で能動的に追加実行** し、`[x]` でチェック済みにする。

#### 1. 計画ファイルの「検証方法」節を全項目列挙する

各項目について、次の二択を判定する。

- **ローカル検証可能**: worktree 内で完結するコマンド・操作で検証できる。例:
  - 自動検証コマンド (`vitest`, `eslint`, `tsc`, `npm run build` 等)
  - dev server を起動した上での `curl` / HTTP リクエスト
  - ローカル DB / ローカルストレージ (D1 `--local`, sqlite ファイル, ローカル R2 等) への適用・読み出し
  - 生成されたファイルの存在確認・内容確認 (`ls`, `cat`, `grep`, スキーマ妥当性など)
  - ユニットテストや統合テスト (worktree 内で完結する範囲)
- **人手必須**: 上記で完結しない、人の判断・他環境への到達が必要なもの。例:
  - Browser での UI / UX 目視確認 (Playwright MCP 等で自動化していない限り)
  - staging / production / 他チーム環境への適用、デプロイ後の動作確認
  - 第三者による目視レビュー (デザインレビュー、セキュリティレビューの目視確認等)
  - 本番アカウントでの API 疎通、有償外部サービスでの動作確認
  - 「実機 (iOS / Android / 特定 OS バージョン) での動作確認」のような物理デバイス必須項目

判定が曖昧な場合 (例: マイグレーションの破壊的影響確認は本番データが必要か、ローカルでも十分か) は AskUserQuestion で確認する。**推測で「人手必須」に逃げない**。

#### 2. ローカル検証可能項目の処理

| 状態 | 処理 |
|---|---|
| Phase 3 で実行済み + PASS | `[x]` でチェック、Phase 3 結果 (コマンド + 結果) を併記 |
| Phase 3 で実行済み + FAIL かつ Phase 4 で解消 | `[x]` でチェック、最終的な PASS 結果を併記 |
| Phase 3 で未実行 | **Phase 5 内で能動的に実行する**。実行して PASS なら `[x]`、FAIL なら Phase 4-A の修正ループに戻る |
| 環境制約で実行不能 (依存ツール未インストール、ネットワーク隔離等) | `[ ]` のまま、項目に **「未実行 — 理由: <具体的な理由>」** を併記。**実行していないのに `[x]` を付けない** |

#### 3. 人手必須項目の処理

`[ ]` のまま残し、項目末尾に **「(人手必須)」** または「(レビュアー / リリース担当が確認)」を明記する。可能であれば確認手順 (URL、操作シーケンス、期待結果) を併記すると親切。

#### 4. 捏造禁止 (重要)

- **実行していない検証項目を `[x]` にしない**。
- **「ロールプレイ」「仮に PASS したものとして」「想定では成功」のような擬似結果を PR body に書かない**。
- 実行できなかった理由がある場合は `[ ]` + 未実行理由を明記する。
- ローカルで実行したが標準出力に PASS と明示されない種類のチェック (例: ファイル存在確認) は、観測した事実 (例: `ls migrations/0007_add_status.sql` の出力) を併記する。

### PR body テンプレート

Phase 5 (初回 PR 作成) の body は次のフォーマットで生成する。Phase 5-bis (Post-PR) のテンプレートとの差分は **「変更履歴」節の有無だけ** で、`## Test plan` を含む他の節は共通。Post-PR 追加修正が発生したら 5-bis で「変更履歴」節が足され、**Test plan 節はここで構築した内容を引き継いで最新化する** (5-bis で Test plan を落とさない)。

```markdown
## Summary

<3-7 行で変更の目的と主要な構成要素>

## 計画 / ADR

- 計画: `docs/plans/<YYYY-MM-DD>-<slug>.md`
- ADR: `docs/adr/...` (N 件、なければ「なし」と明記)

## 検証結果 (Phase 3 自動検証)

| チェック | コマンド | 結果 | 種別 |
|---------|---------|------|------|
| 型チェック | `tsc --noEmit` | PASS | 自動 |
| Lint     | `eslint .`   | PASS | 自動 |
| ...     | ...         | ...  | ...  |

## Test plan

ローカル検証可能項目 (Phase 3 + Phase 5 で実行済み):

- [x] <項目>: `<実行コマンド>` → <結果>
- [x] ...

人手必須項目 (マージ前にレビュアー / リリース担当が確認):

- [ ] <項目> (人手必須) — <確認手順 / 確認すべき URL / 期待結果>

未実行項目 (環境制約で Phase 5 内で実行できなかったもの、あれば):

- [ ] <項目> — 未実行 (理由: <具体的な理由>)

## 既存問題の対応方針 (あった場合のみ)

- [今回 PR で修正] <内容> — コミット `<sha>` で対応
- [別 PR] <followup の title> — cleanup 時に issue 化予定
- [スコープ外] <followup の title> — 本 PR では対応しない、cleanup 時に issue 化予定
```

### PR 作成コマンド

```bash
PR_BODY=$(mktemp -t pr-body.XXXXXX.md)
cat > "$PR_BODY" <<'EOF'
<上記テンプレートを Test plan 構築ルールに従って埋めたもの>
EOF

cd "$WT_PATH" && gh pr create \
  --draft \
  --base "$DEFAULT_BRANCH" \
  --head "$BRANCH" \
  --title "<コミットメッセージから派生したタイトル>" \
  --body-file "$PR_BODY"

rm -f "$PR_BODY"
```

`gh pr create` 実行後、`gh pr view --json url -q .url` で URL を取得しセッションファイルに記録する (手順 7)。

---

## Phase 5-bis: Post-PR Iteration

**目的**: Draft PR 作成後・マージ前の追加修正で、コード修正だけでなく **PR 本文・検証結果・ADR リンクも同期更新**してドキュメント整合性を保つ。

### 起動方法

- `/dev resume` で `status == "pr-open"` のセッションを選択 → 自動で post-PR モード
- `/dev resume <slug>` で直接指定
- cwd が `status == "pr-open"` の worktree 配下 → セッション逆引きで post-PR モード
- **通常の `/dev <説明>` では post-PR モードに入らない** (別タスク扱い)

### 前提条件

- セッションが存在し `status == "pr-open"`
- `gh pr view "$PR_URL" --json state -q .state` が `OPEN` (`MERGED` なら cleanup へ、`CLOSED` なら AskUserQuestion で再 open or 中止)
- worktree が存在し、リモート追跡ブランチが設定済み

### フロー

#### 1. セッション復元

- `WT_PATH` / `BRANCH` / `PR_URL` / `plan_file` をセッションファイルから読み込む
- Phase 0 の整合性チェック (worktree 存在、前提セットアップ設定) を再実行
- 現在の PR 本文を `gh pr view "$PR_URL" --json body -q .body` で取得してキャッシュ

#### 2. 追加修正を Phase 2 同等で実装

- 変更内容は TaskCreate で管理
- 設計判断が絡むなら ADR を追記 (新規 ADR 番号を採番)
- 計画ファイル (`docs/plans/...`) の「変更履歴」節を追記 (なければ作る)

#### 3. Phase 3 (検証) を再実行

- 全検証コマンドを再実行 (変更箇所に限定しない — 回帰検出のため)
- 失敗があれば Phase 4 の切り分けを再実行

#### 4. Phase 4 を再実行 (必要時)

- 新規 FAIL は修正
- 既存 FAIL が新たに見つかれば followups[] に追記 (Phase 4-B の手順)

#### 5. コミット + push

```bash
cd "$WT_PATH" && git add ... && git commit -m "..." && git push
```

PR のコミットは自動追従する (`gh pr edit` 不要)。

#### 6. PR 本文の再生成と更新 (重要、手動では忘れやすい)

**「再生成」は Test plan を捨てることではない**。本文を全文置換する都合上、Phase 5 で構築した `## Test plan` 節 (チェック済み / 未チェック項目) を必ず引き継いで最新化する。手順 1 で取得した現在の PR 本文 (`gh pr view ... --json body`) から既存 Test plan を回収し、追加修正分を反映させること。

PR 本文テンプレート (冒頭に変更履歴、以降は再生成。**`## Test plan` 節は維持・最新化する**):

```markdown
## Summary

<当初の変更内容サマリ + 追加修正のサマリを統合>

## 変更履歴

- YYYY-MM-DD: 初回実装 (計画 ${plan_file})
- YYYY-MM-DD: <追加修正の要約>  ← 今回追加
<...以降の追加修正も順に追記>

## 計画 / ADR

- 計画: `docs/plans/...`
- ADR: `docs/adr/...` (N 件)

## 検証結果 (最新)

| チェック | コマンド | 結果 | 種別 |
|---------|---------|------|------|
| ...     | ...     | PASS | -    |

## Test plan

ローカル検証可能項目 (Phase 3 + Phase 5 + 今回の追加修正で実行済み):

- [x] <項目>: `<実行コマンド>` → <結果>
- [x] ...

人手必須項目 (マージ前にレビュアー / リリース担当が確認):

- [ ] <項目> (人手必須) — <確認手順 / 確認すべき URL / 期待結果>

未実行項目 (環境制約で実行できなかったもの、あれば):

- [ ] <項目> — 未実行 (理由: <具体的な理由>)

## 既存問題の対応方針 (あれば)

- [別 PR] <followup[0].title> — 本 PR スコープ外、cleanup で issue 化予定
- [スコープ外] <followup[1].title> — 本 PR では対応しない、cleanup で issue 化予定
```

**Test plan は破棄しない (重要)**: 上記テンプレートの `## Test plan` 節は、Phase 5 で構築した内容を **引き継いで最新化する**。本文を `gh pr edit --body-file` で全文置換するため、Test plan 節を省くと初回 PR で構築済みのチェックリスト (`[x]` / `[]`) が消え、レビュアーが検証状況を追えなくなる。再生成時は次のように更新する:

- Phase 5 で `[x]` 済みの項目はそのまま維持 (再実行不要)
- 今回の追加修正で新たに検証が必要になった項目を追加し、Test plan 構築ルール ([Phase 5 の「Test plan 構築ルール」](#test-plan-構築ルール)) に従って実行・分類する
- 追加修正で既存の `[x]` 項目に回帰リスクがあれば、Phase 3 再実行 (手順 3) の結果で状態を更新する
- 捏造禁止は Phase 5 と同じく適用 (実行していない項目を `[x]` にしない)

現在の PR 本文は手順 1 で `gh pr view "$PR_URL" --json body -q .body` で取得済みなので、そこから既存の Test plan 節を回収して土台にすると取りこぼしが防げる。

更新コマンド:

```bash
NEW_BODY=$(mktemp)
cat > "$NEW_BODY" <<'EOF'
<上記テンプレートを slug / followups / 検証結果で埋めたもの>
EOF
gh pr edit "$PR_URL" --body-file "$NEW_BODY"
rm -f "$NEW_BODY"
```

heredoc は **クォート付き `<<'EOF'`** を使う (Phase 5 の `gh pr create` 例と同じ)。PR 本文には `` `tsc --noEmit` `` のようなバッククォートや `$` が含まれるため、クォートなし `<<EOF` だとシェルがコマンド置換・変数展開して本文が壊れる。テンプレートのプレースホルダは Claude が事前に解決して埋めるので、シェル変数展開に頼らない。

#### 7. title の更新 (必要時のみ)

- スコープが実質的に変わった場合のみ `gh pr edit "$PR_URL" --title "..."`
- 軽微な追加修正では title を変えない

#### 8. セッションファイル更新

- `updated_at`: ISO 8601 now
- 必要なら `followups[]` 追記 (Phase 4-B で発生した分)
- `post_pr_iterations`: カウンタ (何度 Phase 5-bis を回したか、任意)

#### 9. ユーザー報告

- 追加コミットの SHA、更新した PR 本文の要点、残 followup 数を提示
- 「さらに追加修正する場合は `/dev resume <slug>`」を再掲

### 禁止事項

- PR 本文を更新せずにコミット + push だけで終えない (レビュアーから変更履歴が追えなくなる)
- `gh pr edit --body` で本文を空にしない (`--body-file` を使う、`--body ""` は事故のもと)
- マージ済み (`state == MERGED`) の PR を post-PR モードで再開しない (cleanup へ誘導)

---

## Phase 6: Cleanup (後片付け)

**目的**: PR がマージされた後、worktree とブランチをローカルから削除し、セッションファイルを `cleaned` にする。

**起動方法**: 通常の `/dev` フロー (Phase 0→5) からは自動実行しない。PR マージ確認は分〜日単位の非同期タスクなので、ユーザーが明示的に `/dev cleanup` で起動。

### 呼び出し形態

- `/dev cleanup` — 引数なし
  - cwd を `git rev-parse --show-toplevel` で確認し、worktree 内なら対応セッションを特定
  - cwd が main リポジトリ側 or セッション外なら、`~/.claude/dev-sessions/*.json` のうち `status == "pr-open"` を AskUserQuestion で選択
- `/dev cleanup <branch>` — ブランチ名指定
  - ブランチ名からセッションファイルを逆引き

### 手順

#### 1. セッションファイル読み込み

```
WT_PATH / REPO_ROOT / BRANCH / PR_URL を取得
```

セッション不存在時は AskUserQuestion で「PR URL を指定 / 中止」を確認 (緊急回復フロー)。

#### 2. PR state の確認 (gh を真実とする)

```bash
STATE=$(gh pr view "$BRANCH" --json state -q .state 2>/dev/null)
# または PR_URL が分かっていれば
STATE=$(gh pr view "$PR_URL" --json state -q .state 2>/dev/null)
```

- `MERGED` → 続行
- `OPEN` / `CLOSED` / 取得失敗 → **自動削除はしない**。AskUserQuestion で:
  - 「PR マージを待つ」→ cleanup を中断
  - 「強制削除する (-D)」→ ユーザー明示同意のみ。理由を確認してログに残す
  - 「中止」→ 終了

#### 2.5. followup の自動 issue 化 (`MERGED` 確認後、worktree 削除前)

**目的**: Phase 4-B で「別 PR」「スコープ外」として記録された項目を、merge タイミングで GitHub issue として登録し、永遠の放置を防ぐ。

##### 1. followups の抽出

セッションファイルの `followups[]` を読む。空なら本手順スキップ。各要素のうち `issue_url != null` は既に issue 化済みなのでスキップ (再実行冪等性)。

##### 2. 既存 issue との重複チェック

```bash
# title の前半 40 文字で既存 issue を検索 (open/closed 両方、自リポジトリ限定)
SEARCH_KEY=$(echo "$title" | head -c 40)
EXISTING=$(gh issue list --state all --search "$SEARCH_KEY in:title" --json number,url --limit 5)
# PR リンクで逆引き (body に元 PR URL を含む issue があれば重複)
EXISTING_BY_PR=$(gh issue list --state all --search "\"$PR_URL\" in:body" --json number,url --limit 5)
```

どちらかで 1 件以上ヒット → **重複扱い**。該当 issue URL を `followup.issue_url` に記録して次へ。0 件 → 作成フェーズへ。

##### 3. ラベル候補の取得

`gh label list --json name` で既存ラベルを取得し、キーワードマッチで推定:

- `decision == "separate-pr"` → `followup` / `tech-debt` / `enhancement` のうち存在するもの
- `decision == "out-of-scope"` → `backlog` / `out-of-scope` / `followup` のうち存在するもの
- `source.kind == "existing-verification-failure"` なら `bug` を追加候補に

該当ラベルが 1 つも無ければラベルなしで作成 (ユーザーが後付けする前提)。

##### 4. 一括作成前のまとめ確認 (件数 ≥ 5 のときのみ AskUserQuestion)

```
質問: 未着手の followup を 7 件検出しました。GitHub issue として一括作成しますか?
選択肢:
  A. 全件作成する
  B. 選択して作成する (1 件ずつ確認)
  C. 今回は作成しない (セッションには残す、次回 cleanup で再チェック)
```

4 件以下なら確認せず全件自動作成 (低 friction 方針)。

##### 5. issue 作成

**body-file は必ず `mktemp` で動的パスを取得する** (`/tmp/followup-1.md` のような固定名は別セッション・別 worktree が同名ファイルを書き残しているリスクがあるため絶対に使わない。固定名を再利用すると、古いセッションが残した内容をそのまま投稿してしまい、タイトルと本文が乖離するハイブリッド issue が発生しうる)。

```bash
ISSUE_BODY=$(mktemp -t followup.XXXXXX)
cat > "$ISSUE_BODY" <<EOF
## Context

このタスクは [$PR_URL]($PR_URL) のマージ時に followup として自動登録されました。

**元の決定**: $decision (${decision == "separate-pr" ? "別 PR で対応" : "スコープ外"})
**発見経緯**: ${source.kind}
**関連計画**: \`${plan_file}\`

## 詳細

$body

---
_Auto-created by \`/dev cleanup\` from session \`${slug}\`_
EOF

# 投稿前に body-file の中身を必ず検証 (Write tool が <tool_use_error> で失敗しても
# 後続コマンドで気づけるように、想定文言を含むことを head で目視確認する)
head -c 300 "$ISSUE_BODY"
# 出力に "## Context" や PR_URL などタイトルから期待される文言が含まれるか確認。
# 含まれない / 全く別の話題に見える場合は投稿を中止し、ファイル生成からやり直す。

ISSUE_URL=$(gh issue create \
  --title "$title" \
  --body-file "$ISSUE_BODY" \
  ${labels:+--label "$labels"} \
  --json url -q .url)

rm -f "$ISSUE_BODY"
```

作成失敗時 (権限不足・API エラー等) は警告を出してその followup は `issue_url: null` のまま残す。次回 cleanup で再試行。

##### 6. セッションファイル更新

各 followup の `issue_url` フィールドに作成 URL を書き戻す (手順 7 の `status: cleaned` 更新と一緒にアトミックに書く)。

##### 7. ユーザー報告

作成した issue の一覧、重複扱いで既存 issue にマップされた件数を表示。

##### 禁止事項

- `gh issue create` の `--body` 引数に shell 展開で長文を渡さない (改行・引用符でクラッシュ) → 必ず `--body-file`
- `--body-file` のパスに `/tmp/followup-1.md` 等の **固定名を使わない**。必ず `mktemp -t followup.XXXXXX` で動的パスを取る (別 worktree / 別セッションが同じ `/tmp` を共有しているため、固定名は他セッションの古い内容を投稿する事故を起こす)
- **Write tool / `cat > $BODY` の結果を確認せずに `gh issue create` に進まない**。`head -c 300 "$BODY"` で先頭が想定通りか目視確認する。Write tool は `<tool_use_error>File has not been read yet` で拒否されることがあり、エラーを見逃すと「タイトルは新しい意図、本文は別セッションの古いファイル」というハイブリッド issue が作成される
- `issue_url` が既に入っている followup を再作成しない (冪等性違反)
- プロジェクトの issue テンプレートを無視しない — `.github/ISSUE_TEMPLATE/` があれば `--template` で指定するか、テンプレート本文を取り込んでから body 生成

#### 3. worktree の未コミット変更チェック

```bash
git -C "$WT_PATH" status --porcelain
```

出力があれば中断し、ユーザーに報告。**自動で破棄しない** (意図しない作業を消さないため)。

#### 4. 実行中プロセスの警告 (ベストエフォート、限定的)

```bash
lsof +D "$WT_PATH" 2>/dev/null | head
```

**注意**: この検査は worktree 内のファイルを開いているプロセス (worktree に `cd` したシェル等) しか捕まえない。**ポートだけを掴む dev server (例: `next dev`, `vite`, `rails server`) は検出されない**。ユーザーには「worktree で開いている shell や editor、バインドされた dev server をこちらで確認してから cleanup 実行」を促す。出力があれば警告のみ (kill はしない)。

#### 5. worktree + ブランチ削除

```bash
git -C "$REPO_ROOT" wt -d "$BRANCH"
```

- 成功 → 次へ
- 「not merged into default branch」等で拒否された場合 (squash/rebase merge で起こる):
  - 既に手順 2 で `MERGED` を確認済みなので、AskUserQuestion で「強制削除 (`-D`) を実行する?」を確認
  - 同意後: `git -C "$REPO_ROOT" wt -D "$BRANCH"`

#### 6. リモートブランチの削除確認

- GitHub 側で自動削除設定なら不要
- そうでなければ AskUserQuestion で「リモートブランチも削除?」を確認
  ```bash
  git -C "$REPO_ROOT" push origin --delete "$BRANCH"
  ```

#### 7. セッションファイル更新

```json
{
  ...既存フィールド,
  "status": "cleaned",
  "cleaned_at": "<ISO 8601 now>"
}
```

#### 8. 最終確認レポート

- 削除した worktree パス
- 削除したローカルブランチ
- リモートブランチの扱い (削除 / 保持)
- **作成した GitHub issue 一覧** (手順 2.5 の結果、新規 / 既存にマップされた件数)
- 参考: 残っている他セッション一覧 (`status: "pr-open"` / `"in-progress"`)

### 前提条件

以下が満たされない場合は中断:

- gh CLI で認証済み (`gh auth status`)
- セッションファイルが存在する or PR URL を引数で指定できる
- worktree に未コミット変更がない (あれば中断してユーザーに対応依頼)

### 禁止事項

- **PR state が MERGED でない状態で自動削除しない** (`-D` フォールバックは明示ユーザー同意時のみ)
- **未コミット変更を勝手に破棄しない**
- **実行中プロセスを勝手に kill しない** (警告のみ)
