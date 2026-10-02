#!/usr/bin/env bash
#
# poll-codex-review.sh — Codex (chatgpt-codex-connector[bot]) の PR レビュー状態を監視する。
# /dev Phase 5.5 (CI + Review Loop) の監視メカニズム本体。
#
# 観測 (HolyGrail/GBF-community #925 / #812 / #1282 ほか) で確定した Codex の挙動に基づく:
#   - 指摘あり  → pulls/{n}/reviews に review (state=COMMENTED) + pulls/{n}/comments に inline comments
#   - 指摘なし  → issues/{n}/reactions に +1 (👍)。issue comment「Codex Review: Didn't find any major
#                 issues.」が併せて付くこともある。APPROVED state の review は使わない
#   - 利用上限  → issue comment「You have reached your Codex usage limits for code reviews」。
#                 以後レビューは付かない
#   - 👀(eyes)  → レビュー進行中の一時マーカー (完了後は消える。終端判定には使わない)
#   - 再レビュー → push (新コミット) でトリガー。中間コミットはスキップ、最終コミットは +1 のみのことが多い
#
# 重要 (false-approve 防止 / baseline-diff): GitHub は (user, content) で reaction を dedupe するため
# codex の +1 は 1 つしか存在せず created_at が固定されうる。「+1 が存在する」では誤判定するので、
# commit を持たないイベント (+1 /「Didn't find」/ 利用上限コメント) は last_push_iso より「新しい」ものだけを
# シグナルとして扱う。review は時刻で絞らず、--processed-reviews に無いものを未処理として返す
# (baseline を push 以外で動かさずに済み、push の前後にどの順序で届いた review も取りこぼさない)。
#
# 使い方:
#   poll-codex-review.sh <owner/repo> <pr_number> <last_push_iso> [options]
#     last_push_iso : ISO8601 UTC (例 2026-05-29T15:19:48Z)。最後の push のコミット時刻。
#                     これより厳密に新しい +1 / コメントだけをシグナル扱い。セッションの review.last_push_at を渡す。
#   options:
#     --processed-reviews <id,...>  処理済みの codex review の id (カンマ区切り。空でもよい)。
#                        セッションの review.processed_review_ids を渡す。これに無い review が未処理。
#     --limit-head <sha> 利用上限を観測した時点の PR の head。セッションの review.usage_limit_head を渡す (無ければ省く)。
#                        上限コメントより後に届いた review のうち、この commit の祖先 (上限の前の head) を対象とするものを
#                        「上限が戻った」証拠に数えない (上限の前に依頼されて遅れて届いた review を除く)
#     --watch            内部で短間隔ポーリング (変化検知 or タイムアウトで exit)。
#                        ※ run_in_background な Bash で起動すること (前景 sleep は環境で禁止)。
#     --interval <sec>   ポーリング間隔 (default 30)
#     --max-wait <sec>   --watch の最大待機秒 (default 540。前景 Bash の 600s 上限内にも収まる値)
#     --bot <login>      Codex bot のログイン名 (default chatgpt-codex-connector[bot])
#
# 出力 (stdout, 1 行 JSON):
#   {
#     "signal": "approved" | "new_review" | "usage_limited" | "waiting",
#     "approved_at": "<ISO|null>",          # last_push_iso 以降の codex +1 か「Didn't find any major issues」の時刻
#     "usage_limit_at": "<ISO|null>",       # last_push_iso 以降の利用上限コメントの時刻
#     "usage_limit_active_at": "<ISO|null>", # baseline によらず、codex の最後の review / +1 /「Didn't find」以降 (同じ秒を含む) の
#                                            # 利用上限コメントの時刻 (上限がまだ戻っていない)。push で baseline が
#                                            # 利用上限コメントを越えても、待機上限での分類に使える。上限の後の review は
#                                            # --limit-head の祖先を対象とするものを数えない
#     "head_sha": "<sha>",                   # PR の現在の head
#     "head_review": {id, commit_id, submitted_at} | null,  # head を対象とする最新の codex review (処理済みを含む)。
#                                            # null でなければ head はレビュー済み
#     "latest_review": {id, commit_id, submitted_at, ...} | null,  # 未処理の最新 codex review
#     "new_comments": [ {id, pull_request_review_id, in_reply_to_id, path, line,
#                        outdated, commit_id, html_url, created_at, body}, ... ],
#     "eyes_present": true|false,            # codex の 👀 が今ついているか (補助情報)
#     "checked_at": "<ISO>"
#   }
# signal 優先順位: new_review > approved > usage_limited > waiting。usage_limited は baseline 以降の上限コメントが
# まだ有効 (usage_limit_active_at が baseline より新しい) なときだけ (上限の後に届いた review を処理した後は返さない)。未処理の review が 1 件でもあれば、approved との時刻に
# よらず new_review (review を triage してから終端へ進む。baseline は push 以外で動かないので、approved は review を処理済みに
# した後のポーリングで返る)。
# 終了コード: 0 = 正常 (signal は JSON 参照)、2 = 引数エラー、3 = gh/jq 実行エラー。

