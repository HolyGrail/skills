# Phase 5.5: CI + Review Loop

Phase 5 (Open PR 作成) と Phase 6 (Cleanup) の間に挟まる、**CI と Codex 自動レビューの能動監視 + 自動対応ループ**。Phase 5 完了直後に自動突入する。PR open をトリガーに CI と Codex bot のレビューが走るので、本フェーズは (1) CI checks の完了を監視して FAIL があれば修正 push、(2) Codex の指摘を triage し、成立を確認できた P1/P2 を直してローカルレビューを通し、1 回だけ push して返信する、を **CI 全成功 + レビュー収束** まで繰り返す。収束の判定は [終端とエスカレーション](#終端とエスカレーション) に定める。「👍 が付くまで push を続ける」ではない。

SKILL.md 本体から「Phase 5 完了後に自動突入するとき」「`/dev review` で再開するとき」「CI / Codex レビュー対応ループの state machine / 監視ロジックが必要なとき」に参照する。

## Contents
- [ループが伸びる仕組み](#ループが伸びる仕組み)
- [前提: Codex の挙動 (実 PR 観測で確定)](#前提-codex-の挙動-実-pr-観測で確定)
- [起動方法と前提条件](#起動方法と前提条件)
- [待ち方 (relay モードと poll モード)](#待ち方-relay-モードと-poll-モード)
- [State machine](#state-machine)
- [CI 監視 (gh pr checks)](#ci-監視-gh-pr-checks)
- [監視メカニズム (poll-codex-review.sh)](#監視メカニズム-poll-codex-reviewsh)
- [1 ラウンドの対応フロー](#1-ラウンドの対応フロー)
- [triage 分類ルール](#triage-分類ルール)
- [自律修正を止める条件](#自律修正を止める条件)
- [返信フロー](#返信フロー)
- [終端とエスカレーション](#終端とエスカレーション)
- [セッション保存](#セッション保存)
- [計測](#計測)
- [禁止事項](#禁止事項)

---

## ループが伸びる仕組み

2026-03〜09 の 8 リポジトリ 1,164 PR (Codex の指摘が付いた PR 174 件、506 ラウンド、指摘 658 件) と、/dev セッション 162 件の記録を集計した。ループが伸びる仕組みは次のとおりだった。

- 1 ラウンドの指摘数は 1 件が 74%、2 件が 22%。Codex は 1 パスに 1〜2 件ずつしか出さないので、指摘を直して push するたびに次の 1〜2 件が出る。ラウンド数はおおむね「最終的に出る指摘の総数 ÷ 1〜2」になる
- 多ラウンド PR の 2 ラウンド目以降の指摘は、元の変更に対する初出が 50%、直前の fix に対する指摘が 34%。前者は検出の小出し、後者は Codex の提案文をそのまま実装して次のパスで穴を突かれる連鎖 (12 ラウンドの PR では 13 件中 10 件がこれで、最終ラウンドは前ラウンドの順序提案を反転させていた)
- P3 は 658 件中 7 件。「P3 を直すからループする」は当たらない。指摘の 9 割は妥当で、反論は 77 件中 3 件
- 返信のみのラウンドで `@codex review` を投げると、同じ commit が再レビューされて新しい P1 が出る (GBF-community #1145 R5)
- 利用上限に達すると「You have reached your Codex usage limits」が投稿され、head 未レビューのまま止まる (半年で 22 回)
- 上限 5 ラウンドのエスカレーションでは「続行」が選ばれ、上限は 8 / 10 / 12 に引き上げられていた

このフェーズは、(a) 指摘対応で push する回数そのものを予算にし、(b) push 前に直した箇所と影響先へ focus したローカルレビューを掛けて 1 push あたりの消化数を上げ、(c) 指摘をパッチではなく問題の記述として扱い、(d) 👍 以外の収束条件を持つ。GitHub 上のラウンド数を減らすだけでは、ループを手元に移しただけになりうる。[計測](#計測) の指標で確かめる。

---

## 前提: Codex の挙動 (実 PR 観測で確定)

以下は **推測ではなく** HolyGrail の PR を `gh api` で観測して確定した事実。state machine はこれに基づく。Codex のレビュー本文 (`### 💡 Codex Review`) の "About Codex in GitHub" にも公式記述がある。

| 項目 | 確定事実 |
|---|---|
| **bot アクター** | `chatgpt-codex-connector[bot]` (`--bot` で上書き可能にしてある) |
| **トリガー** (公式) | PR を review 用に open / **draft を ready にする** / `@codex review` とコメント。push 後の再レビューは設定「レビューのトリガー」(オープン時 / すべてのプッシュ時 / スマート検出) に従う |
| **再レビュー** | push (新コミット) で再トリガーされることが多い (スマート検出でも観測)。保証はないので、自動を待ってから明示 `@codex review` でフォールバックする |
| **指摘あり** | `pulls/{n}/reviews` に review (`state: COMMENTED`) + `pulls/{n}/comments` に inline comments。コメントは `pull_request_review_id` で review に紐付く |
| **指摘なし (approve)** | PR 本体(issue) に `+1`(👍) reaction。issue comment「Codex Review: Didn't find any major issues.」が併せて付くこともある。**`APPROVED` state の review は使わない** |
| **利用上限** | issue comment「You have reached your Codex usage limits for code reviews」。以後レビューは付かない。上限が戻ると head をレビューすることがある (#1282 は 78 分後) |
| **同一 commit の再レビュー** | push が無くても `@codex review` で再レビューされ、前のパスで出なかった指摘が出る (#1145 R5)。返信だけのラウンドでは投げない |
| **1 パスの検出数** | 1 件 74% / 2 件 22% (2026-03〜09、506 ラウンド)。1 パスで全部出る前提を置かない |
| **fix の再検証** | Codex は自分の P1 に対する fix が効いているかを検証しない (#1145 R1 の PRAGMA no-op を見逃した)。fix の検証は自分で行う |
| **コメント形式** | inline comment の本文冒頭に重要度バッジ `![P2 Badge]`。`in_reply_to_id` で返信スレッド、`commit_id`/`line` でレビュー対象 |
| **👀 (eyes)** | レビュー進行中の一時マーカー。完了後は消える → **終端判定には使わない** (補助情報) |
| **コミットの扱い** | Codex は **最新コミットをレビューし中間コミットをスキップ**。最終コミットは review なしで **+1 のみ** のことが多い |
| **再レビュー latency** | 可変 (#925: ~2 分 / #812: 一部 ~29 分)。タイムアウトは余裕を持たせる (既定 40 分) |
| **設定** | https://chatgpt.com/codex/cloud/settings/code-review の「徹底的なコードレビュー」(新しい問題が見つからなくなるまで探す) と「レビューのトリガー」。2026-09-07 から前者は全リポジトリで ON、後者はスマート検出。どちらもこのループからは変えられない |

**設計上の最重要点 (false-approve 防止)**: GitHub は (user, content) で reaction を dedupe するため、Codex の +1 は **1 つしか存在せず created_at が固定されうる**。「+1 が存在する」で approved 判定すると、過去ラウンドの +1 を見て早期終了する事故が起きる。→ **👍 と issue comment は、必ず「自分の最後の push より新しい」ものだけをシグナルとして扱う** (baseline-diff)。baseline (`review.last_push_at`) を動かすのは push のときだけにする。review は時刻ではなく処理済みの id で絞る (未処理の review は、push の前後にどの順序で届いても返る)。push しないラウンドで baseline を review の時刻まで進めると、その時刻より前か同じ秒に付いた今の head への 👍 が二度と返らなくなる。

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

`WT_PATH` / `BRANCH` / `PR_URL` / `plan_issue` (旧セッションは `plan_file`) / `followups` / `review` をセッションから読み込む。`review` が無ければ初期化する ([セッション保存](#セッション保存) のスキーマ)。旧スキーマのセッション (`push_rounds` や `findings` が無い) は、無いフィールドを初期値で補う。旧セッションの `last_review_commit` は使わない (head がレビュー済みかはポーリングの `head_review` で判定する)。`last_push_commit` があれば、`last_push_at` は再開のたびにそのコミット時刻から取り直す ([手順 7](#7-commit--push--返信--pr-本文) の `NEW_PUSH_AT` と同じ式。旧手順は push しないラウンドで `last_push_at` を review の時刻まで進めていたので、そのままだと今の head への 👍 が返らないことがある)。`wait_started_at` が無ければ再開した時刻で補う (旧セッションの `last_push_at` はコミット時刻で、push より前になりうる。再開時刻なら待機を短く見積もるだけで、レビューの来る前に終わらせることはない)。

---

## 待ち方 (relay モードと poll モード)

CI と Codex の結果を待つ方法は、pr-relay mod が動いているかで変わる。ツール一覧に `mcp__pr-relay__watch` があれば **relay モード**、無ければ **poll モード**。判定はセッションファイルに保存せず、待つたびにツール一覧で決める (再開したセッションで mod の有無が変わりうる)。

poll モードは [State machine](#state-machine) の図のとおり、`gh pr checks --watch` と `poll-codex-review.sh --watch` を `run_in_background` で回して自分で待つ。

### relay モード

pr-relay は PR を 1 分ごとに確かめ、Codex のレビュー、Codex の 👍 (または「Didn't find any major issues」)、マージのときにプロンプトでセッションを起こす。待つ側は監視を頼んでターンを終える。

**push の後 (Phase 5 の PR 作成直後を含む)**:

1. [手順 8](#8-台帳と-baseline-の更新) の「push した場合」の更新 (`last_push_at`、`wait_started_at`、保存した判定の初期化) を済ませ、`review.loop_status = "monitoring"` をセッションファイルに保存する (起こされた後と `/dev review` での再開は、ここから状態を読む)。`last_push_at` と `wait_started_at` は push のときだけ動かす
2. `mcp__pr-relay__watch` を `pr_url` = `$PR_URL`、`since` = `review.last_push_at` で呼ぶ (pr-relay が自分で拾った baseline ではなく、セッションの baseline に揃える)
3. CI を待つ手段を用意する ([CI 監視](#ci-監視-gh-pr-checks) の「relay モードでの CI」)
4. 時間切れ用のタイマーを 1 本張る: `ARMED=$(date -u +%Y-%m-%dT%H:%M:%SZ); sleep <秒>; echo "armed_at=$ARMED"` を `run_in_background` の Bash で起動する。秒数は `escalate_after_seconds / 2` (既定 1200。Bash の `timeout` はそれより長くする)。pr-relay は時間の経過では起こさないので、これが無いと Codex 未設定のリポジトリやレビューが来ない PR で、`@codex review` のフォールバックと待機上限の分岐に自動では届かない。Codex をポーリングするのではなく、時間切れを確かめるためのもの
5. 「PR #N を pr-relay が監視中。CI と Codex の結果を待ちます」と 1 行報告して **ターンを終える**。`poll-codex-review.sh --watch`、`sleep` のループ、ScheduleWakeup では待たない。これは承認待ちの停止ではなく、待機の手段である (SKILL.md「フェーズ間で停止しない」に反しない)

**起こされたとき**: プロンプトの種類ごとに、State machine の対応する状態へ入る。

| 届いたもの | 入る状態と最初の作業 |
|---|---|
| 「Codex が PR #N … にレビューを付けました」 | `poll-codex-review.sh` を **`--watch` なしで 1 回** 呼ぶ (引数は poll モードと同じで `$LAST_PUSH_AT` = `review.last_push_at`、`--processed-reviews` = `review.processed_review_ids`)。`signal=new_review` の `new_comments[]` で [RESPONDING](#1-ラウンドの対応フロー) に入る。pr-relay のプロンプトは件数しか運ばないので、triage に要るコメント本文と id はここで取る |
| 「Codex が PR #N … を approved にしました」 | 下の「状態の確定」を行う |
| CI の結果 (`ci-monitor-event`、または `gh pr checks --watch` の完了) | fail / cancel なら [CI_FIXING](#ci-fail-の修正フロー-ci_fixing) に入る (その手順 0 で届いていたレビューを拾う)。緑なら下の「状態の確定」を行う |
| 時間切れ用タイマーの完了 | 出力の `armed_at` が `review.wait_started_at` より前 (後の push より前に張ったタイマー) か、ループがすでに終端なら、何もせずターンを終える。それ以外は下の「状態の確定」を行う |
| 「PR … がマージされました。/dev cleanup の手順で…」 (帯の `cleanup` ボタン) | [Phase 6](phases-5-6.md#phase-6-cleanup-後片付け) へ |

**状態の確定**: approved の知らせ、CI の緑、タイマーの完了は、どれもここに合流する。

1. `poll-codex-review.sh` を 1 回呼ぶ (引数は上の表と同じ)。`new_review` なら RESPONDING に入る。`approved` なら `review.approved_at` を、`usage_limited` なら `review.timeout_reason = "usage-limit"` を保存する。`waiting` なら `review.wait_started_at` からの経過を `total_wait_seconds` として、State machine の `signal=waiting` の分岐 (`@codex review` を 1 回投げる / CI-only / no-head-review / CONVERGED 判定) を適用する
2. 終端の条件を満たし、head の CI が緑なら終える ([終端とエスカレーション](#終端とエスカレーション))。CI が pending ならターンを終え、CI の結果でもう一度ここに来る。fail なら CI_FIXING に入る
3. 終端でなく、待機上限にも届いていなければ、残りの時間 (最大 `escalate_after_seconds / 2`) でタイマーを張り直し、`mcp__pr-relay__watch` を呼んでターンを終える

`signal` がプロンプトと食い違う (例: レビューの知らせなのに `waiting`) ときも、プロンプトではなくポーリングの `signal` に従い、上の「状態の確定」を行う (push しないラウンドの後は baseline が動かないので、張り直した監視が処理済みの review を知らせることがある)。

**pr-relay が起こさない事象**: 次は relay モードではセッションを起こさない。ターンを終えた後に起きたものは、時間切れ用タイマーで起こされたとき、または人が `/dev review` で再開したときに、上の「状態の確定」で判定する。

- 利用上限 (pr-relay はトーストで人に知らせるだけ): `signal=usage_limited` なら [REVIEW_INCOMPLETE](#review_incomplete-head-が未レビュー) (`usage-limit`)
- レビューが来ないまま時間が過ぎた: 「状態の確定」の手順 1 の `waiting` の分岐で扱う
- PR のクローズ (トーストだけ): 再開時に `gh pr view --json state` で確かめ、前提条件 2 に従う

**deny を受けたとき**: 監視中の PR があると、pr-relay は `poll-codex-review.sh --watch` を実行する Bash を「pr-relay is watching … End the turn instead of waiting here.」で deny する (`--watch` なしの 1 回呼び出しは通す)。これを受けたら、再試行も、1 ショットや ScheduleWakeup への切り替えもせず、上の手順 1 の保存を済ませてターンを終える。

---

## State machine

終端は次の 3 つのいずれか (判定の詳細は [終端とエスカレーション](#終端とエスカレーション)):

- **APPROVED**: 最新 push 以降に Codex の 👍 (または「Didn't find any major issues」) が付き、head に対する CI が緑
- **CONVERGED**: push を伴わないラウンドの終端。head に対するレビューが完了していて、台帳の P1/P2 に全て disposition が付き、CI が緑
- **REVIEW_INCOMPLETE**: 利用上限などで head が未レビューのまま待機上限に達した。approved とは報告しない

push するたびに CI と Codex の判定は仕切り直しになる (CI は HEAD コミットに対して走り直し、Codex は再レビューする)。

図の CI_WAIT と MONITORING の待ち方は poll モードのもの。relay モードでは CI_WAIT と MONITORING を同時に待ち、どちらの結果も「起こされたとき」に届く ([待ち方](#待ち方-relay-モードと-poll-モード))。届いた後の分岐と終端は両モードで同じ。

```
[起動] Phase 5 完了直後に自動突入 (再開は /dev review <slug>)
  ├─ 前提条件チェック (Draft なら gh pr ready で Open 化して続行)
  └─ baseline 記録: review.last_push_at = 現在の HEAD コミットの push 時刻
        ※ 取得: gh api repos/{repo}/commits/{sha} --jq .commit.committer.date
          (or PR 作成時刻 / 監視開始時刻のうち最も確実なもの。「これ以降の Codex
           👍 とコメントだけを新規とみなす」基準なので、取りこぼすより早めでよい)
        review.last_push_commit = その sha。baseline を動かすのは push のときだけ

         ┌──────────────────────────────────────────────────────┐
         ▼                                                      │
[CI_WAIT] gh pr checks "$PR_URL" --watch (run_in_background)     │
  ├─ 全 bucket が pass/skipping → [MONITORING] (CI 緑)            │
  ├─ fail / cancel あり → [CI_FIXING] (手順 0 の poll で届いていた │
  │    レビューを拾い、あれば RESPONDING と同じ push にまとめる)      │
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
  ├─ signal=new_review (processed_review_ids に無い codex review。approved より優先) → [RESPONDING]
  ├─ signal=approved (last_push_at 以降に codex +1 か「Didn't find any major issues」)
  │     └─ CI が最新 push に対して緑であることを再確認 → [APPROVED] 終了
  ├─ signal=usage_limited (last_push_at 以降に利用上限コメント)
  │     └─ → [REVIEW_INCOMPLETE] (種別 usage-limit)
  └─ signal=waiting (内部タイムアウトで exit)
        ├─ total_wait_seconds += 経過。escalate_after_seconds 超過:
        │     ├─ Codex イベントがこの PR で一度も観測されていない
        │     │   → Codex 未設定の可能性。CI 緑なら [DONE (CI-only)]
        │     ├─ usage_limit_active_at あり、head が未レビュー → [REVIEW_INCOMPLETE] (種別 usage-limit)
        │     ├─ 過去にイベントあり、head が未レビュー (head_review が null) → [REVIEW_INCOMPLETE] (種別 no-head-review)
        │     └─ 過去にイベントあり、head はレビュー済み (head_review あり) → [CONVERGED 判定]
        ├─ eyes_present==true → レビュー進行中。@codex review は投げず待機継続
        ├─ eyes_present==false、直近のイベントが自分の push、push から
        │   escalate_after_seconds/2 以上経過、codex_review_requested==false
        │   → @codex review を 1 回だけ投げる (codex_review_requested=true)
        └─ それ以外 → 再度 --watch を起動 (MONITORING 継続)

[RESPONDING] 1 ラウンド = 最大 1 push
  1. remote-ahead reconcile (git fetch + ahead/behind)
  2. 最新 review に紐づく未処理 inline comments を回収
  3. 全件 triage: 成立を一次情報で確認してから fix / rebut / followup / reply-only
  4. 修復記録を書く (P1 と、並行制御・状態遷移・永続化に触れる P2)
  5. fix を実装 (同根の全箇所、最小の一貫した変更) → Phase 3 検証 → P1 は再現テスト
  6. push 前ローカルレビュー (local-codex-review.sh、最大 2 パス)
  7. 1 コミット → push → 各コメントに返信 → PR 本文を同期更新
  8. 台帳 (findings[]) と processed_review_ids を更新、push したら baseline を前進、push_rounds++ / rounds++
  ├─ push した → [CI_WAIT]
  ├─ push しなかった → [CONVERGED 判定] (P1/P2 を rebut したなら [ESCALATED])
  └─ push_rounds >= max_push_rounds の状態で次の new_review が来た → [ESCALATED]
     (指摘の重大度によらず。修正はエスカレーションの選択肢の中で行う)

[APPROVED]          CI 全成功 + 👍。loop_status=approved
[CONVERGED]         CI 全成功 + head レビュー済み + P1/P2 全件 disposition 済み。loop_status=converged
[REVIEW_INCOMPLETE] head 未レビュー。loop_status=review-incomplete、timeout_reason に種別
[DONE (CI-only)]    Codex 未設定リポジトリの終端。loop_status=timeout
[ESCALATED]         残指摘の一覧と推奨 disposition を提示して AskUserQuestion
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

### relay モードでの CI

pr-relay は CI を見ない (Desktop アプリが CI の結果をセッションへ送るので、両方で見ると同じ失敗で二重に起こされる)。待ち方は実行環境で分ける。

- **Desktop アプリ** (ツール一覧に `mcp__ccd_pr__get_status` がある): `mcp__ccd_pr__get_status` が PR を報告しなければ `mcp__ccd_pr__bind_pr` で紐付ける。CI の結果は `<ci-monitor-event>` として届くので、`gh pr checks --watch` は回さない
- **それ以外 (CLI)**: 従来どおり `gh pr checks "$PR_URL" --watch` を `run_in_background` で起動してからターンを終える。完了するとセッションが起こされる

どちらでも、起こされた後の判定は上の `gh pr checks --json` の 1 ショットで行う。

### CI FAIL の修正フロー (CI_FIXING)

0. **入口でレビューの有無を確かめる**: `poll-codex-review.sh` を `--watch` なしで 1 回呼ぶ (`$LAST_PUSH_AT` = `review.last_push_at`、`--processed-reviews` = `review.processed_review_ids`)。CI を待つ間に届いたレビューは、確かめずに CI 修正を push しても次のポーリングで返るが、その指摘の fix が別の push になり、Codex のパスを 1 回余分に使う。`new_review` なら [1 ラウンドの対応フロー](#1-ラウンドの対応フロー) で triage と fix を進め、CI 修正と同じ 1 push にまとめる (下の手順 4。この push は指摘対応を含むので `push_rounds` に数える)。それ以外の signal は「状態の確定」の手順 1 と同じく保存し、そのまま CI 修正に進む。relay モードでも poll モードでも同じ
1. 失敗した check の詳細を取得する: `gh pr checks --json` の `link` から run ID を特定し、`gh run view <run-id> --log-failed` でログを読む
2. **根本原因を診断してから修正する**。ローカルの Phase 3 検証で再現を試み、再現すればローカルで修正 → PASS を確認してから push する。ローカルで再現しない失敗 (環境差・依存キャッシュ・secrets) はログから原因を特定する。修正の実装は [model-routing.md の判定手順](model-routing.md#判定手順)で実行主体を自律選定し subagent / codex へ委任してよい (診断・PASS 判定・push はメインに残す)
3. **flaky の扱い**: 失敗が今回の変更と無関係で非決定的に見える場合のみ、`gh run rerun <run-id> --failed` を **1 回だけ**試す。再実行でも落ちたら実問題として扱い、修正する。rerun を繰り返して緑を引き当てるのは禁止
4. 修正 push は「1 ラウンド 1 push」規律の対象。push の直前に [手順 7](#7-commit--push--返信--pr-本文) と同じく、ポーリングをもう 1 回呼ぶ (手順 0 の後、診断と修正の間に届いたレビューを、同じ push に含めるため)。**CI 修正とレビュー指摘対応が同時に溜まっている場合は 1 つのコミット群にまとめて 1 push にする** (別々に push すると Codex の追跡が壊れる)
5. push 後は手順 8 の「push した場合」と同じく baseline (`review.last_push_at`、`review.wait_started_at`) を前進させて保存した判定を戻し、`ci_fix_rounds` をインクリメントして CI_WAIT に戻る。CI 修正だけの push は `push_rounds` に数えないが、Codex のパスは 1 回消費し、新しい指摘が出ることもある。レビュー指摘の対応が保留になっているなら、CI 修正を単独で push せず、その対応と同じ push にまとめる
6. CI 失敗の原因が **main 由来 (既存問題)** と切り分けられた場合も、CI を落とす以上 Phase 4-B マトリクスの第 1 行に該当するので今回 PR で修正する
7. 自分では解決できない失敗 (リポジトリ設定・secrets 不足・外部サービス障害・billing 等) に行き着いたら、診断結果を添えて [ESCALATED] へ

## 監視メカニズム (poll-codex-review.sh)

Codex 監視は同梱スクリプト [`scripts/poll-codex-review.sh`](scripts/poll-codex-review.sh) に集約する (baseline-diff / commit gating ロジックをインラインで毎回組むと事故るため)。relay モードでは、以下の `--watch` と ScheduleWakeup は使わない ([待ち方](#待ち方-relay-モードと-poll-モード))。

### なぜポーリングを分割するか

`gh api` の応答待ちと前景 Bash の **600s 上限** (background の上限は 2 時間) に対し、再レビュー latency は最大 ~30 分。1 本の `while + sleep` では span できない。そこで **「短い --watch を background で回し、変化検知 or 内部タイムアウトで exit → Claude が起きて判断 → 必要なら再起動」** という短チェック反復にする。Claude はアイドル中コンテキストを消費しない。

### 使い方

```bash
# SKILL_DIR はスキルを読み込んだときの base directory。毎回代入する ([phases-5-6.md の PR 作成前ローカルレビュー](phases-5-6.md#pr-作成前ローカルレビュー))
SKILL_DIR="<スキルの base directory>"
SCRIPT="$SKILL_DIR/references/scripts/poll-codex-review.sh"

# 処理済み review の id。セッションの配列をカンマ区切りにする (空なら空文字列)
SESSION_FILE="$HOME/.claude/dev-sessions/<slug>.json"
PROCESSED=$(jq -r '.review.processed_review_ids | join(",")' "$SESSION_FILE")

# --watch: background で起動する (前景 sleep が禁止の環境のため run_in_background 必須)
"$SCRIPT" "$OWNER/$REPO" "$PR_NUMBER" "$LAST_PUSH_AT" --processed-reviews "$PROCESSED" --watch --max-wait 540
```

- **必ず `run_in_background: true` の Bash で起動する**。スクリプトの `while` ループごと background プロセスになり、exit 時に Claude が起こされる。
- 第 3 引数 `$LAST_PUSH_AT` は `review.last_push_at` (ISO8601 UTC)。**👍、「Didn't find any major issues」、利用上限コメントは、これより厳密に新しいものだけがシグナル**になる。
- `--processed-reviews` は `review.processed_review_ids`。review は時刻で絞らず、ここに無いものを未処理として返す。渡し忘れると、処理済みの review が `new_review` で返り続ける (コメントは `processed_comment_ids` で弾かれるが、ループが進まない)。どの呼び出しでも必ず渡す
- 出力 (1 行 JSON):
  ```json
  {"signal":"approved|new_review|usage_limited|waiting","approved_at":"<ISO|null>",
   "usage_limit_at":"<ISO|null>","usage_limit_active_at":"<ISO|null>",
   "head_sha":"<sha>","head_review":{"id":...,"commit_id":...,"submitted_at":...}|null,
   "latest_review":{"id":...,"commit_id":...,"submitted_at":...,"body":...}|null,
   "new_comments":[{"id":...,"pull_request_review_id":...,"in_reply_to_id":...,
                    "path":...,"line":...,"outdated":bool,"commit_id":...,
                    "html_url":...,"created_at":...,"body":...}],
   "eyes_present":bool,"checked_at":"<ISO>"}
  ```
- signal 優先順位: **new_review > approved > usage_limited > waiting**。未処理の review が 1 件でもあれば、approved との時刻によらず new_review を返す。approved の後か同じ秒に届いた review (同じ commit の再レビューで指摘が出た場合など) も、approved より前に届いて未処理の review も、指摘を triage せずに APPROVED へ進まない。baseline は push のときしか動かないので、approved はその review を処理済みにした後のポーリングで返る。
- `gh api` が失敗すると、結果を空とは見なさず終了コード 3 で終わる (空と見なすと、利用上限や approved を取りこぼして `waiting` になる)。終了コード 3 は `waiting` として扱わず、時間をおいて 1 回だけ再実行し、それでも失敗したら認証やレート制限を確かめて報告する
- `approved_at` は 👍 reaction と「Didn't find any major issues」コメントのうち新しい方。`latest_review` は未処理の最新 review。
- `head_sha` はスクリプトが `pulls/{n}` から取った PR の head。`head_review` は head を対象とする最新の review で、処理済みも含む。**`head_review` が null でなければ head はレビュー済み**。前の head への遅れた review を後から処理しても、この判定は変わらない
- `usage_limit_active_at` は baseline によらず、Codex の最後の反応 (head への review / 👍 /「Didn't find」) 以降 (同じ秒を含む) の利用上限コメントの時刻を返す。レビューの後に上限が付き、その対応の push で baseline が越えても、上限が戻っていないことをここで判定できる。前の head への review は上限より前に依頼されて遅れて届いたものなので、上限が戻った証拠に数えない


### ScheduleWakeup フォールバック

background `--watch` の sleep が環境で動かない / 長時間にわたり再起動を繰り返す場合は、**1 ショットモード** (`--watch` なし) を ScheduleWakeup で間欠実行してもよい。間隔は **240–270s 推奨** (Anthropic prompt cache の 5 分 TTL 内に収めてコンテキストを温存)。

```bash
"$SCRIPT" "$OWNER/$REPO" "$PR_NUMBER" "$LAST_PUSH_AT" --processed-reviews "$PROCESSED"   # 1 ショット (即 exit)
```

---

## 1 ラウンドの対応フロー

`signal=new_review` を受けたら以下を実行する。push は **1 ラウンドに最大 1 回** (複数 push すると Codex が中間コミットをスキップして混乱するため)。

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
- `id` が `review.rebutted_comment_ids` に **無い** (反論済みの再提起は新規扱いしない)
- `outdated == false` (`line == null` の outdated コメントは「対象行が消滅/移動」= 既に解消された可能性が高い。**自動修正の対象にしない**。本当に解消済みか軽く確認し、未解消なら fix 候補に拾い直す。processed に入れて以後スキップ)

### 3. triage (成立の確認を先に)

各指摘について、指摘が成立する入力、実行順序、環境を一次情報 (実コード、テスト、実 DB、公式ドキュメント) で確認する。確認できた P1/P2 だけを fix にする。バッジは triage の入力であって結論ではない (P3 でもデータ損失を述べていれば P1 として扱い、P2 でも成立しなければ rebut する)。分類の表は [triage 分類ルール](#triage-分類ルール)。

### 4. 修復記録

P1 の指摘と、並行制御、状態遷移、永続化に触れる P2 の指摘には、fix を書く前に次の 4 点を書く (返信本文に要約を載せ、全文はセッションの `findings[].repair` に残す)。

- **失敗**: 発火する入力または実行順序と、観測した (または根拠を示せる) 結果
- **不変条件**: 成功時、失敗時、再試行時、並行実行時に保たれるべき性質
- **修復**: 選んだ変更がその不変条件を回復する理由。影響する呼び出し元と、同型の箇所
- **証拠**: 再現の方法と、その環境での検証結果

並行制御の指摘には、interleaving か状態遷移のトレースを書く。1 つのスケジュールで通るテストは、並行正しさの証明にならない。

他の P2 は、返信に「この変更でその振る舞いが直る理由」を 1 行書けば足りる。

### 5. fix の実装と検証

- 指摘文は問題の記述であって、パッチではない。提案されたコードをそのまま貼らず、修復記録の不変条件から変更を決める。同根の箇所 (同型のエラー処理、同じ所有者チェック、同じ JOIN の消費側) は全部同じ commit で直す。Codex は同型の箇所を別ラウンドに分けて出すので、ここで拾えばラウンドが減る
- 変更は不変条件を回復する最小の一貫したものにする。防御コード、抽象化、設定項目、ついでのリファクタを足さない。fix 後に `/simplify` は掛けない (差分が増えると次のパスの指摘面が増える)
- 範囲とテストは Phase 2 の「スコープとテストの規律」([phases-1-4.md Phase 2 手順 4](phases-1-4.md#phase-2-implement-実装)) に従う。指摘の外で見つけた問題はこの fix に混ぜず followup にする。P1 の再現テスト (下記) は規律の「タスクが求める箇所」に当たる
- 実行主体は [model-routing.md の判定手順](model-routing.md#判定手順)で自律選定してよい。修復記録の作成と、証拠の判定はメインに残す
- **Phase 3 (Verify) を再実行** (変更箇所に限定しない。コマンド自動検出は [phases-1-4.md Phase 3](phases-1-4.md#phase-3-verify-検証))。新規 FAIL は修正、既存 FAIL は followups[] へ ([phases-1-4.md Phase 4-B](phases-1-4.md#4-b-既存問題-main-にも存在))
- **P1 の fix には再現テストを付ける**。修正前に落ちて修正後に通ることを確認する。PRAGMA や設定のような宣言的な変更は、実 DB や実データで効いていることを確認する (Codex は fix の有効性を見ない)

### 6. push 前ローカルレビュー

push するたびにクラウドのレビュー 1 回と CI 1 回を使う。ローカルの 1 パスも週間利用枠の 0.5〜1% を使い、クラウドのレビューと同じメーターに載る (2026-09-07 実測)。だから既定は focus 付きの 1 パスで、今回の修正とその影響先だけを見る。役割は「修正が不変条件を回復しているか、影響先を壊していないか」をクラウドの往復と CI を使う前に確かめることで、変更全体の再発見ではない。

```bash
# SKILL_DIR はスキルを読み込んだときの base directory。毎回代入する ([phases-5-6.md の PR 作成前ローカルレビュー](phases-5-6.md#pr-作成前ローカルレビュー) と同じ)
SKILL_DIR="<スキルの base directory>"
SCRIPT="$SKILL_DIR/references/scripts/local-codex-review.sh"
# run_in_background で起動する (1 パス 4〜6 分)
"$SCRIPT" "$WT_PATH" "origin/$DEFAULT_BRANCH" --focus "<今回直した振る舞いと、その影響先>"
```

- `--focus` を付けると、レビュー範囲はその対象と影響先 (呼び出し元、消費側、同型の箇所) に限られ、変更全体は探し直さない。1 パス目は今回の fix と影響先だけを見る。P1/P2 が出たら手順 3〜5 で処理し、そのときだけ 2 パス目を掛ける (focus は 2 回目の fix)。3 パス目は掛けない
- 2 パス目でも P1/P2 が出て直した場合、その head はローカルレビューを通っていない。`review.head_local_review = "unreviewed"` として記録し、push 後の Codex レビューが head を見るまで CONVERGED にしない
- 掛けないラウンド: fix が typo やコメントなど 1 行の機械的修正だけのとき、reply-only や followup だけで push しないとき。このときは `head_local_review = "cloud-first"` と記録する
- パスごとに見つかる集合は変わる (同じコードに 3 回掛けて 3 件、2 件、2 件、重なりは 2 件だった)。「ローカルで出なかったからクラウドでも出ない」とは言えない。出た分を先に消化する仕組みとして使う
- codex CLI が無い、またはタイムアウトしたときは `head_local_review = "skipped"` と理由を記録して続行する (ゲートで止まらない)
- `local_review_passes` を掛けたパス数だけ加算する

### 7. commit → push → 返信 → PR 本文

push の直前に `poll-codex-review.sh` を `--watch` なしで 1 回呼ぶ (`--processed-reviews` は `review.processed_review_ids`)。fix と検証とローカルレビューの間に届いたレビューを、同じ push に含めるためである。ここで拾えなかったレビュー (このポーリングから push までに届いたもの) も失われない。review は時刻ではなく処理済みの id で絞るので、push の後のポーリングで未処理として返る。`processed_review_ids` は手順 8 まで更新しないので、このポーリングはこのラウンドで triage 中のレビューも返す。`new_comments[]` のうち、`pull_request_review_id` がこのラウンドで triage したレビューの id に無いものだけを新着とし、新着があれば手順 2〜5 で triage してから同じ push に含める。push の直前に確かめるのはこの 1 回だけにする (ここで届いた指摘の fix にはローカルレビューを掛けない。1 ラウンド 1 push を崩さないため)。

```bash
cd "$WT_PATH" && git add -A && git commit -m "fix: Codex レビュー指摘に対応 (round N)" && git push
NEW_SHA=$(git -C "$WT_PATH" rev-parse HEAD)
# イベントの baseline (取りこぼすより早めでよい)。GitHub の時刻 (...Z) と文字列で比べるので UTC の Z 形式で出す。
# --format=%cI はコミット時のタイムゾーン (+09:00 など) が付き、辞書順が時刻順にならない
NEW_PUSH_AT=$(TZ=UTC git -C "$WT_PATH" show -s --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd HEAD)
PUSHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)                    # 実際に push した時刻。待機時間の基準
```

- `fix` が 0 件 (rebut / followup / reply-only のみ) なら push しない
- 各コメントに [返信フロー](#返信フロー) で返信する。push 直後に返信し、再レビューが始まる前に返信が見える状態にする
- P2 の followup はこのラウンド内で issue を起票し、番号を返信する (`gh issue create --body-file`、mktemp と head 検証のルールは Phase 6 と同じ。`followups[].issue_url` に記録する)。P3 の followup は followups[] に記録し、cleanup で起票する
- PR 本文を Phase 5-bis の「[PR 本文の再生成と更新](phases-5-6.md#phase-5-bis-post-pr-iteration)」ルールで同期更新する。**Test plan 節を破棄しない** / 変更履歴に「YYYY-MM-DD: Codex レビュー round N 対応」を追記 / `gh pr edit "$PR_URL" --body-file`

### 8. 台帳と baseline の更新

- `review.findings[]` に各コメントを追記する: `{id, round, severity, path, title, validity, disposition, evidence, sha, issue_url}` ([セッション保存](#セッション保存))
- `review.processed_comment_ids` に対応した id を追加、`rebutted_comment_ids` に反論した id を追加、`processed_review_ids` に処理した review id を追加する。push の有無によらず、triage した review はすべて `processed_review_ids` に入れる (入れないと、同じ review が次のポーリングで再び `new_review` として返り、コメントは全て処理済みで 0 件、即 MONITORING、また同じ review、という無限スピンになる)
- **baseline (`review.last_push_at`) は push したときだけ前進させる**:
  - push した場合: `review.last_push_at = NEW_PUSH_AT`、`review.wait_started_at = PUSHED_AT` (コミットから時間をおいて push しても、待機をレビューの来る前に打ち切らないよう、待機の基準は実際の push 時刻にする)、`review.last_push_commit = NEW_SHA`、`push_rounds += 1` (指摘対応を含む push だけ。CI 修正だけの push と Phase 5-bis の push は数えない)、`total_wait_seconds = 0` (poll モードの待機時間も push ごとに数え直す)。前の head について保存した `approved_at`、`timeout_reason`、`terminal_reason` は null に戻す。待ち方によらず、push はすべてこの更新を通る (Phase 5-bis の人手の push と CI 修正の push も含む)
  - push しなかった場合: `last_push_at` も `wait_started_at` も動かさない。同じ review の再返却は `processed_review_ids` で止まる。baseline を処理した review の `submitted_at` まで進めると、それより前か同じ秒に付いた今の head への 👍 が以後のポーリングで返らず、承認が失われる (前の head への遅れた review を処理したときに起きる)
- ポーリングの `head_review` が null でなく、`head_local_review` が `"unreviewed"` なら `"cloud-reviewed"` に更新する (head を Codex が見たので、手順 6 の「Codex レビューが head を見るまで」が満たされる)
- `review.rounds += 1` (受信したレビュー数)、`updated_at` 更新
- push した場合は CI_WAIT に戻る (relay モードでは [待ち方](#待ち方-relay-モードと-poll-モード) の「push の後」の手順で待つ)。push しなかった場合は [CONVERGED 判定](#converged-push-を伴わないラウンドの終端) に進む。**push しなかったラウンドで `@codex review` は投げない** (同じ commit が再レビューされ、新しい指摘が出る)

---

## triage 分類ルール

各 inline comment を Codex の重要度バッジ (本文冒頭 `![P1/P2/P3 Badge]`) と、成立の確認結果で分類する。**全件 triage する。黙って全部修正しない / 黙って全部無視しない**。

| 分類 | 条件 | アクション |
|---|---|---|
| **fix** | 一次情報で成立を確認できた P1/P2 | 修復記録 → 最小の一貫した変更。返信で対応内容と commit sha |
| **rebut** | 指摘が成立しない (前提誤り、既に対応済み、意図した設計) | 根拠付きで in_reply_to 返信 (一次情報、コード参照、gem や外部 API なら実装の該当行)。`rebutted_comment_ids` に記録。**P1/P2 の rebut は自分で閉じず、そのラウンドの終わりに [ESCALATED] でユーザー確認を取る** (反論は 77 件中 3 件と稀で、そこは人が見る価値がある) |
| **followup** | 妥当だが本 PR のスコープ外、または既存問題 | P2: このラウンドで issue を起票し番号を返信。P3: `followups[]` に `decision: "separate-pr"` or `"out-of-scope"` で追記し、返信で「別 issue として対応予定」を明示 |
| **reply-only** | P3、または妥当だが振る舞いに影響しない P2 バッジの指摘 | 同意か不同意を一言返して resolve する。push しない。P2 バッジを reply-only にするときは、台帳の `severity` を P3 にし、振る舞いに影響しない根拠と元のバッジを `evidence` に書く。P1 バッジは reply-only にしない (成立すれば fix、しなければ rebut)。P1/P2 の fix push に同乗できるのは typo やコメントの 1 行修正だけ。ロジックに触る P3 は followup |

判定指針:
- 成立の確認は、指摘が述べる入力や実行順序を実際に再現するか、コードで経路を追って示す。「もっともらしい」だけで fix にしない。2 ラウンド目以降の指摘の 9 割は妥当だったが、残りの 1 割を直すと fix 起因の指摘が増える
- 判断に迷う指摘 (設計トレードオフが絡む等) も、一次情報を集めて自律決定するのが原則 (Phase 1 の選定基準を適用し、判断根拠を返信に書く)。根拠を集めても fix / rebut のどちらとも確定できない場合のみ、そのコメントを保留にして他を先に処理し、保留分は [ESCALATED] 時にまとめてユーザーに提示する (1 件ごとに停止しない)
- `/pr-feedback` の分類体系 (must / imo / nits / q) は返信テンプレートの参照元として使う。優先度はバッジと成立確認で決める
- 台帳の `severity` は triage 後の重大度で、CONVERGED の条件 2 と 3 はこの値で判定する。バッジから上げ下げしたら (P3 バッジでもデータ損失を述べていれば P1、振る舞いに影響しない P2 は P3)、元のバッジを `evidence` に書く

---

## 自律修正を止める条件

次のいずれかに当たったら、そのラウンドで自律修正をやめ、[ESCALATED] に入る。修正の連鎖 (提案どおり直す → 次のパスで提案の穴が出る → また直す) は、ラウンドを重ねても収束しない。

- 同じ不変条件に対する修正が 2 ラウンド目に入った
- 今回の fix が、前ラウンドで採った順序や設計の判断を反転させる
- 失敗を再現できない、または修復が不変条件を回復することを示せない

エスカレーション時には、その不変条件と、これまでの修正の経緯を提示する。

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
head -c 300 "$REPLY"   # 想定する書き出しが含まれるか目視

# reply 投稿: 特殊文字を壊さないため jq で JSON 化し --input - で渡す
jq -n --rawfile b "$REPLY" '{body:$b}' \
  | gh api -X POST "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" --input -

rm -f "$REPLY"
```

- `$COMMENT_ID` は返信先トップレベルコメントの `id`
- 短い定型文 (`@codex review` 等の PR 全体コメント) は `gh pr comment "$PR_URL" --body "@codex review"` でよい (PR 本体コメント。長文なら `--body-file`)
- 代替: MCP `mcp__plugin_github_github__add_reply_to_pull_request_comment` でも返信可能 (gh が使えない環境)

返信内容の原則 (`/pr-feedback` の返信テンプレート準拠):
- **fix**: 「ご指摘ありがとうございます。<失敗の条件> に対して <不変条件を回復する変更> を入れました。同型の <箇所> も同じ commit で直しています。コミット `<sha>` で対応しました。」提案コードをそのまま採ったときも「ご提案どおり」ではなく、何が直るのかを書く
- **rebut**: 「<根拠: 一次情報/コード参照>。このため本指摘は<該当しない/既に対応済み>と判断しました。」(丁寧かつ技術的根拠ベース)
- **followup**: 「妥当なご指摘です。本 PR のスコープ外のため、issue #<番号> で対応します。」
- **reply-only**: 「ご指摘のとおりです。振る舞いには影響しないため、この PR では変更せず followup に記録しました。」

---

## 終端とエスカレーション

### APPROVED (👍 による正常終了)

`signal=approved` (last_push_at 以降の 👍 か「Didn't find any major issues」) を検知したら、次を確認して終了する:

1. **最新 push に対する CI が全成功** (`gh pr checks --json` で bucket が全て `pass`/`skipping`。pending が残っていれば CI_WAIT に戻って完了を待つ)
2. `findings[]` に disposition の無い P1/P2 が残っていない (残っていれば処理してから終了)
3. `review.loop_status = "approved"`、`review.approved_at = <時刻>`、`terminal_reason = "approved"` を保存
4. ユーザーに報告: 受信したレビュー数と push した回数、各ラウンドの対応サマリ (fix/rebut/followup/reply-only の内訳、CI 修正内容)、ローカルレビューのパス数と結果、CI 最終結果、最終コミット sha
   - 報告する各項目は、このセッションのツール結果 (`gh pr checks` の出力、`git log`、返信 API の応答) を指せるものだけにする。未検証の項目は「未検証」と明示する (SKILL.md「全フェーズ共通」6)
5. 「PR がマージされたら `/dev cleanup` で worktree を掃除し、followup を issue 化できます」と案内。relay モードでは「マージされるとプロンプトの上の帯に `cleanup` ボタンが出ます」と添える (pr-relay は終端の後もマージを見張っている)

### CONVERGED (push を伴わないラウンドの終端)

Codex の 👍 は無いが、次を全て満たせば終了する:

1. head に対する Codex レビューがある (`poll-codex-review.sh` を 1 回呼び、`head_review` が null でない)。last_push_at より後に届いた review でも、前の push で依頼したレビューが遅れて届いたものは commit_id が古い head を指すので、提出時刻や処理の順序では判定しない
2. `findings[]` の P1/P2 (triage 後の `severity`) が全て「検証済み fix」「ユーザー確認済み rebut」「issue 化済み followup」「ユーザーが受け入れた残存リスク」のいずれか
3. P3 と reply-only は返信済み (振る舞いに影響しないとして P2 バッジから P3 に下げた reply-only を含む)
4. head に対する CI が全成功
5. `review.head_local_review` が `"unreviewed"` でない

`review.loop_status = "converged"`、`terminal_reason = "converged"` を保存し、報告では「Codex の 👍 は付いていない。最終レビューの指摘は全て disposition 済み」と明記する。条件 1 を満たさない (head が未レビュー) なら終端にせず MONITORING に戻る (relay モードでは「状態の確定」の手順 3 と同じく、タイマーが残っていなければ張り直し、`mcp__pr-relay__watch` を呼んでターンを終える)。head のレビューを待つうちに利用上限か待機上限に達したときだけ REVIEW_INCOMPLETE にする。条件 2 で rebut にユーザー確認が無いなら ESCALATED。

### REVIEW_INCOMPLETE (head が未レビュー)

次のいずれかで、head に対するレビューが無いまま終わる:

| 種別 (`timeout_reason`) | 条件 |
|---|---|
| `usage-limit` | `signal=usage_limited` (last_push_at 以降に利用上限コメント)、または待機上限に達したときにポーリングの `usage_limit_active_at` が null でない (レビュー対応の push で baseline が上限コメントを越えた場合) |
| `error` | bot のエラーコメント、または「no environment」のようなレビュー不能の通知。`poll-codex-review.sh` はこれを判別しない (`waiting` が返る) ので、待機上限に達したとき、または `/dev review` で再開したときに、bot の最新の issue comment を読んで判定する |
| `no-head-review` | 過去に Codex イベントがあり、待機上限に達しても head に対するレビューが来ない |

head に対する CI がまだ pending か fail なら、種別を記録したまま CI_WAIT / CI_FIXING を続け、CI が緑になってから終える (relay モードでは CI と Codex を同時に待つので、利用上限の知らせが CI より先に届くことがある)。

`review.loop_status = "review-incomplete"`、`terminal_reason = "review-incomplete"` を保存する。**approved とは報告しない**。head に未レビューの変更があること、利用上限なら上限が戻った後に `@codex review` を人が投げる必要があること、または人手レビューに委ねることを報告する。

### DONE (CI-only) (Codex 未設定リポジトリの終端)

latency timeout に達し、かつ **この PR で Codex イベント (review / comment / +1 / 👀) が一度も観測されていない**場合は、Codex 未設定リポジトリと判断する。CI が全成功なら次で終了する:

1. `review.loop_status = "timeout"`、`terminal_reason = "ci-only"` を保存 (approved と区別する)
2. ユーザーに報告: CI 全成功の結果と、「Codex のレビューは観測されませんでした (未設定の可能性)。レビューは人間のレビュアーに委ねます」を明記
3. マージ後の `/dev cleanup` を案内

### ESCALATED (ユーザー判断が必要)

以下のいずれかで CI_WAIT/MONITORING/RESPONDING を抜け、AskUserQuestion でユーザーに判断を仰ぐ:

| 条件 | 内容 |
|---|---|
| **push 予算の到達** (`push_rounds >= max_push_rounds`、既定 3) の後に new_review が来た | 残指摘を一覧にして判断を仰ぐ |
| **自律修正を止める条件** ([上記](#自律修正を止める条件)) | 不変条件と修正の経緯を提示 |
| **P1/P2 の rebut** | 反論の根拠を提示し、閉じてよいかを確認 |
| **CI 失敗が自力で解決不能** (リポジトリ設定・secrets・外部サービス・billing 等) | 診断結果と失敗ログの要点を提示 |
| **検証 (ローカル) の根本原因を特定しても解決不能** | Phase 4-A の手順に従い判断を仰ぐ |
| **remote コンフリクト / 分岐** | 自動 rebase 不能。状況を報告して停止 |

提示する内容: 残っている指摘の一覧表 (重大度 / path / 要旨 / 成立確認の結果 / 推奨する disposition とその根拠)。

選択肢は次の 4 つ。**「続行してラウンド上限を上げる」は置かない** (上限は 5 から 8、10、12 と上げられてきた。上げても 1 パス 1〜2 件の検出は変わらない):

1. **指定した指摘だけ直して終了する**: 名指しされた指摘を手順 3〜7 で処理し、push 前ローカルレビューを通して 1 回 push する。head に対するレビューを 1 回だけ待ち、それでも指摘が出たらこの画面に戻る (ラウンド上限の引き上げではなく、名指しの指摘に対する 1 回の作業)
2. **指定した指摘の残存リスクを受け入れて終了する**: 受け入れた指摘ごとに理由を返信に残し、`disposition = "accepted-risk"` で台帳に記録する。issue 化は追跡のためであって、受け入れの代わりにはならない
3. **変更を revert または分割する**: 修正の連鎖が止まらない不変条件を、別 PR に切り出す
4. **人手レビューに引き渡す**: 現状で停止し、残指摘の一覧を PR 本文に載せる

`loop_status = "escalated"` を保存し、`/dev review <slug>` で再開可能にする。

---

## セッション保存

`~/.claude/dev-sessions/<slug>.json` に `review` オブジェクトを持たせる (スキーマ詳細は [session-management.md](session-management.md))。

```json
"review": {
  "loop_status": "monitoring",          // monitoring|ci-fixing|responding|approved|converged|review-incomplete|timeout|escalated|null
  "rounds": 0,                          // 受信した Codex レビューの数 (計測用)
  "push_rounds": 0,                     // 指摘対応で push した回数 (予算の対象。CI 修正だけの push は含めない)
  "max_push_rounds": 3,
  "ci_fix_rounds": 0,
  "local_review_passes": 0,             // Phase 5 と 5.5 で掛けたローカルレビューのパス数
  "head_local_review": "clean",         // clean|unreviewed|skipped|cloud-first|cloud-reviewed
  "codex_review_requested": false,      // この PR で @codex review を投げたか (1 PR 1 回)
  "last_push_at": "2026-05-30T01:00:00Z",
  "last_push_commit": "abc1234...",
  "wait_started_at": "2026-05-30T01:00:00Z", // 最後に実際に push した時刻 (コミット時刻ではない)。待機時間と relay モードのタイマーの基準
  "processed_review_ids": [],           // triage した review の id。--processed-reviews に渡し、ポーリングの対象から除く
  "processed_comment_ids": [],
  "rebutted_comment_ids": [],
  "findings": [
    {"id": 3939237807, "round": 1, "severity": "P2", "path": "app/lib/x.server.ts",
     "title": "非配列 JSON をイベントタグとして数えない",
     "validity": "valid", "disposition": "fixed",
     "evidence": "実 DB で quest_tags_json='\"天元\"' の行を用意し、修正前は件数 1、修正後は 0 を確認",
     "repair": null, "sha": "57880204", "issue_url": null}
  ],
  "total_wait_seconds": 0,
  "escalate_after_seconds": 2400,
  "started_at": "2026-05-30T01:00:00Z",
  "approved_at": null,
  "terminal_reason": null,              // approved|converged|review-incomplete|ci-only|escalated
  "timeout_reason": null                // review-incomplete の種別 (usage-limit|error|no-head-review) か自由記述
}
```

- `severity`: triage 後の重大度 (バッジから上げ下げしたら元のバッジを `evidence` に書く)
- `validity`: `valid` (成立を確認) / `excessive` (成立するが振る舞いに影響しない) / `wrong` (成立しない)
- `disposition`: `fixed` / `rebutted` / `followup` / `reply-only` / `accepted-risk` / `pending`
- 中断 (セッション切れ等) しても、`processed_*_ids` と `last_push_at` と `findings[]` から **冪等に再開**できる (再 `/dev review <slug>` で続行)

---

## 計測

終了報告と `findings[]` から後で集計できるように、次を必ず残す: `terminal_reason`、`rounds` と `push_rounds`、`local_review_passes`、`findings[]` の重大度 / 妥当性 / disposition / round、PR open から終端までの時間。

見る指標は 3 つ。

1. PR ごとの「最初のレビューから全指摘の disposition 完了まで」の時間 (ローカルレビュー、クラウドの待ち、人の介入を含む) の中央値と p90
2. fix push 1 回あたりの、直前の fix に起因する指摘の数 (同じ不変条件に 2 回目の指摘が出た件数は別に数える)
3. 終了後に見つかった妥当な P1/P2 の数 (マージ後の指摘、障害、後続 PR での発見。REVIEW_INCOMPLETE と accepted-risk の PR も母数に含める)

GitHub 上のラウンド数は 1 の内訳として見る。ラウンドが減っても 1 が減らなければ、手元に移しただけである。

---

## 禁止事項

- **👍 が付くまで push を続けない**。終端は APPROVED / CONVERGED / REVIEW_INCOMPLETE のいずれかで、いずれも CI 全成功を伴う。APPROVED と CONVERGED は head レビューの確認も伴い、REVIEW_INCOMPLETE は head が未レビューであることを記録して報告する。CI 緑だけでも終了しない (Codex 設定済みリポジトリではレビューの完了を待つ)
- **返信だけのラウンドで `@codex review` を投げない**。同じ commit が再レビューされ、前のパスで出なかった指摘が出る。`@codex review` は push 後に自動レビューが来ないときの 1 PR 1 回のフォールバック
- **成立を確認せずに fix にしない / 提案コードをそのまま貼らない**。指摘は問題の記述として読み、不変条件から変更を決める。同根の箇所は同じ commit で直す
- **push 前ローカルレビューを、修正の検証以外に広げない**。既定は focus 付き 1 パス。変更全体の再発見はクラウドの「徹底的なコードレビュー」に任せる (ローカル 1 パスは週間利用枠の 0.5〜1%)。1 行の機械的修正だけの push には掛けない。CLI 不在やタイムアウトで掛けられなかったときは理由を記録して続行する
- **利用上限コメントを無視して待ち続けない**。`usage_limited` は REVIEW_INCOMPLETE の終端。approved と報告しない
- **max_push_rounds をエスカレーションの中で引き上げない**。選択肢は名指しの指摘の処理、残存リスクの受け入れ、revert / 分割、人手レビューの 4 つ
- **P1 の fix を再現テストなしで push しない**。Codex は fix の有効性を見ない
- **CI 失敗を `gh run rerun` の連打で握りつぶさない**。rerun は flaky 切り分けとして 1 回のみ。2 回連続で落ちたら実問題として修正する
- **CI 修正とレビュー対応を別々に push しない**。同時に溜まっているなら 1 push にまとめる
- **「+1 が存在する」で approved 判定しない** (baseline-diff 必須)。必ず `last_push_at` より新しい +1 だけをシグナルにする
- **commit_id の完全一致を待たない** (Codex は中間コミットをスキップ、最終コミットは +1 のみ)。`last_push_at` 以降の 👍 と、未処理の review で判定する
- **1 ラウンドで複数 push しない** (中間コミットがスキップされ追跡が壊れる)
- **outdated コメント (`line==null`) を機械的に fix しない** (対象行が消えている)
- **返信本文を `--body-file`/`--input` 以外で渡さない** (shell 展開事故)。`mktemp` 動的パス + `head` 検証必須
- **PR 本文を更新せずに push だけで終えない** (Phase 5-bis ルール、Test plan を落とさない)
- **`--watch` を前景 Bash で起動しない** (sleep がブロックされる。`run_in_background` 必須)
- **relay モードで Codex を自分で待たない** (deny を受けた後も同じ。[待ち方](#relay-モード))
- **MERGED / CLOSED の PR で監視を始めない** (Phase 6 へ誘導)
- **push しないラウンドで baseline を進めない**。`review.last_push_at` は push のときだけ動かし、同じ review の再返却は `--processed-reviews` で止める ([手順 8](#8-台帳と-baseline-の更新))
- **`waiting` 時に `eyes_present` を無視して即 `@codex review` しない**。eyes が残っている間はレビュー進行中なので待機する (二重トリガー防止)
