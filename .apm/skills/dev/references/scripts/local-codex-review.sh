#!/usr/bin/env bash
#
# local-codex-review.sh — codex review CLI をプロンプトモードで呼び、BASE から作業ツリーまでの変更 (未コミットの fix を含む) を
# AGENTS.md の Code review 基準でレビューする。--focus が無ければ変更全体を網羅的に、あれば focus の対象と影響先だけを見る。
# /dev Phase 5 (PR 作成前) と Phase 5.5 (push 前) のローカルレビューに使う。
#
# 背景 (2026-09-07 に HolyGrail/GBF-community #1361 の修正前 head で観測):
#   - codex review の --commit / --base は [PROMPT] と併用できない (引数エラーになる)。
#     レビュー範囲はプロンプトの中で git diff の範囲として指定する
#   - 既定の呼び出し (--commit) は、クラウドの Codex が P2 を付けた変更に 2 回とも「不具合なし」を返した。
#     「新しい P1/P2 が見つからなくなるまで探し続ける」と指示したプロンプトモードでは、
#     同じ変更に P2 を 2〜3 件返した (パスごとに見つかる集合は変わる。1 パスで全部出る保証はない)
#   - AGENTS.md の Code review 節は読み込まれ、指摘に [AGENTS.md:L68] のような引用が付く
#   - 1 パスの所要時間は 4〜6 分 (テストの実行や実 DB での再現を含む)。合計 100〜120 万トークン (9 割はキャッシュ入力) で、
#     週間利用枠の 0.5〜1% を消費する (~/.codex/sessions の rate_limits で観測)。クラウドのレビューと同じメーターに載る
#
# 使い方:
#   local-codex-review.sh <worktree_path> <base_ref> [options]
#     base_ref : 比較元 (origin/main など)。merge-base を取り、そこから作業ツリーまでをレビューする
#   options:
#     --focus "<観点>"   直前の fix で変えた振る舞いとその影響先。指定するとレビュー範囲をこれに限り、
#                        変更全体の探し直しはしない (Phase 5 の 2 パス目と Phase 5.5 の push 前に使う)
#     --timeout <sec>    既定 900
#     --log <path>       生ログの保存先 (既定: mktemp)
#     --bot-note         出力の先頭に「ローカルレビュー」である旨の 1 行を付ける
#
# 出力: codex の最終メッセージ (findings 一覧) を stdout に。
# 終了コード: 0 = 完了 (指摘の有無は本文を読む)、2 = 引数エラー、3 = 実行エラー / タイムアウト、4 = 差分なし

set -euo pipefail

TIMEOUT=900
FOCUS=""
LOG=""
NOTE=0

usage() {
  sed -n '2,28p' "$0" >&2
  exit 2
}

[ $# -lt 2 ] && usage
WT="$1"; BASE_REF="$2"; shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --focus)   FOCUS="${2:?}"; shift ;;
    --timeout) TIMEOUT="${2:?}"; shift ;;
    --log)     LOG="${2:?}"; shift ;;
    --bot-note) NOTE=1 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
  shift
done

command -v codex >/dev/null 2>&1 || { echo "codex CLI not found" >&2; exit 3; }
[ -d "$WT/.git" ] || [ -f "$WT/.git" ] || { echo "not a git worktree: $WT" >&2; exit 2; }

cd "$WT"
BASE_SHA=$(git merge-base "$BASE_REF" HEAD) || { echo "merge-base failed for $BASE_REF" >&2; exit 3; }
HEAD_SHA=$(git rev-parse HEAD)
# push 前の fix はコミット前に掛けるので、HEAD ではなく作業ツリー (未追跡ファイルを含む) と比べる
if git diff --quiet "$BASE_SHA" && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "no changes between $BASE_SHA and the working tree" >&2
  exit 4
fi

[ -n "$LOG" ] || LOG=$(mktemp -t local-codex-review.XXXXXX)

SCOPE="Review the changes between commit $BASE_SHA and the current working tree (HEAD is $HEAD_SHA; uncommitted changes are part of the change set). Run: git diff $BASE_SHA and git status --short (for new untracked files) to see the full change set, and read the surrounding code and callers as needed.
Apply the 'Code review' / 'Code Review Rules' section of AGENTS.md (root and nested) as the review criteria."
REPORT="Verify findings against real behavior where it matters (run only the tests related to the changed files, reproduce with real data or the real database); do not run the whole test suite.
Keep searching within that scope until you find no new P1 or P2 findings.
Then list every P1/P2 finding with severity tag, file and line, the triggering condition, and the concrete consequence. Do not report P3 or style-only items."
if [ -z "$FOCUS" ]; then
  # 全体レビュー (Phase 5 の 1 パス目): 変更全体を網羅的に探す
  PROMPT="$SCOPE
Be exhaustive across the whole change set. When you find one instance of a defect pattern, inspect every other occurrence and affected consumer in the change set and report them together.
$REPORT"
else
  # 限定レビュー (Phase 5 の 2 パス目、Phase 5.5 の push 前): focus の対象と影響先だけを見る。
  # 変更全体の探し直しはクラウドのレビューに任せ、時間と利用枠を focus の検証に使う
  PROMPT="$SCOPE
Limit this review to: $FOCUS. Check whether that change restores the intended behavior and whether it breaks its affected code (callers, consumers, and other occurrences of the same pattern). Do not search the rest of the change set for unrelated defects.
$REPORT"
fi

# perl の alarm でタイムアウトを掛ける (macOS 標準には timeout(1) が無い)。SIGALRM で終了すると exit 142
set +e
perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" \
  codex review -c 'approval_policy="never"' "$PROMPT" > "$LOG" 2>&1
rc=$?
set -e

if [ "$rc" -eq 142 ]; then
  echo "codex review timed out after ${TIMEOUT}s (log: $LOG)" >&2
  exit 3
fi
if [ "$rc" -ne 0 ]; then
  echo "codex review exited with $rc (log: $LOG)" >&2
  tail -n 20 "$LOG" >&2
  exit 3
fi

# CLI は思考・ツール実行のストリームの後に、行が "codex" だけのマーカーに続けて最終メッセージを出す。
# 最後のマーカー以降だけを取り出し、同じ最終メッセージが続けて 2 回出力される場合 (0.153 で観測) は
# 先頭行が再び現れた位置で打ち切って 1 回分にする
[ "$NOTE" -eq 1 ] && echo "[local codex review] base=$BASE_SHA head=$HEAD_SHA log=$LOG"
# マーカーが無い、または最終メッセージが空なら、出力形式が変わったとみなして実行エラーにする
# (空の stdout で exit 0 すると、呼び出し側が「指摘なし」と読み違える)
FINAL=$(awk '/^codex$/{buf=""; p=1; next} p{buf=buf $0 "\n"} END{printf "%s", buf}' "$LOG" \
  | awk 'NR==1{first=$0} NR>1 && $0==first && first!="" {exit} {print}')
if [ -z "$(printf '%s' "$FINAL" | tr -d '[:space:]')" ]; then
  echo "no final review message found in codex output (log: $LOG)" >&2
  exit 3
fi
printf '%s\n' "$FINAL"
