#!/usr/bin/env bash
# copy-guard.sh — PR を出すとき、足した「人に見せる日本語」の点検を担保する (PreToolUse hook)。
#
# 対象: Bash の gh pr (create|ready)、mcp__github__create_pull_request。
# 動き: この hook と同じディレクトリの copy-diff.sh check を、そのセッションの cwd で実行する。
#       コマンドが cd してから gh を呼ぶ形なら、cd した先で実行する。
#       PR の base (--base、gh-merge-base 設定) が既定のブランチと違えば、その base との差分を見る。
#       足した日本語が無い、または点検済み (mark 済み) なら素通し。未点検なら deny して手順を返す。
#       git リポジトリでない、base が決まらないなど判定できないときは素通し (止めすぎない)。
# 登録: settings.json の PreToolUse に、このファイルのパスを直接指定する (SKILL.md を参照)。
#       copy-diff.sh を自分の場所から探すので、別の場所へコピーしない。jq が要る。
# 限界: コマンドの文字列を近似的に読むだけで、シェルとして解釈はしない。sudo や eval、エイリアス、
#       スクリプトの中からの実行、gh の -R / --repo で別のリポジトリを指す形は対象にならない。
input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
cmd=""
base=""
targets=""
helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/copy-diff.sh"

case "$tool_name" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
    # gh pr create / ready が、コマンドとして実行される位置にあるときだけ対象にする。
    # 引用符の中や heredoc の本文に同じ文字列があるだけのコマンド (git commit -m '...' など) は通す。
    # 二重引用符の中でも、コマンド置換 ($(...) やバッククォート) を含むものは中を見る。
    # 見つかれば 1 行目に hit、2 行目に --base の値 (無ければ空)、3 行目以降に、それより前の cd の行き先を順に出す。
    parsed=$(printf '%s' "$cmd" | perl -0777 -ne '
      my @q;
      s/<<-?[ \t]*(["\x27]?)(\w+)\1[^\n]*\n.*?\n[ \t]*\2[ \t]*(?=\n|\z)//gs;
      s/"((?:[^"\\]|\\.)*)"|\x27([^\x27]*)\x27/my ($dq, $sq) = ($1, $2); if (defined $dq && $dq =~ m{\$\(|`}) { " $dq " } else { push @q, defined $dq ? $dq : $sq; "\x01$#q\x01" }/ge;
      exit unless /^(.*?)(?:^|[;&|(\{\n`])[ \t]*(?:\w+=\S*[ \t]+)*gh[ \t]+pr[ \t]+(?:create|ready)\b([^;&|\n)`]*)/s;
      my ($pre, $rest) = ($1, $2);
      my $base = $rest =~ /(?:--base|-B)(?:[ \t]+|=)(\S+)/ ? $1 : "";
      my @d;
      while ($pre =~ /(?:^|[;&|(\s])cd\s+([^\s;&|)]+)/g) { push @d, $1 }
      for ($base, @d) { s/\x01(\d+)\x01/$q[$1]/g }
      print join("\n", "hit", $base, @d);
    ' 2>/dev/null)
    [ -n "$parsed" ] || exit 0
    base=$(printf '%s\n' "$parsed" | sed -n 2p)
    targets=$(printf '%s\n' "$parsed" | tail -n +3)
    ;;
  mcp__github__create_pull_request)
    base=$(printf '%s' "$input" | jq -r '.tool_input.base // ""' 2>/dev/null)
    ;;
  *) exit 0 ;;
esac

[ -f "$helper" ] || exit 0
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
# "cd <dir> && gh pr create" の形なら、gh が実際に動くディレクトリを対象にする。
# cd が続くときは順にたどる。変数を含むなど解決できない行き先は飛ばす。
while IFS= read -r t; do
  [ -n "$t" ] || continue
  case "$t" in "~"|"~/"*) t="$HOME${t#\~}" ;; esac
  cd "$t" 2>/dev/null
done <<EOF
$targets
EOF
# PR の base を、--base、ブランチの gh-merge-base 設定の順で決める。どちらも無ければ helper の既定に任せる。
if [ -z "$base" ]; then
  cur=$(git branch --show-current 2>/dev/null)
  [ -n "$cur" ] && base=$(git config --get "branch.$cur.gh-merge-base" 2>/dev/null)
fi
if [ -n "$base" ]; then
  if git rev-parse -q --verify "origin/$base" >/dev/null 2>&1; then base="origin/$base"
  elif ! git rev-parse -q --verify "$base" >/dev/null 2>&1; then base=""
  fi
fi
bash "$helper" check ${base:+"$base"} >/dev/null 2>&1
[ $? -eq 1 ] || exit 0

basearg=${base:+ $base}
n=$(bash "$helper" list ${base:+"$base"} 2>/dev/null | wc -l | tr -d ' ')
REASON="【文言が未点検】このブランチは、人に見せる日本語を ${n} 行足しています。PR を出す前に Skill(ui-copy-ja) の「別の目で点検する」を行ってください: (1) bash \"${helper}\" list${basearg} で一覧を出す → (2) 書いた本人とは別の読み手 (subagent) に一覧を渡して点検させ、指摘を直す → (3) 直した内容をコミットし、bash \"${helper}\" mark${basearg} で点検済みと記録する → (4) PR を出すコマンドをもう一度実行する。一覧がすべて人に見せない文字列 (ログ、テスト用のデータなど) なら、その判断を PR の本文に 1 行書いてから、mark で点検済みと記録してください。"
jq -n --arg r "$REASON" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
