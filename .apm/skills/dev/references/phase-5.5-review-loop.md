# Phase 5.5: CI + Review Loop

Phase 5 (Open PR 作成) と Phase 6 (Cleanup) の間に挟まる、**CI と Codex 自動レビューの能動監視 + フル自動対応ループ**。Phase 5 完了直後に自動突入する。PR open をトリガーに CI と Codex bot のレビューが走るので、本フェーズは (1) CI checks の完了を監視して FAIL があれば修正 push、(2) Codex の 👀 → コメント → 👍 を監視して指摘が付いたら triage → 修正/反論/followup → push → 返信 → 再レビュー待ち、を **CI 全成功 + approved (👍) の両方が揃うまで自走**させる。

SKILL.md 本体から「Phase 5 完了後に自動突入するとき」「`/dev review` で再開するとき」「CI / Codex レビュー対応ループの state machine / 監視ロジックが必要なとき」に参照する。

## Contents
- [前提: Codex の挙動 (実 PR 観測で確定)](#前提-codex-の挙動-実-pr-観測で確定)
- [起動方法と前提条件](#起動方法と前提条件)
- [State machine](#state-machine)
- [CI 監視 (gh pr checks)](#ci-監視-gh-pr-checks)
- [監視メカニズム (poll-codex-review.sh)](#監視メカニズム-poll-codex-reviewsh)
- [1 ラウンドの対応フロー](#1-ラウンドの対応フロー)
- [triage 分類ルール](#triage-分類ルール)
- [返信フロー](#返信フロー)
- [終端とエスカレーション](#終端とエスカレーション)
- [セッション保存](#セッション保存)
- [禁止事項](#禁止事項)
- [検証メモ](#検証メモ)

---

## 前提: Codex の挙動 (実 PR 観測で確定)

以下は **推測ではなく** HolyGrail/GBF-community #925 / #812 を `gh api` で観測して確定した事実。state machine はこれに基づく。Codex のレビュー本文 (`### 💡 Codex Review`) の "About Codex in GitHub" にも公式記述がある。

| 項目 | 確定事実 |
|---|---|
| **bot アクター** | `chatgpt-codex-connector[bot]` (`--bot` で上書き可能にしてある) |
| **トリガー** (公式) | PR を review 用に open / **draft を ready にする** / `@codex review` とコメント |
| **再レビュー** | **push (新コミット) で実際に再トリガーされる** (両 PR でコミットごとに review を観測)。ただし保証はされないので、自動を待ってから明示 `@codex review` でフォールバックする |
| **指摘あり** | `pulls/{n}/reviews` に review (`state: COMMENTED`) + `pulls/{n}/comments` に inline comments。コメントは `pull_request_review_id` で review に紐付く |
| **指摘なし (approve)** | PR 本体(issue) に `+1`(👍) reaction。**`APPROVED` state の review は使わない** |
| **コメント形式** | inline comment の本文冒頭に重要度バッジ `![P2 Badge]`。`in_reply_to_id` で返信スレッド、`commit_id`/`line` でレビュー対象 |
| **👀 (eyes)** | レビュー進行中の一時マーカー。完了後は消える → **終端判定には使わない** (補助情報) |
| **コミットの扱い** | Codex は **最新コミットをレビューし中間コミットをスキップ**。最終コミットは review なしで **+1 のみ** のことが多い |
| **再レビュー latency** | 可変 (#925: ~2 分 / #812: 一部 ~29 分)。タイムアウトは余裕を持たせる (既定 40 分) |

**設計上の最重要点 (false-approve 防止)**: GitHub は (user, content) で reaction を dedupe するため、Codex の +1 は **1 つしか存在せず created_at が固定されうる**。「+1 が存在する」で approved 判定すると、過去ラウンドの +1 を見て早期終了する事故が起きる。→ **必ず「自分の最後の push より新しい」イベントだけをシグナルとして扱う** (baseline-diff)。

---

## 起動方法と前提条件

### 起動

- **Phase 5 完了直後の自動突入 (通常経路)**: `gh pr create` が成功しセッションが `status == "pr-open"` になったら、そのままこのループに入る。ユーザーの明示起動を待たない
- **`/dev review [slug]` (再開経路)**: セッションが中断した場合の再入口
  - 引数なし: `status == "pr-open"` のセッションを AskUserQuestion で選択 (cwd が worktree 配下ならそれを優先)
  - slug 指定: 直接そのセッション

### 前提条件 (満たさなければ中断)

1. セッションが存在し `status == "pr-open"`
2. `gh pr view "$PR_URL" --json state -q .state` が `OPEN` (`MERGED` なら Phase 6 へ誘導、`CLOSED` なら AskUserQuestion)
3. **PR が Draft でない** (`gh pr view "$PR_URL" --json isDraft -q .isDraft` が `false`)
   - `true` (Draft) の場合: 旧セッションの再開時のみ発生しうる。`gh pr ready "$PR_URL"` を実行して Open 化し、ナレーションで報告して続行する (Phase 5 以降 Open が既定であり、自分が作成した PR なので確認不要)
4. worktree が存在し、リモート追跡ブランチが設定済み (Phase 0 整合性チェック)
5. `gh auth status` 認証済み、`jq` 利用可能

### セッション復元

`WT_PATH` / `BRANCH` / `PR_URL` / `plan_issue` (旧セッションは `plan_file`) / `followups` / `review` をセッションから読み込む。`review` が無ければ初期化する ([セッション保存](#セッション保存) のスキーマ)。

---

## State machine

**終端条件は「最新 push に対して CI 全成功」かつ「last_push_at 以降の codex +1」の AND**。push するたびに両方が仕切り直しになる (CI は HEAD コミットに対して走り直し、Codex は再レビューする)。

```
[起動] Phase 5 完了直後に自動突入 (再開は /dev review <slug>)
  ├─ 前提条件チェック (Draft なら gh pr ready で Open 化して続行)
  └─ baseline 記録: review.last_push_at = 現在の HEAD コミットの push 時刻
        ※ 取得: gh api repos/{repo}/commits/{sha} --jq .commit.committer.date
          (or PR 作成時刻 / 監視開始時刻のうち最も確実なもの。「これ以降の Codex
           イベントだけを新規とみなす」基準なので、取りこぼすより早めでよい)

         ┌──────────────────────────────────────────────────────┐
         ▼                                                      │
[CI_WAIT] gh pr checks "$PR_URL" --watch (run_in_background)     │
  ├─ 全 bucket が pass/skipping → [MONITORING] (CI 緑)            │
  ├─ fail / cancel あり → [CI_FIXING]                            │
  └─ checks が 1 つも無い ("no checks reported") → CI 条件充足扱いで [MONITORING]
                                                                │
[CI_FIXING] 1 ラウンド = 1 push に直列化 (RESPONDING と共通の規律)   │
  1. 失敗 check の run ログ取得 (gh run view <run-id> --log-failed) │
  2. 根本原因を診断 (ローカルの Phase 3 検証で再現を試みる)            │
     ※ flaky 疑い (変更と無関係・非決定的) は gh run rerun --failed を
       1 回だけ試す。それでも落ちたら実問題として修正                  │
  3. 修正 → ローカル検証 PASS → 1 コミット → push                   │
  4. baseline 前進、ci_fix_rounds++、PR 本文の検証結果を同期更新      │
  └─ → [CI_WAIT] へ戻る (push で CI と Codex 再レビューが両方走る) ──┘

[MONITORING] poll-codex-review.sh --watch (run_in_background)
  ├─ signal=approved (last_push_at 以降に codex +1)
  │     └─ CI が最新 push に対して緑であることを再確認 → [APPROVED] 終了
  ├─ signal=new_review (last_push_at 以降に codex review) → [RESPONDING]
  └─ signal=waiting (内部タイムアウトで exit)
        ├─ total_wait_seconds += 経過。escalate_after_seconds 超過:
        │     ├─ Codex イベントがこの PR で一度も観測されていない
        │     │   → Codex 未設定の可能性。CI 緑なら [DONE (CI-only)] として
        │     │     終了報告 (レビューは人間に引き渡す旨を明記)
        │     └─ 過去に Codex イベントあり → [ESCALATED]
        ├─ eyes_present==true → レビュー進行中。@codex review は投げず待機継続
        ├─ eyes_present==false かつ直近 push 後で再レビュー未着 → @codex review (フォールバック)
        └─ それ以外 → 再度 --watch を起動 (MONITORING 継続)

[RESPONDING] 1 ラウンド = 1 push に直列化
  1. remote-ahead reconcile (git fetch + ahead/behind)
  2. 最新 review に紐づく未処理 inline comments を回収
  3. 全件 triage (fix / rebut / followup)
  4. fix を実装 → Phase 3 検証 (回帰防止) → 1 コミット
  5. push (1 ラウンド 1 push)
  6. 各コメントに返信
  7. PR 本文を同期更新 (Phase 5-bis ルール)
  8. baseline 前進 (push 時=push 時刻 / 非 push 時=処理 review の submitted_at)、
     rounds++、保存 ※ 非 push でも前進させないと同じ review 再返却で無限スピン
  └─ rounds >= max_rounds → [ESCALATED]
     push した場合 → [CI_WAIT] (CI を先に確認してから Codex 監視に戻る)
     push しなかった場合 → [MONITORING]

[APPROVED]       CI 全成功 + approved。ユーザー報告 + 「マージ後 /dev cleanup」案内、
                 loop_status=approved
[DONE (CI-only)] Codex 未設定リポジトリの終端。CI 全成功を報告し、
                 人間レビュー待ちとして引き渡す (loop_status=approved 扱いにはしない。
                 loop_status=timeout + 報告で区別)
[ESCALATED]      未解決事項をまとめて AskUserQuestion でユーザーに判断を仰ぐ
```

---

## CI 監視 (gh pr checks)

CI の監視・判定は `gh pr checks` に集約する。checks は **HEAD コミットに対して**返るため、push すれば自動的に最新コミットの判定になる (Codex の baseline-diff のような自前の時刻管理は不要)。

### 待機と判定

```bash
# 待機: checks が全て完了するまでブロックする。run_in_background 必須 (前景 sleep 禁止と同じ理由)
cd "$WT_PATH" && gh pr checks "$PR_URL" --watch

# 判定: watch の exit 後に 1 ショットで結果を確定する
cd "$WT_PATH" && gh pr checks "$PR_URL" --json name,bucket,link
```

- **bucket の解釈**: `pass` / `skipping` → OK。`fail` / `cancel` → CI_FIXING へ。`pending` → まだ完了していない (watch を再起動)
- **checks が 1 つも無い場合**: `gh pr checks` は「no checks reported」エラー (非ゼロ exit) を返す。CI 未設定リポジトリなので **CI 条件は満たしたとみなして** MONITORING へ進む (エラーで停止しない)
- **`--watch` が使えない環境**: 1 ショット呼び出し + ScheduleWakeup で間欠確認にフォールバック (poll-codex-review.sh と同じ方式)

### CI FAIL の修正フロー (CI_FIXING)

1. 失敗した check の詳細を取得する: `gh pr checks --json` の `link` から run ID を特定し、`gh run view <run-id> --log-failed` でログを読む
2. **根本原因を診断してから修正する**。ローカルの Phase 3 検証で再現を試み、再現すればローカルで修正 → PASS を確認してから push する。ローカルで再現しない失敗 (環境差・依存キャッシュ・secrets) はログから原因を特定する
3. **flaky の扱い**: 失敗が今回の変更と無関係で非決定的に見える場合のみ、`gh run rerun <run-id> --failed` を **1 回だけ**試す。再実行でも落ちたら実問題として扱い、修正する。rerun を繰り返して緑を引き当てるのは禁止
4. 修正 push は「1 ラウンド 1 push」規律の対象。**CI 修正とレビュー指摘対応が同時に溜まっている場合は 1 つのコミット群にまとめて 1 push にする** (別々に push すると Codex の追跡が壊れる)
5. push 後は baseline (`review.last_push_at`) を前進させ、`ci_fix_rounds` をインクリメントして CI_WAIT に戻る
6. CI 失敗の原因が **main 由来 (既存問題)** と切り分けられた場合も、CI を落とす以上 Phase 4-B マトリクスの第 1 行に該当するので今回 PR で修正する
7. 自分では解決できない失敗 (リポジトリ設定・secrets 不足・外部サービス障害・billing 等) に行き着いたら、診断結果を添えて [ESCALATED] へ

## 監視メカニズム (poll-codex-review.sh)

Codex 監視は同梱スクリプト [`scripts/poll-codex-review.sh`](scripts/poll-codex-review.sh) に集約する (baseline-diff / commit gating ロジックをインラインで毎回組むと事故るため)。

### なぜポーリングを分割するか

`gh api` の応答待ちと Bash の **600s 上限** に対し、再レビュー latency は最大 ~30 分。1 本の `while + sleep` では span できない。そこで **「短い --watch を background で回し、変化検知 or 内部タイムアウトで exit → Claude が起きて判断 → 必要なら再起動」** という短チェック反復にする。Claude はアイドル中コンテキストを消費しない。

### 使い方

```bash
SCRIPT="$REPO_ROOT/.claude/skills/dev/references/scripts/poll-codex-review.sh"
# (グローバルスキルの場合は ~/.claude/skills/dev/references/scripts/poll-codex-review.sh)

# --watch: background で起動する (前景 sleep が禁止の環境のため run_in_background 必須)
"$SCRIPT" "$OWNER/$REPO" "$PR_NUMBER" "$LAST_PUSH_AT" --watch --max-wait 540
```

- **必ず `run_in_background: true` の Bash で起動する**。スクリプトの `while` ループごと background プロセスになり、exit 時に Claude が起こされる。
- 第 3 引数 `$LAST_PUSH_AT` は `review.last_push_at` (ISO8601 UTC)。**これより厳密に新しい Codex イベントだけがシグナル**になる。
- 出力 (1 行 JSON):
  ```json
  {"signal":"approved|new_review|waiting","approved_at":"<ISO|null>",
   "latest_review":{"id":...,"commit_id":...,"submitted_at":...,"body":...}|null,
   "new_comments":[{"id":...,"pull_request_review_id":...,"in_reply_to_id":...,
                    "path":...,"line":...,"outdated":bool,"commit_id":...,
                    "html_url":...,"created_at":...,"body":...}],
   "eyes_present":bool,"checked_at":"<ISO>"}
  ```
- signal 優先順位: **approved > new_review > waiting**。

### ScheduleWakeup フォールバック

background `--watch` の sleep が環境で動かない / 長時間にわたり再起動を繰り返す場合は、**1 ショットモード** (`--watch` なし) を ScheduleWakeup で間欠実行してもよい。間隔は **240–270s 推奨** (Anthropic prompt cache の 5 分 TTL 内に収めてコンテキストを温存)。

```bash
"$SCRIPT" "$OWNER/$REPO" "$PR_NUMBER" "$LAST_PUSH_AT"   # 1 ショット (即 exit)
```

---

## 1 ラウンドの対応フロー

`signal=new_review` を受けたら以下を **1 push に直列化**して実行する (複数 push すると Codex が中間コミットをスキップして混乱するため)。

### 1. remote-ahead reconcile (必須・先頭)

ユーザーが手動で push している可能性があるため、修正前に必ず origin と同期する。

```bash
cd "$WT_PATH" && git fetch origin "$BRANCH"
LOCAL=$(git rev-parse @); REMOTE=$(git rev-parse "@{u}"); BASE=$(git merge-base @ "@{u}")
```

- `LOCAL == REMOTE` → 同期済み、続行
- `LOCAL == BASE` (remote が進んでいる) → `git pull --rebase` してから続行。コンフリクトしたら停止してユーザーに報告
- それ以外 (ローカルが進んでいる/分岐) → 状況を報告。分岐なら停止

### 2. コメント回収

`signal=new_review` の出力 `new_comments[]` を使う。対応対象は次でフィルタ:

- `in_reply_to_id == null` (トップレベル指摘。返信スレッドの子は対象外)
- `id` が `review.processed_comment_ids` に **無い** (未対応)
- `id` が `review.rebutted_comment_ids` に **無い** (反論済みの再提起は新規扱いしない → [#4 ループ防止](#終端とエスカレーション))
- `outdated == false` (`line == null` の outdated コメントは「対象行が消滅/移動」= 既に解消された可能性が高い。**自動修正の対象にしない**。本当に解消済みか軽く確認し、未解消なら fix 候補に拾い直す。processed に入れて以後スキップ)

### 3. triage

回収した各コメントを [triage 分類ルール](#triage-分類ルール) に従い `fix` / `rebut` / `followup` に分類する。

### 4. fix を実装 → 検証

- `fix` 分のコード修正を worktree 内で実装
- **Phase 3 (Verify) を再実行** (変更箇所に限定しない — 回帰検出のため。コマンド自動検出は [phases-1-4.md Phase 3](phases-1-4.md#phase-3-verify-検証))
- 新規 FAIL は修正、既存 FAIL は followups[] へ ([phases-1-4.md Phase 4-B](phases-1-4.md#4-b-既存問題-main-にも存在))

### 5. push (1 ラウンド 1 push)

```bash
cd "$WT_PATH" && git add -A && git commit -m "fix: Codex レビュー指摘に対応 (round N)" && git push
NEW_SHA=$(git -C "$WT_PATH" rev-parse HEAD)
NEW_PUSH_AT=$(git -C "$WT_PATH" show -s --format=%cI HEAD)  # ISO8601
```

`fix` が 0 件 (全て rebut/followup) の場合は push しない (返信のみ)。**この場合でも手順 8 で baseline (`review.last_push_at`) を「処理した最新 review の `submitted_at`」に前進させる**。前進させないと push が無いため baseline が動かず、同じ review が次の MONITORING で再び `new_review` として返り、コメントは全て処理済みでフィルタされ 0 件 → 即 MONITORING → 同じ review …… という **タイトな無限スピン** になる (`rebutted_comment_ids` は再 triage を防ぐが、monitor の再スピンは防げない)。baseline を前進させれば rebut-only ラウンドは正しく `waiting` → latency timeout → [ESCALATED] (「全件反論済み・Codex 未応答」) に落ちる。

### 6. 返信

各コメントに [返信フロー](#返信フロー) で返信する。

### 7. PR 本文の同期更新

Phase 5-bis の「[PR 本文の再生成と更新](phases-5-6.md#phase-5-bis-post-pr-iteration)」ルールをそのまま適用する。**Test plan 節を破棄しない** / 変更履歴に「YYYY-MM-DD: Codex レビュー round N 対応」を追記 / `gh pr edit "$PR_URL" --body-file` で更新。

### 8. セッション保存 + 再レビュー誘導

- `review.processed_comment_ids` に対応した id を追加、`rebutted_comment_ids` に反論した id を追加
- `review.processed_review_ids` に処理した review id を追加 (複数 review を処理したら全件)
- **baseline (`review.last_push_at`) を必ず前進させる** (BLOCKER 回避):
  - push した場合: `review.last_push_at = NEW_PUSH_AT`、`review.last_push_commit = NEW_SHA`
  - **push しなかった場合 (rebut/followup のみ)**: `review.last_push_at = 処理した最新 review の submitted_at` (同じ review の再スピンを防ぐ。前進させないと手順 5 の無限スピンに陥る)
- `review.rounds += 1`、`updated_at` 更新
- → **push した場合は CI_WAIT に戻る** (新コミットの CI を先に確認してから Codex 監視へ)。push しなかった場合は MONITORING に戻る。**再レビュー誘導は push の有無と `eyes_present` で判断**:
  - **push した場合**: 自動再レビューを待つ。`waiting` で exit したとき `eyes_present == false` (レビュー進行中でない) なら `@codex review` をコメントしてフォールバックトリガー。`eyes_present == true` なら進行中なので投げずに待機継続 (二重トリガー防止。#812 実測で latency ~29 分のケースあり、早すぎる再投稿は二重レビューを招く)
  - **push しなかった場合**: 再レビューは起こらないので `@codex review` は投げない。baseline 前進により `waiting` → latency timeout → [ESCALATED] に委ねる

---

## triage 分類ルール

各 inline comment を `/pr-feedback` の分類体系 (🔴 must / 🟡 imo / 🟢 nits / 🔵 q) と Codex の重要度バッジ (本文冒頭 `![P1/P2/P3 Badge]`) で評価し、対応を決める。**全件 triage する — 黙って全部修正しない / 黙って全部無視しない**。

| 分類 | 条件 | アクション |
|---|---|---|
| **fix** | 指摘が正しく、コード/ドキュメントを直すべき | 修正を実装。返信で対応内容 + commit sha を報告 |
| **rebut** | 指摘が誤り・前提が違う・既に対応済み・意図的な設計 | **根拠付きで** in_reply_to 返信 (一次情報・コード参照を添える)。`rebutted_comment_ids` に記録。コード変更なし |
| **followup** | 指摘は妥当だが本 PR のスコープ外 / 範囲が大きい | `followups[]` に `decision: "separate-pr"` or `"out-of-scope"` で追記 (Phase 6 で issue 化)。返信で「別 issue として対応予定」を明示 |

判定指針:
- **重要度バッジ + must/imo/nits/q** で優先度を付ける。must / P1 相当は原則 fix。nits / P3 相当でも安価なら fix、コストが見合わなければ followup
- **誤指摘を黙って直さない**: Codex の指摘が常に正しいとは限らない。一次情報 (公式ドキュメント・実コード) で確認し、誤りなら rebut する (実例: #925 は逆に Codex の指摘が正しく、ユーザーが overclaim を訂正した。どちらに転んでも **根拠で判断**する)
- 判断に迷う指摘 (設計トレードオフが絡む等) も、**一次情報を集めて自律決定するのが原則** (Phase 1 の選定基準を適用し、判断根拠を返信に書く)。根拠を集めても fix / rebut のどちらとも確定できない場合のみ、そのコメントを保留にして他を先に処理し、保留分は [ESCALATED] 時にまとめてユーザーに提示する (1 件ごとに停止しない)

---

## 返信フロー

inline comment への返信は GitHub の reply エンドポイントを使う。**本文は CLAUDE.md / SKILL.md の `--body-file` + `mktemp` + `head` 検証ルールの対象** (shell 展開事故・他セッションのファイル混入を防ぐ)。

```bash
REPLY=$(mktemp -t codex-reply.XXXXXX)
cat > "$REPLY" <<'EOF'
ご指摘ありがとうございます。<対応内容 or 反論の根拠>。
<fix なら: コミット abc1234 で対応しました。>
EOF

# 投稿前検証 (Write tool 拒否や中身ズレを検知)
head -c 200 "$REPLY"   # 想定する書き出しが含まれるか目視

# reply 投稿: 特殊文字を壊さないため jq で JSON 化し --input - で渡す
jq -n --rawfile b "$REPLY" '{body:$b}' \
  | gh api -X POST "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" --input -

rm -f "$REPLY"
```

- `$COMMENT_ID` は返信先トップレベルコメントの `id`
- 短い定型文 (`@codex review` 等の PR 全体コメント) は `gh pr comment "$PR_URL" --body "@codex review"` でよい (PR 本体コメント。長文なら `--body-file`)
- 代替: MCP `mcp__plugin_github__add_reply_to_pull_request_comment` でも返信可能 (gh が使えない環境)

返信内容の原則 (`/pr-feedback` の返信テンプレート準拠):
- **fix**: 「ご指摘ありがとうございます。<具体的修正内容>。コミット `<sha>` で対応しました。」
- **rebut**: 「<根拠: 一次情報/コード参照>。このため本指摘は<該当しない/既に対応済み>と判断しました。」(丁寧かつ技術的根拠ベース)
- **followup**: 「妥当なご指摘です。本 PR のスコープ外のため、別 issue として対応します (cleanup 時に自動起票)。」

---

## 終端とエスカレーション

### APPROVED (正常終了)

`signal=approved` (last_push_at 以降に codex +1) を検知したら、**最新 push に対する CI が全成功であることを再確認**した上で終了する (`gh pr checks --json` で bucket が全て `pass`/`skipping`。pending が残っていれば CI_WAIT に戻って完了を待つ。approved だけで終了しない):

1. `review.loop_status = "approved"`、`review.approved_at = <+1 の時刻>` を保存
2. ユーザーに報告: 回した round 数 (レビュー対応 + CI 修正)、各ラウンドの対応サマリ (fix/rebut/followup の内訳、CI 修正内容)、CI 最終結果、最終コミット sha
3. 「PR がマージされたら `/dev cleanup` で worktree を掃除し、followup を issue 化できます」と案内

### DONE (CI-only) — Codex 未設定リポジトリの終端

latency timeout に達し、かつ **この PR で Codex イベント (review / comment / +1 / 👀) が一度も観測されていない**場合は、Codex 未設定リポジトリと判断する。CI が全成功なら次で終了する:

1. `review.loop_status = "timeout"` を保存 (approved と区別する)
2. ユーザーに報告: CI 全成功の結果と、「Codex のレビューは観測されませんでした (未設定の可能性)。レビューは人間のレビュアーに委ねます」を明記
3. マージ後の `/dev cleanup` を案内

### ESCALATED (ユーザー判断が必要)

以下のいずれかで CI_WAIT/MONITORING/RESPONDING を抜け、AskUserQuestion でユーザーに判断を仰ぐ:

| 条件 | エスカレーション |
|---|---|
| **latency timeout** (`total_wait_seconds > escalate_after_seconds`、既定 40 分) かつ過去に Codex イベントあり | 「Codex の再レビューが来ません。①`@codex review` を再投稿 / ②中止 / ③現状でマージ判断」(イベントが一度も無い場合は DONE (CI-only) へ) |
| **max_rounds 超過** (既定 5) | 「N ラウンド対応しましたが approved に達しません。未解決コメント一覧を提示。①続行 / ②手動対応に切替 / ③現状でマージ判断」 |
| **#4 反論再提起ループ** | 同一指摘 (`rebutted_comment_ids`) を Codex が N 回再提起 → 「Codex と見解が平行線です。指摘内容を提示するので判断してください」 |
| **CI 失敗が自力で解決不能** (リポジトリ設定・secrets・外部サービス・billing 等) | 診断結果と失敗ログの要点を提示して判断を仰ぐ |
| **検証 (ローカル) の根本原因を特定しても解決不能** | Phase 4-A の手順に従いユーザーに判断を仰ぐ |
| **remote コンフリクト / 分岐** | 自動 rebase 不能。状況を報告して停止 |

`loop_status = "escalated"` / `"timeout"` を保存し、`/dev review <slug>` で再開可能にする。

---

## セッション保存

`~/.claude/dev-sessions/<slug>.json` に `review` オブジェクトを持たせる (スキーマ詳細は [session-management.md](session-management.md))。

```json
"review": {
  "loop_status": "monitoring",          // monitoring|ci-fixing|responding|approved|timeout|escalated|null
  "rounds": 0,
  "max_rounds": 5,
  "ci_fix_rounds": 0,
  "last_push_at": "2026-05-30T01:00:00Z",
  "last_push_commit": "abc1234...",
  "processed_review_ids": [],
  "processed_comment_ids": [],
  "rebutted_comment_ids": [],
  "total_wait_seconds": 0,
  "escalate_after_seconds": 2400,
  "started_at": "2026-05-30T01:00:00Z",
  "approved_at": null
}
```

中断 (セッション切れ等) しても、`processed_*_ids` と `last_push_at` から **冪等に再開**できる (再 `/dev review <slug>` で続行)。

---

## 禁止事項

- **approved (👍) だけで終了しない**。終端条件は「最新 push に対する CI 全成功」との AND。逆に CI 緑だけでも終了しない (Codex 設定済みリポジトリでは approved を待つ)
- **CI 失敗を `gh run rerun` の連打で握りつぶさない**。rerun は flaky 切り分けとして 1 回のみ。2 回連続で落ちたら実問題として修正する
- **CI 修正とレビュー対応を別々に push しない**。同時に溜まっているなら 1 push にまとめる (1 ラウンド 1 push 規律)
- **「+1 が存在する」で approved 判定しない** (baseline-diff 必須)。必ず `last_push_at` より新しい +1 だけをシグナルにする
- **commit_id の完全一致を待たない** (Codex は中間コミットをスキップ、最終コミットは +1 のみ)。`last_push_at 以降の codex イベント`で判定する
- **1 ラウンドで複数 push しない** (中間コミットがスキップされ追跡が壊れる)
- **Codex の指摘を黙って全部修正しない / 黙って全部無視しない** (全件 triage)
- **outdated コメント (`line==null`) を機械的に fix しない** (対象行が消えている)
- **返信本文を `--body-file`/`--input` 以外で渡さない** (shell 展開事故)。`mktemp` 動的パス + `head` 検証必須
- **PR 本文を更新せずに push だけで終えない** (Phase 5-bis ルール、Test plan を落とさない)
- **`--watch` を前景 Bash で起動しない** (sleep がブロックされる。`run_in_background` 必須)
- **MERGED / CLOSED の PR で監視を始めない** (Phase 6 へ誘導)
- **rebut/followup のみのラウンドで baseline を据え置かない**。push が無くても `review.last_push_at` を処理した最新 review の `submitted_at` に前進させる (据え置くと同じ review が再返却され monitor が無限スピンする → [手順 5](#5-push-1-ラウンド-1-push) / [手順 8](#8-セッション保存--再レビュー誘導))
- **`waiting` 時に `eyes_present` を無視して即 `@codex review` しない**。eyes が残っている間はレビュー進行中なので待機する (二重トリガー防止)

---

## 検証メモ

`scripts/poll-codex-review.sh` は MERGED 済みの #925 / #812 で過去時刻 baseline により検証済み:

- **approved 検出**: #925 baseline=`15:19:48Z` (最後の push 直後) → `signal=approved` / `approved_at=15:21:15Z` / comments=0 (最終コミットは review なし +1 のみ、を正しく判定)
- **comment 回収**: #925 baseline=`15:10:02Z` → review `4390706057` (commit 7bc7e35) / comment `3325242373` (CLAUDE.md:479, outdated=false) を正しく紐付け
- **false-approve 防止**: #925 baseline=`15:21:16Z` (+1 直後) → `signal=waiting` (gating が機能)
- **別 PR 再現**: #812 baseline=`11:52:14Z` → `approved` / `11:54:54Z`

**実運用で確認すべき (過去データでは再現不可)**:
- `signal=new_review` の単独発火 (過去 PR は +1 が常に最後にあるため approved に隠れる)。次の実 PR で「指摘あり・+1 なし」状態を確認
- Codex の +1 の `created_at` がサイクルごとに更新されるか固定か → timestamp gating で足りるか baseline capture も要るか
- 典型的な再レビュー latency → `escalate_after_seconds` の調整
