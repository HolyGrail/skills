#!/usr/bin/env bash
# copy-guard.sh — PR を出すとき、足した「人に見せる日本語」の点検を担保する (PreToolUse hook)。
#
# 対象: Bash の gh pr (create|ready)、mcp__github__create_pull_request。
# 動き: この hook と同じディレクトリの copy-diff.sh check を、そのセッションの cwd で実行する。
#       コマンドが cd してから gh を呼ぶ形なら、cd した先で実行する。
#       足した日本語が無い、または点検済み (mark 済み) なら素通し。未点検なら deny して手順を返す。
#       git リポジトリでない、base が決まらないなど判定できないときは素通し (止めすぎない)。
# 登録: settings.json の PreToolUse に、このファイルのパスを直接指定する (SKILL.md を参照)。
#       copy-diff.sh を自分の場所から探すので、別の場所へコピーしない。jq が要る。
input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
cmd=""
helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/copy-diff.sh"

case "$tool_name" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
    printf '%s' "$cmd" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+(create|ready)' || exit 0
    ;;
  mcp__github__create_pull_request) ;;
  *) exit 0 ;;
esac

[ -f "$helper" ] || exit 0
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
# "cd <dir> && gh pr create" の形なら、gh が実際に動くディレクトリを対象にする。
# gh pr より前にある最後の cd を見る。変数を含むなど解決できない行き先は、セッションの cwd のままにする。
if [ -n "$cmd" ]; then
  target=$(printf '%s' "$cmd" | perl -0777 -ne '
    exit unless /^(.*?)gh\s+pr\s+(?:create|ready)/s;
    my ($pre, $d) = ($1);
    while ($pre =~ /(?:^|[;&|(\s])cd\s+(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s;&|)]+))/g) {
      $d = defined $1 ? $1 : defined $2 ? $2 : $3;
    }
    print $d if defined $d;
  ' 2>/dev/null)
  case "$target" in "~"|"~/"*) target="$HOME${target#\~}" ;; esac
  [ -n "$target" ] && cd "$target" 2>/dev/null
fi
bash "$helper" check >/dev/null 2>&1
[ $? -eq 1 ] || exit 0

n=$(bash "$helper" list 2>/dev/null | wc -l | tr -d ' ')
REASON="【文言が未点検】このブランチは、人に見せる日本語を ${n} 行足しています。PR を出す前に Skill(ui-copy-ja) の「別の目で点検する」を行ってください: (1) bash \"${helper}\" list で一覧を出す → (2) 書いた本人とは別の読み手 (subagent) に一覧を渡して点検させ、指摘を直す → (3) 直した内容をコミットし、bash \"${helper}\" mark で点検済みと記録する → (4) PR を出すコマンドをもう一度実行する。一覧がすべて人に見せない文字列 (ログ、テスト用のデータなど) なら、その判断を PR の本文に 1 行書いてから、mark で点検済みと記録してください。"
jq -n --arg r "$REASON" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