set -euo pipefail

BOT="chatgpt-codex-connector[bot]"
PROCESSED=""
LIMIT_HEAD=""
INTERVAL=30
MAX_WAIT=540
WATCH=0

usage() {
  sed -n '2,/^$/p' "$0" >&2
  exit 2
}

command -v gh >/dev/null 2>&1 || { echo '{"error":"gh not found"}' >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo '{"error":"jq not found"}' >&2; exit 3; }

[ $# -lt 3 ] && usage
REPO="$1"; PR="$2"; BASE="$3"; shift 3
while [ $# -gt 0 ]; do
  case "$1" in
    --watch)    WATCH=1 ;;
    --interval) INTERVAL="${2:?}"; shift ;;
    --max-wait) MAX_WAIT="${2:?}"; shift ;;
    --bot)      BOT="${2:?}"; shift ;;
    --processed-reviews) PROCESSED="${2?}"; shift ;;
    --limit-head) LIMIT_HEAD="${2?}"; shift ;;
    -h|--help)  usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
  shift
done

# 処理済み review id を JSON 配列に (空文字列なら [])
PROCESSED_JSON=$(jq -nc --arg p "$PROCESSED" '$p | split(",") | map(select(length > 0) | tonumber)' 2>/dev/null) \
  || { echo "invalid --processed-reviews: $PROCESSED" >&2; exit 2; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# gh api の失敗を空の結果と見なさず、終了コード 3 で止める (空と見なすと利用上限や approved を取りこぼして waiting になる)。
# watch ループの result=$(check) の中では errexit が効かないので、呼び出し側は「|| exit 3」で明示的に伝える。
# --paginate はページごとに別の JSON 配列を出すので、1 つの配列にまとめてから返す (まとめないと後段の jq が
# ページごとに走り、時刻や eyes が複数行になって出力の JSON が組み立てられない)
api() {
  local out
  out=$(gh api "$1" --paginate 2>/dev/null) || { printf '{"error":"gh api failed: %s"}\n' "$1" >&2; exit 3; }
  printf '%s' "$out" | jq -cs 'add // []'
}

# 1 ショット判定。stdout に 1 行 JSON を出す。
check() {
  local reactions reviews comments issue_comments reaction_at no_issues_at approved_at usage_limit_at eyes
  local fresh_reviews latest_review review_ids has_review new_comments signal
  local last_activity_at usage_limit_active_at pr head_sha head_review
  local latest_limit_at activity_reviews late_commits post_limit_commits c status

  pr=$(api "repos/$REPO/pulls/$PR") || exit 3
  head_sha=$(printf '%s' "$pr" | jq -r '.head.sha')
  reactions=$(api "repos/$REPO/issues/$PR/reactions") || exit 3
  # 提出済みの codex review だけに絞っておく (以降の判定はすべてこの集合から取る)
  reviews=$(api "repos/$REPO/pulls/$PR/reviews" \
    | jq -c --arg bot "$BOT" '[.[] | select(.user.login==$bot and .submitted_at != null)]') || exit 3
  issue_comments=$(api "repos/$REPO/issues/$PR/comments") || exit 3

  # last_push 以降の codex +1 (approved シグナル)
  reaction_at=$(printf '%s' "$reactions" | jq -r --arg bot "$BOT" --arg base "$BASE" \
    '[.[] | select(.user.login==$bot and .content=="+1" and .created_at > $base)]
     | map(.created_at) | max // ""')

  # last_push 以降の「Didn't find any major issues」コメント (approved の第 2 形態)
  no_issues_at=$(printf '%s' "$issue_comments" | jq -r --arg bot "$BOT" --arg base "$BASE" \
    '[.[] | select(.user.login==$bot and .created_at > $base
                   and (.body | test("Didn'"'"'t find any major issues"; "i")))]
     | map(.created_at) | max // ""')

  # 文字列比較で新しい方を取る。GitHub の created_at は常に "YYYY-MM-DDTHH:MM:SSZ" の UTC なので辞書順 = 時刻順
  approved_at=$(printf '%s\n%s\n' "$reaction_at" "$no_issues_at" | sort | tail -n 1)

  # last_push 以降の利用上限コメント
  usage_limit_at=$(printf '%s' "$issue_comments" | jq -r --arg bot "$BOT" --arg base "$BASE" \
    '[.[] | select(.user.login==$bot and .created_at > $base
                   and (.body | test("reached your Codex usage limits"; "i")))]
     | map(.created_at) | max // ""')

  # head を対象とする最新の codex review (処理済みを含む)。head がレビュー済みかの判定用
  head_review=$(printf '%s' "$reviews" | jq -c --arg head "$head_sha" \
    '[.[] | select(.commit_id==$head)] | max_by(.submitted_at) | if . == null then null else {id, commit_id, submitted_at} end')

  # baseline によらない、上限に達したままかの判定。codex の最後の反応 (review / +1 /「Didn't find」) 以降に
  # 利用上限コメントがあれば、上限はまだ戻っていない。GitHub の時刻は秒単位で、上限を使い切ったレビューと
  # 上限コメントは同じ秒になりうるので、同じ秒は上限が残っている側に倒す (外れても待機上限での分類が変わるだけ)。
  # 上限の前に依頼されて遅れて届いた前の head への review を「戻った」と数えないよう、--limit-head があれば、
  # 最新の上限コメントより後の review のうち、limit-head の祖先 (compare の behind) を対象とするものを数えない。
  # limit-head 自身 (identical)、その後の push (ahead)、rebase 後 (diverged) への review は上限が戻った証拠になる。
  # 上限コメント以前の review は判定に影響しないので、compare はそれより後の review の commit だけに掛ける
  activity_reviews="$reviews"
  if [ -n "$LIMIT_HEAD" ]; then
    latest_limit_at=$(printf '%s' "$issue_comments" | jq -r --arg bot "$BOT" \
      '[.[] | select(.user.login==$bot and (.body | test("reached your Codex usage limits"; "i")))
       | .created_at] | max // ""')
    if [ -n "$latest_limit_at" ]; then
      late_commits=$(printf '%s' "$reviews" | jq -r --arg l "$latest_limit_at" \
        '[.[] | select(.submitted_at > $l) | .commit_id] | unique | .[]')
      post_limit_commits='[]'
      for c in $late_commits; do
        # 404 / 422 (force push で消えた commit や、共通の祖先が無い) は数えない。それ以外の失敗は、
        # 空と見なすと上限が残っていると誤って usage_limited を返しうるので、api() と同じく終了コード 3 で止める
        if ! status=$(gh api "repos/$REPO/compare/$LIMIT_HEAD...$c" --jq '.status' 2>&1); then
          case "$status" in
            *"HTTP 404"*|*"HTTP 422"*) status="" ;;
            *) printf '{"error":"gh api failed: repos/%s/compare/%s...%s"}\n' "$REPO" "$LIMIT_HEAD" "$c" >&2; exit 3 ;;
          esac
        fi
        case "$status" in
          ahead|identical|diverged) post_limit_commits=$(printf '%s' "$post_limit_commits" | jq -c --arg c "$c" '. + [$c]') ;;
        esac
      done
      activity_reviews=$(printf '%s' "$reviews" | jq -c --arg l "$latest_limit_at" --argjson ok "$post_limit_commits" \
        '[.[] | select(.submitted_at <= $l or (.commit_id as $c | $ok | index($c)) != null)]')
    fi
  fi
  last_activity_at=$( { printf '%s' "$activity_reviews" | jq -r 'map(.submitted_at) | max // ""'
                        printf '%s' "$reactions" | jq -r --arg bot "$BOT" \
                          '[.[] | select(.user.login==$bot and .content=="+1") | .created_at] | max // ""'
                        printf '%s' "$issue_comments" | jq -r --arg bot "$BOT" \
                          '[.[] | select(.user.login==$bot and (.body | test("Didn'"'"'t find any major issues"; "i")))
                           | .created_at] | max // ""'; } | sort | tail -n 1)
  usage_limit_active_at=$(printf '%s' "$issue_comments" | jq -r --arg bot "$BOT" --arg after "$last_activity_at" \
    '[.[] | select(.user.login==$bot and .created_at >= $after
                   and (.body | test("reached your Codex usage limits"; "i")))]
     | map(.created_at) | max // ""')

  # codex の 👀 が今あるか (補助。終端判定には使わない)
  eyes=$(printf '%s' "$reactions" | jq --arg bot "$BOT" \
    '[.[] | select(.user.login==$bot and .content=="eyes")] | length > 0')

  # 未処理の codex review 群。時刻では絞らない (push 直前のポーリングの後、push までに届いた review も返す)。
  # commit 完全一致も要求しない (中間コミットはスキップされ、前の head への review にも今の head に残る指摘がありうる)
  fresh_reviews=$(printf '%s' "$reviews" | jq -c --argjson done "$PROCESSED_JSON" \
    '[.[] | select((.id as $i | $done | index($i)) == null)]')
  # latest_review は signal 表示 / 参照用。review_ids は comment 回収用 (複数 review の取りこぼし防止)
  latest_review=$(printf '%s' "$fresh_reviews" | jq -c \
    '(max_by(.submitted_at)
      | if . == null then null
        else {id, commit_id, submitted_at, state, html_url: .html_url, body} end)')
  review_ids=$(printf '%s' "$fresh_reviews" | jq -c '[.[].id]')
  has_review=$(printf '%s' "$review_ids" | jq 'length > 0')

  # 未処理の「全」codex review に紐づく inline comments (単一 review に絞ると、
  # 未処理 review が 2 件以上あるとき古い方を取りこぼすため全件返す)
  new_comments='[]'
  if [ "$has_review" = "true" ]; then
    comments=$(api "repos/$REPO/pulls/$PR/comments") || exit 3
    new_comments=$(printf '%s' "$comments" | jq -c --arg bot "$BOT" --argjson rids "$review_ids" \
      '[.[] | select(.user.login==$bot and (.pull_request_review_id as $r | ($rids | index($r)) != null))
            | {id, pull_request_review_id, in_reply_to_id, path, line,
               outdated: (.line==null), commit_id, html_url, created_at, body}]')
  fi

  # 未処理の review があれば、approved より先に new_review を返す (approved の後か同じ秒に届いた review も、
  # approved より前に届いて未処理の review も、指摘を triage せずに終端へ進まない)。approved は baseline より
  # 新しい限り返り続けるので、review を処理済みにした後のポーリングで返る
  if [ "$has_review" = "true" ];   then signal="new_review"
  elif [ -n "$approved_at" ];      then signal="approved"
  elif [ -n "$usage_limit_active_at" ] && [[ "$BASE" < "$usage_limit_active_at" ]]; then signal="usage_limited"
  else                                  signal="waiting"; fi

  jq -cn \
    --arg signal "$signal" \
    --arg approved_at "$approved_at" \
    --arg usage_limit_at "$usage_limit_at" \
    --arg usage_limit_active_at "$usage_limit_active_at" \
    --arg head_sha "$head_sha" \
    --argjson head_review "${head_review:-null}" \
    --argjson latest_review "${latest_review:-null}" \
    --argjson new_comments "$new_comments" \
    --argjson eyes "${eyes:-false}" \
    --arg checked_at "$(now_iso)" \
    '{signal: $signal,
      approved_at: (if $approved_at=="" then null else $approved_at end),
      usage_limit_at: (if $usage_limit_at=="" then null else $usage_limit_at end),
      usage_limit_active_at: (if $usage_limit_active_at=="" then null else $usage_limit_active_at end),
      head_sha: $head_sha,
      head_review: $head_review,
      latest_review: $latest_review,
      new_comments: $new_comments,
      eyes_present: $eyes,
      checked_at: $checked_at}'
}

if [ "$WATCH" -eq 0 ]; then
  check
  exit 0
fi

# --watch: 変化検知 or 内部タイムアウトまでポーリング。前景 sleep が禁止の環境では
# run_in_background な Bash で起動すること (この while ループごと background プロセスになる)。
deadline=$(( $(date +%s) + MAX_WAIT ))
while :; do
  result=$(check) || exit 3
  sig=$(printf '%s' "$result" | jq -r '.signal')
  if [ "$sig" != "waiting" ]; then printf '%s\n' "$result"; exit 0; fi
  remaining=$(( deadline - $(date +%s) ))
  if [ "$remaining" -le 0 ]; then printf '%s\n' "$result"; exit 0; fi
  [ "$remaining" -lt "$INTERVAL" ] && INTERVAL="$remaining"
  sleep "$INTERVAL"
done
