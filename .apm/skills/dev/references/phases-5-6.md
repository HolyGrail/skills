# Phases 5-6: PR / Post-PR / Cleanup

PR 作成からマージ後の片付けまでの 3 フェーズ詳細。SKILL.md 本体から「Phase 5 以降を実行するとき」「followup 自動 issue 化のロジックが必要なとき」に参照する。

## Contents
- [Phase 5: PR (プルリクエスト)](#phase-5-pr-プルリクエスト)
- [Phase 5-bis: Post-PR Iteration](#phase-5-bis-post-pr-iteration)
- [Phase 6: Cleanup (後片付け)](#phase-6-cleanup-後片付け)

---

## Phase 5: PR (プルリクエスト)

**目的**: 変更を **Open PR** として作成し (Draft にしない)、Phase 5.5 (CI + Review Loop) へ自動続行する。

**注意**: git 操作は `git -C "$WT_PATH" ...`、`/pr-create` 等の委譲先スキルも `cd "$WT_PATH" && ...` で起点を揃える。

### 前提条件

Phase 5 に進む前に、以下を満たす:

- Phase 3 の全検証が PASS、または
- 残る FAIL は全て「既存問題」かつ Phase 4-B の自動判断マトリクスで「separate-pr」または「out-of-scope」が確定済み (PR 本文に明記する前提)

新規問題が未解消なら main を壊しうる PR になり、既存問題の対応が未確定なら PR 本文の「既存問題の対応方針」節が書けない。どちらかが残っている間は Phase 5 に進まない。

### 手順

1. git の状態確認: `git -C "$WT_PATH" status` / `git -C "$WT_PATH" branch --show-current`
2. 変更内容を分析してコミットメッセージを作成し、ローカルにコミットする (push はまだしない)
3. **PR 作成前ローカルレビュー (条件付き)** (詳細は次節「PR 作成前ローカルレビュー」): 変更が並行制御、状態遷移、永続化、schema、認可のいずれかに触れる、または変更行数が 500 を超えるときだけ、`scripts/local-codex-review.sh` で変更全体を AGENTS.md の基準でレビューし、P1/P2 を直してから push する。それ以外は掛けずに PR を開き、最初の広い発見は「徹底的なコードレビュー」を ON にしたクラウドのレビュー (2026-09-07 以降) に任せる。ローカルの 1 パスは週間利用枠の 0.5〜1% を消費し、クラウドのレビューと同じメーターに載る (2026-09-07 実測)。セッションに `review` オブジェクトがまだ無ければ、この手順で [session-management.md](session-management.md#スキーマ) の初期値 (`loop_status: null`、`push_rounds: 0`、`findings: []` など) で作り、`local_review_passes` と `head_local_review` (掛けなかったときは `"cloud-first"`) をここに書く。レビューの指摘で直したら Phase 3 の検証を再実行し (手順 5 の Test plan はこの結果から作る)、直した分を手順 4 の前にコミットし、`git -C "$WT_PATH" status --porcelain` が空であることを確かめる
4. プッシュ: `cd "$WT_PATH" && git push -u origin "$BRANCH"`
5. **Test plan 構築**: 計画 issue の「検証方法」節と Phase 3 結果から、PR body に含める Test plan チェックリストを作る (詳細は「Test plan 構築ルール」)
6. **PR body をファイルに書き出してから `gh pr create --body-file` で作成** (詳細は「PR body テンプレート」と「PR 作成コマンド」)。本文には「レビュアー向けの前提」節を含める (意図、不変条件、意図的に対応しないこと、環境制約、ローカルレビューの結果):
   - **`--draft` を付けない (Open PR として作成する)**。Codex が設定されたリポジトリでは PR open をトリガーに自動レビューが走り、CI もこの時点で起動する — Phase 5.5 がそのまま両方を監視する
   - **Claude Code デフォルトテンプレート (`## Summary` / `## Test plan` の素のプレースホルダ `[Bulleted markdown checklist of TODOs...]`) にフォールバックしない**。本フェーズで構築済みの body をそのまま使う
   - `/pr-create` slash command に **委譲しない** (デフォルトテンプレートに戻る原因になる)
7. 計画 issue の本文を更新: ステータス行を `completed` にし、「結果」節を記入する (`gh issue edit <番号> --body-file`、mktemp + head 検証 + cognitive-rhythm-writing 推敲のルールは issue 作成時と同じ)。**issue のクローズはここでは行わない** — この PR で計画 issue の全項目が完結するなら PR body の `Closes #<番号>` によるマージ時自動クローズに任せ、計画 issue が複数 PR で消化するチェックリスト形式なら `Closes` を使わず部分消化を明示する (グローバル CLAUDE.md「マルチ PR で消化する issue」)
8. **セッションファイル更新**:
   - `pr_url`: `gh pr view --json url -q .url` で取得
   - `status`: `"pr-open"`
   - `pr_opened_at`: ISO 8601 タイムスタンプ
   - `updated_at`: 同上 (以後の post-PR 修正で更新される)
   - `review.local_review_passes` と `review.head_local_review`: 手順 3 の結果
9. **Phase 5.5 (CI + Review Loop) へ自動続行する**: PR URL をユーザーにナレーションで提示した上で、そのまま [phase-5.5-review-loop.md](phase-5.5-review-loop.md) の監視ループに入る (`/dev review` の明示起動を待たない)。relay モードなら、最初の待機も [待ち方](phase-5.5-review-loop.md#relay-モード) に従う。CI 全成功 + レビュー収束 (approved / converged) で終端し、完了報告とあわせて次を案内する:
   - 人手主導で追加修正したい場合は `/dev resume <slug>` (Phase 5-bis)
   - セッションが中断した場合は `/dev review <slug>` でループを再開できる
   - **マージ後に `/dev cleanup` を実行すると worktree を掃除する**

### PR 作成前ローカルレビュー

Codex のクラウドレビューは 1 パスに 1〜2 件ずつしか指摘を出さなかった (2026-03〜09 の 506 ラウンドで 1 件が 74%、2 件が 22%)。2026-09-07 に「徹底的なコードレビュー」を全リポジトリで ON にしたので、最初の広い発見はクラウドに任せ、ローカルのレビューはリスクの高い変更に限る。ローカルの 1 パスは合計 100〜120 万トークン (9 割はキャッシュ入力) で、週間利用枠の 0.5〜1% を消費する。クラウドのレビューと同じメーターに載るので、掛けた分だけクラウドの往復を減らせなければ損になる。

掛ける条件: 変更が並行制御、状態遷移、永続化、schema、認可のいずれかに触れる、または変更行数が 500 を超える。どちらにも当たらなければ掛けずに PR を開き、`review.head_local_review = "cloud-first"` と記録する。

```bash
SCRIPT=~/.claude/skills/dev/references/scripts/local-codex-review.sh
# 1 パス 4〜6 分 (関連テストの実行や実 DB での再現を含む)。run_in_background で起動し、完了通知で戻る
"$SCRIPT" "$WT_PATH" "origin/$DEFAULT_BRANCH"
```

- **1 パス目**: 変更全体を対象にする。出た P1/P2 は成立を一次情報で確認し、成立するものを Phase 4 の修正ループで直す (修復の考え方は [phase-5.5-review-loop.md 手順 4〜5](phase-5.5-review-loop.md#4-修復記録))。P3 は `followups[]` に記録する
- **2 パス目** (1 パス目で P1/P2 が出て直した場合のみ): `--focus "<直した振る舞いと影響先>"` を付けて掛ける。ここでも P1/P2 が出て直したら、その head はローカルレビューを通っていない。`review.head_local_review = "unreviewed"` として記録し、PR 本文の「レビュアー向けの前提」にその旨を書く。3 パス目は掛けない (ループを手元で再現するだけになる)
- codex CLI が無い、またはタイムアウトしたときは `head_local_review = "skipped"` と理由を記録して続行する
- パスごとに見つかる集合は変わる。ローカルで出なかった指摘がクラウドで出ることはある。それは Phase 5.5 で処理する
- 掛けたパス数を `review.local_review_passes` に記録する。効果は `~/.claude/tools/codex-review-metrics/compare.py` の表 D (ローカル事前レビュー別のクラウド 1 ラウンド目の指摘数) で確かめる

### Test plan 構築ルール

PR body の Test plan は **「自分で確認できる範囲は確認した状態で PR を出す」** ことを目的とする。Phase 3 の自動検証だけでは計画 issue「検証方法」節の項目をカバーしきれないことがある (例: dev server を起動した上での疎通、ローカル DB へのマイグレーション適用など)。これらを **Phase 5 内で能動的に追加実行** し、`[x]` でチェック済みにする。

#### 1. 計画 issue の「検証方法」節を全項目列挙する

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

判定が曖昧な場合 (例: マイグレーションの破壊的影響確認は本番データが必要か、ローカルでも十分か) は「worktree 内で実行する手段が組めるか」を基準に自分で判定する。組めるなら実行して `[x]`、組めないなら人手必須に分類し、**何が足りなくてローカルで実行できないのか**を理由として併記する。**推測で「人手必須」に逃げない** — 実行手段を検討した形跡を理由に残す。

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

- **実行していない検証項目を `[x]` にしない**。**「ロールプレイ」「仮に PASS したものとして」「想定では成功」のような擬似結果も PR body に書かない**。
- 実行できなかった理由がある場合は `[ ]` + 未実行理由を明記する。
- ローカルで実行したが標準出力に PASS と明示されない種類のチェック (例: ファイル存在確認) は、観測した事実 (例: `ls migrations/0007_add_status.sql` の出力) を併記する。

### PR body テンプレート

Phase 5 (初回 PR 作成) の body は次のフォーマットで生成する。Phase 5-bis (Post-PR) のテンプレートとの差分は **「変更履歴」節の有無だけ** で、`## Test plan` を含む他の節は共通。Post-PR 追加修正が発生したら 5-bis で「変更履歴」節が足され、**Test plan 節はここで構築した内容を引き継いで最新化する** (5-bis で Test plan を落とさない)。

```markdown
## Summary

<3-7 行で変更の目的と主要な構成要素>

## 計画 / ADR

- 計画 issue: <plan_issue の URL>
  - 全項目をこの PR で消化する場合: `Closes #<番号>` をここに書く
  - 部分消化の場合: `Closes` を使わず「issue #<番号> の <M> 項目目を消化」のように明示する
- ADR: `docs/adr/...` (N 件、なければ「なし」と明記)

## 検証結果 (Phase 3 自動検証)

| チェック | コマンド | 結果 | 種別 |
|---------|---------|------|------|
| 型チェック | `tsc --noEmit` | PASS | 自動 |
| Lint     | `eslint .`   | PASS | 自動 |
| ローカル Codex レビュー | `local-codex-review.sh` | P1/P2 0 件 (2 パス目) | 自動 |
| ...     | ...         | ...  | ...  |

## レビュアー向けの前提

- 意図: <この変更が何を保証し、何を保証しないか>
- 不変条件: <変更後も保たれるべき性質。並行実行、失敗時、再試行時の扱い>
- 意図的に対応しないこと: <既知の指摘候補と、その判断の根拠>
- 環境制約: <ローカルで検証できなかった経路と理由>
- ローカルレビュー: <パス数と、出た P1/P2 の処理。2 パス目で直して未レビューの head ならその旨>

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
# 投稿前に内容を検証 (想定する書き出しが含まれるか目視確認)
head -c 300 "$PR_BODY"

cd "$WT_PATH" && gh pr create \
  --base "$DEFAULT_BRANCH" \
  --head "$BRANCH" \
  --title "<コミットメッセージから派生したタイトル>" \
  --body-file "$PR_BODY"

rm -f "$PR_BODY"
```

`gh pr create` 実行後、`gh pr view --json url -q .url` で URL を取得しセッションファイルに記録する (手順 7)。

---

## Phase 5-bis: Post-PR Iteration

**目的**: PR 作成後・マージ前の追加修正で、コード修正だけでなく **PR 本文・検証結果・ADR リンクも同期更新**してドキュメント整合性を保つ。

> **Phase 5-bis と Phase 5.5 の違い**: 5-bis は **人手主導**の追加修正 (`/dev resume`)。CI と Codex 自動レビューへの **能動監視・フル自動対応** は Phase 5.5 (Phase 5 から自動突入、再開は `/dev review`。[phase-5.5-review-loop.md](phase-5.5-review-loop.md))。両者は本節の PR 本文同期ルール (Test plan 保持・変更履歴) と `followups[]` を共有する。5-bis で push した後は Phase 5.5 のループに戻り、終端条件 (CI 全成功 + レビュー収束) を確かめ直す。

### 起動方法

- `/dev resume` でセッション一覧から `status == "pr-open"` を選択、または `/dev resume <slug>` で直接指定 → 自動で post-PR モード
- cwd が `status == "pr-open"` の worktree 配下 → セッション逆引きで post-PR モード
- **通常の `/dev <説明>` では post-PR モードに入らない** (別タスク扱い)

### 前提条件

- セッションが存在し `status == "pr-open"`
- `gh pr view "$PR_URL" --json state -q .state` が `OPEN` (`MERGED` なら cleanup へ、`CLOSED` なら AskUserQuestion で再 open or 中止)
- worktree が存在し、リモート追跡ブランチが設定済み

### フロー

#### 1. セッション復元

- `WT_PATH` / `BRANCH` / `PR_URL` / `plan_issue` をセッションファイルから読み込む
- Phase 0 の整合性チェック (worktree 存在、前提セットアップ設定) を再実行
- 現在の PR 本文を `gh pr view "$PR_URL" --json body -q .body` で取得してキャッシュ

#### 2. 追加修正を Phase 2 同等で実装

- 変更内容はナレーションと計画 issue の「変更履歴」節で追跡する (タスク管理ツールが利用可能な環境ではそれも使ってよい)
- 設計判断が絡むなら ADR を追記 (新規 ADR 番号を採番)
- 計画 issue 本文の「変更履歴」節を追記 (なければ作る)。更新は `gh issue edit <番号> --body-file` で行い、ADR 追記分の「ADR」節更新もまとめて 1 回で反映する

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

- YYYY-MM-DD: 初回実装 (計画 issue: ${plan_issue})
- YYYY-MM-DD: <追加修正の要約>  ← 今回追加
<...以降の追加修正も順に追記>

## 計画 / ADR

- 計画 issue: <plan_issue の URL> (Closes / 部分消化の書き分けは Phase 5 と同じ)
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

**Test plan は破棄しない (重要)**: 本文を `gh pr edit --body-file` で全文置換するため、Test plan 節を省くと初回 PR で構築済みのチェックリスト (`[x]` / `[ ]`) が消え、レビュアーが検証状況を追えなくなる。手順 1 で取得済みの現在の PR 本文 (`gh pr view "$PR_URL" --json body -q .body`) から既存の Test plan 節を回収して土台にし、次のように更新する:

- Phase 5 で `[x]` 済みの項目はそのまま維持 (再実行不要)
- 今回の追加修正で新たに検証が必要になった項目を追加し、Test plan 構築ルール ([Phase 5 の「Test plan 構築ルール」](#test-plan-構築ルール)) に従って実行・分類する
- 追加修正で既存の `[x]` 項目に回帰リスクがあれば、Phase 3 再実行 (手順 3) の結果で状態を更新する
- 捏造禁止は Phase 5 と同じく適用 (実行していない項目を `[x]` にしない)

更新コマンド:

```bash
NEW_BODY=$(mktemp)
cat > "$NEW_BODY" <<'EOF'
<上記テンプレートを slug / followups / 検証結果で埋めたもの>
EOF
head -c 300 "$NEW_BODY"   # 投稿前に想定する書き出しが含まれるか目視確認
gh pr edit "$PR_URL" --body-file "$NEW_BODY"
rm -f "$NEW_BODY"
```

heredoc は **クォート付き `<<'EOF'`** を使う (Phase 5 の `gh pr create` 例と同じ)。PR 本文には `` `tsc --noEmit` `` のようなバッククォートや `$` が含まれるため、クォートなし `<<EOF` だとシェルがコマンド置換・変数展開して本文が壊れる。テンプレートのプレースホルダは Claude が事前に解決して埋めるので、シェル変数展開に頼らない。

#### 7. title の更新 (必要時のみ)

- スコープが実質的に変わった場合のみ `gh pr edit "$PR_URL" --title "..."` を実行する (軽微な追加修正では title を変えない)

#### 8. セッションファイル更新

- `updated_at`: ISO 8601 now
- 必要なら `followups[]` 追記 (Phase 4-B で発生した分)
- `post_pr_iterations`: カウンタ (何度 Phase 5-bis を回したか、任意)

#### 9. ユーザー報告

- 追加コミットの SHA、更新した PR 本文の要点、残 followup 数を提示し、「さらに追加修正する場合は `/dev resume <slug>`」を再掲

### 禁止事項

- PR 本文を更新せずにコミット + push だけで終えない (レビュアーから変更履歴が追えなくなる)
- `gh pr edit --body` で本文を空にしない (`--body-file` を使う、`--body ""` は事故のもと)
- マージ済み (`state == MERGED`) の PR を post-PR モードで再開しない (cleanup へ誘導)

---

## Phase 6: Cleanup (後片付け)

**目的**: PR がマージされた後、worktree とブランチをローカルから削除し、セッションファイルを `cleaned` にする。

**起動方法**: 通常の `/dev` フロー (Phase 0→5.5) からは自動実行しない。PR マージ確認は分〜日単位の非同期タスクなので、ユーザーが明示的に `/dev cleanup` で起動するか、pr-relay の帯の `cleanup` ボタンを押して起動する。

### 呼び出し形態

- pr-relay の `cleanup` ボタン — 「PR <URL> がマージされました。/dev cleanup の手順で worktree とブランチを片付けてください。」というプロンプトが届く
  - ボタンを押したのはユーザーなので、`/dev cleanup` の明示起動と同じに扱う。手順 2 の state 確認は省かない
  - セッションは、プロンプトの URL と `pr_url` が一致する `~/.claude/dev-sessions/*.json` で特定する (URL は大文字小文字を無視して比べる)。見つからなければ下の引数なしと同じ探し方に落とす
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
**関連計画**: ${plan_issue}

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

# gh issue create は作成した issue の URL を標準出力に返す (--json フラグは存在しない)
ISSUE_URL=$(gh issue create \
  --title "$title" \
  --body-file "$ISSUE_BODY" \
  ${labels:+--label "$labels"})

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

#### 7.5. プロジェクト固有の cleanup 後処理 (あれば実行、ベストエフォート)

**目的**: マージ済みのコードを手元の実行環境へ反映する、ローカルの生成物を掃除するなど、プロジェクトごとに cleanup の締めとして走らせたい処理を実行する。

プロジェクトの `CLAUDE.md` に「`/dev cleanup` 後の後処理」に相当する節があれば、その手順に従って実行する。無ければ本手順はスキップする (無いこと自体は報告しなくてよい)。

実行ルール:

- **ベストエフォート**。失敗しても cleanup は完了扱いにし、手順 8 のレポートに結果 (成功 / skip の理由 / 失敗の理由) を 1 行残す。ロールバックはしない
- **作業ディレクトリは `$REPO_ROOT`**。worktree は手順 5 で削除済みで、対象はマージ後の default ブランチであってタスクブランチではない
- **`$REPO_ROOT` の作業ツリーを勝手に動かさない**。最新化は「default ブランチ上」かつ「`git status --porcelain` が空」かつ「fast-forward できる」の 3 条件が揃ったときだけ行い、コマンドは `git pull --ff-only` を使う。pull の後に `git rev-parse HEAD` と `git rev-parse "origin/$DEFAULT_BRANCH"` が一致することも確かめる (default ブランチに未 push のコミットがあると、`git pull --ff-only` は「Already up to date」で成功してしまう)。1 つでも欠けたら最新化を skip して警告し、**後処理そのものも skip する** (後処理はマージ後のコードを前提にするので、別ブランチや古いチェックアウトで走らせると違う版を反映しうる)。ユーザーが default ブランチ側で別の作業をしている可能性があるので、作業ツリーは動かさない。porcelain が空でも未 push のコミットがあれば、素の `git pull` は設定次第でマージコミットや rebase を作る
- **外部デバイス・外部環境への依存は実行時に検出する**。接続されていなければ skip として報告し、エラー扱いにしない
- 数分かかる処理になりうるため、開始時に何をしているかナレーションで宣言する

セッションファイルの `status: "cleaned"` (手順 7) は、本手順の成否に関わらず維持する。

#### 8. 最終確認レポート

- 削除した worktree パス
- 削除したローカルブランチ
- リモートブランチの扱い (削除 / 保持)
- **作成した GitHub issue 一覧** (手順 2.5 の結果、新規 / 既存にマップされた件数)
- **プロジェクト固有の cleanup 後処理の結果** (手順 7.5。実行したか / skip したか、その理由)
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
