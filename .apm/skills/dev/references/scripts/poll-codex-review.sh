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
# 必ず last_push_iso より「新しい」イベントだけをシグナルとして扱う。
#
# 使い方:
#   poll-codex-review.sh <owner/repo> <pr_number> <last_push_iso> [options]
#     last_push_iso : ISO8601 UTC (例 2026-05-29T15:19:48Z)。これより厳密に新しい Codex
#                     イベントのみシグナル扱い。通常はセッションの review.last_push_at を渡す。
#   options:
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
#                                            # 利用上限コメントを越えても、待機上限での分類に使える
#     "latest_review": {id, commit_id, submitted_at, ...} | null,  # 同以降の最新 codex review
#     "new_comments": [ {id, pull_request_review_id, in_reply_to_id, path, line,
#                        outdated, commit_id, html_url, created_at, body}, ... ],
#     "eyes_present": true|false,            # codex の 👀 が今ついているか (補助情報)
#     "checked_at": "<ISO>"
#   }
# signal 優先順位: approved > new_review > usage_limited > waiting。ただし approved は、baseline 以降の最新 review より後に
# 付いたときだけ (approved の後か同じ秒に review が届いていれば new_review)。
# 終了コード: 0 = 正常 (signal は JSON 参照)、2 = 引数エラー、3 = gh/jq 実行エラー。

set -euo pipefail

BOT="chatgpt-codex-connector[bot]"
INTERVAL=30
MAX_WAIT=540
WATCH=0

usage() {
  sed -n '2,46p' "$0" >&2
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
    -h|--help)  usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
  shift
done

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
  local fresh_reviews latest_review latest_review_at review_ids has_review new_comments signal
  local last_activity_at usage_limit_active_at

  reactions=$(api "repos/$REPO/issues/$PR/reactions") || exit 3
  reviews=$(api "repos/$REPO/pulls/$PR/reviews") || exit 3
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

  # baseline によらない、上限に達したままかの判定。codex の最後の反応 (review / +1 /「Didn't find」) 以降に
  # 利用上限コメントがあれば、上限はまだ戻っていない。GitHub の時刻は秒単位で、上限を使い切ったレビューと
  # 上限コメントは同じ秒になりうるので、同じ秒は上限が残っている側に倒す (外れても待機上限での分類が変わるだけ)
  last_activity_at=$( { printf '%s' "$reviews" | jq -r --arg bot "$BOT" \
                          '[.[] | select(.user.login==$bot and .submitted_at != null) | .submitted_at] | max // ""'
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

  # last_push 以降の codex review 群 (commit 完全一致は要求しない: 中間コミットはスキップされるため)
  fresh_reviews=$(printf '%s' "$reviews" | jq -c --arg bot "$BOT" --arg base "$BASE" \
    '[.[] | select(.user.login==$bot and .submitted_at != null and .submitted_at > $base)]' 2>/dev/null || echo '[]')
  # latest_review は signal 表示 / 参照用。review_ids は comment 回収用 (複数 review の取りこぼし防止)
  latest_review=$(printf '%s' "$fresh_reviews" | jq -c \
    '(max_by(.submitted_at)
      | if . == null then null
        else {id, commit_id, submitted_at, state, html_url: .html_url, body} end)')
  review_ids=$(printf '%s' "$fresh_reviews" | jq -c '[.[].id]')
  latest_review_at=$(printf '%s' "$fresh_reviews" | jq -r 'map(.submitted_at) | max // ""')
  has_review=$(printf '%s' "$review_ids" | jq 'length > 0')

  # baseline 以降の「全」codex review に紐づく inline comments (単一 review に絞ると、
  # baseline 上に未処理 review が 2 件以上あるとき古い方を取りこぼすため全件返す)
  new_comments='[]'
  if [ "$has_review" = "true" ]; then
    comments=$(api "repos/$REPO/pulls/$PR/comments") || exit 3
    new_comments=$(printf '%s' "$comments" | jq -c --arg bot "$BOT" --argjson rids "$review_ids" \
      '[.[] | select(.user.login==$bot and (.pull_request_review_id as $r | ($rids | index($r)) != null))
            | {id, pull_request_review_id, in_reply_to_id, path, line,
               outdated: (.line==null), commit_id, html_url, created_at, body}]')
  fi

  # approved は、その時刻が baseline 以降の最新 review より後のときだけ。approved の後に届いた review
  # (同じ commit の再レビューで指摘が出た場合など) があれば new_review を返す。GitHub の時刻は秒単位なので、
  # 同じ秒なら review を優先する (approved を勝たせると指摘を triage せずに終端へ進む)。時刻は辞書順 = 時刻順
  if [ -n "$approved_at" ] && { [ -z "$latest_review_at" ] || [[ "$latest_review_at" < "$approved_at" ]]; }; then
    signal="approved"
  elif [ "$has_review" = "true" ]; then signal="new_review"
  elif [ -n "$usage_limit_at" ];   then signal="usage_limited"
  else                                  signal="waiting"; fi

  jq -cn \
    --arg signal "$signal" \
    --arg approved_at "$approved_at" \
    --arg usage_limit_at "$usage_limit_at" \
    --arg usage_limit_active_at "$usage_limit_active_at" \
    --argjson latest_review "${latest_review:-null}" \
    --argjson new_comments "$new_comments" \
    --argjson eyes "${eyes:-false}" \
    --arg checked_at "$(now_iso)" \
    '{signal: $signal,
      approved_at: (if $approved_at=="" then null else $approved_at end),
      usage_limit_at: (if $usage_limit_at=="" then null else $usage_limit_at end),
      usage_limit_active_at: (if $usage_limit_active_at=="" then null else $usage_limit_active_at end),
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
