#!/usr/bin/env bash
# copy-guard.sh — PR を出すとき、足した「人に見せる日本語」の点検を担保する (PreToolUse hook)。
#
# 対象: Bash の gh pr (create|ready)、mcp__github__create_pull_request。
# 動き: この hook と同じディレクトリの copy-diff.sh check を、そのセッションの cwd で実行する。
#       コマンドが cd してから gh を呼ぶ形なら、cd した先で実行する。
#       PR の base (--base、gh-merge-base 設定) が既定のブランチと違えば、その base との差分を見る。
#       --head でチェックアウト中とは別のブランチを指していれば、そのブランチを調べる。
#       gh pr ready に番号、URL、ブランチを付けた形では、その PR の head と base を調べる。
#       足した日本語が無い、または点検済み (mark 済み) なら素通し。未点検なら deny して手順を返す。
#       git リポジトリでない、base が決まらないなど判定できないときは素通し (止めすぎない)。
# 登録: settings.json の PreToolUse に、このファイルのパスを直接指定する (SKILL.md を参照)。
#       copy-diff.sh を自分の場所から探すので、別の場所へコピーしない。jq が要る。
# 限界: コマンドの文字列を近似的に読むだけで、シェルとして解釈はしない。sudo や eval、エイリアス、
#       スクリプトの中からの実行、gh の -R / --repo で別のリポジトリを指す形は対象にならない。
#       gh pr ready --undo=false のように値を付けた形は、--undo と同じく対象にならない。
#       フォークのブランチ (--head owner:branch) は、owner と同じ名前のリモートを取得済みのときだけ調べられる。
input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
cmd=""
base=""
head=""
sel=""
sub=""
oid=""
targets=""
helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/copy-diff.sh"

case "$tool_name" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
    # gh pr create / ready が、コマンドとして実行される位置にあるときだけ対象にする。
    # 引用符の中や heredoc の本文に同じ文字列があるだけのコマンド (git commit -m '...' など) は通す。
    # --help / -h を付けたコマンドは、ヘルプを表示するだけなので、対象にしない。
    # gh pr ready --undo は Draft に戻す操作なので、対象にしない。同じコマンドに続きがあれば、最初の対象外でないものを見る。
    # かっこで囲んだ中 (サブシェルやコマンド置換) で閉じている cd は、外の行き先に数えない。
    # 行末の \ で次の行に続けたコマンドは、1 行につないでから読む。
    # 引用符の中身は 1 つの引数として扱い、その後ろのオプション (--base など) も読む。
    # 二重引用符の中にコマンド置換 ($(...) やバッククォート) があれば、外側に見つからないときに中も見る。
    # 見つかれば 1 行目に hit、2 行目に --base の値、3 行目に --head の値、4 行目に ready の対象 (無ければ空)、5 行目に create か ready か、6 行目以降に、それより前の cd の行き先を順に出す。
    parsed=$(printf '%s' "$cmd" | perl -0777 -ne '
      my (@q, @inner);
      s/\\\n//g;
      s/<<-?[ \t]*(["\x27]?)(\w+)\1[^\n]*\n.*?\n[ \t]*\2[ \t]*(?=\n|\z)//gs;
      s/"((?:[^"\\]|\\.)*)"|\x27([^\x27]*)\x27/my ($dq, $sq) = ($1, $2); push @q, defined $dq ? $dq : $sq; push @inner, [$#q, $dq] if defined $dq && $dq =~ m{\$\(|`}; "\x01$#q\x01"/ge;
      my $re = qr/(?:^|[;&|(\{\n`])[ \t]*(?:\w+=\S*[ \t]+)*gh[ \t]+pr[ \t]+(create|ready)\b([^;&|\n)`]*)/;
      my ($pre, $sub, $rest);
      for my $c ([undef, $_], @inner) {
        my ($i, $txt) = @$c;
        while ($txt =~ /$re/g) {
          next if $1 eq "ready" && $2 =~ /(?:^|\s)--undo\b/;
          next if $2 =~ /(?:^|\s)(?:--help|-h)(?:\s|$)/;
          ($pre, $sub, $rest) = (substr($txt, 0, $-[0]), $1, $2);
          $pre = substr($_, 0, index($_, "\x01$i\x01")) . " " . $pre if defined $i;
          last;
        }
        last if defined $sub;
      }
      exit unless defined $sub;
      1 while $pre =~ s/\$?\([^()]*\)//;
      my $base = $rest =~ /(?:--base|-B)(?:[ \t]+|=)(\S+)/ ? $1 : "";
      my $head = $rest =~ /(?:--head|-H)(?:[ \t]+|=)(\S+)/ ? $1 : "";
      my $sel = ($sub eq "ready" && $rest =~ /^[ \t]+([^-\s]\S*)/) ? $1 : "";
      my @d;
      while ($pre =~ /(?:^|[;&|(\s])cd\s+([^\s;&|)]+)/g) { push @d, $1 }
      for ($base, $head, $sel, @d) { s/\x01(\d+)\x01/$q[$1]/g }
      print join("\n", "hit", $base, $head, $sel, $sub, @d);
    ' 2>/dev/null)
    [ -n "$parsed" ] || exit 0
    base=$(printf '%s\n' "$parsed" | sed -n 2p)
    head=$(printf '%s\n' "$parsed" | sed -n 3p)
    sel=$(printf '%s\n' "$parsed" | sed -n 4p)
    sub=$(printf '%s\n' "$parsed" | sed -n 5p)
    targets=$(printf '%s\n' "$parsed" | tail -n +6)
    ;;
  mcp__github__create_pull_request)
    base=$(printf '%s' "$input" | jq -r '.tool_input.base // ""' 2>/dev/null)
    head=$(printf '%s' "$input" | jq -r '.tool_input.head // ""' 2>/dev/null)
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
# gh pr ready では、対象の PR の head と base を gh に問い合わせる。
# 対象は、番号、URL、ブランチの指定があればその PR、無ければ今のブランチの PR。
# PR の先頭のコミットが手元にあれば、そのコミットを調べる。無ければ、owner:branch として下の手順で探す。
# 問い合わせに失敗したとき、ブランチ名ならそのブランチを、番号と URL なら HEAD を調べる。
if [ "$sub" = ready ]; then
  info=$(gh pr view ${sel:+"$sel"} --json headRefOid,baseRefName,headRepositoryOwner,headRefName \
    -q '.headRefOid + " " + .baseRefName + " " + .headRepositoryOwner.login + ":" + .headRefName' 2>/dev/null)
  if [ -n "$info" ]; then
    oid=${info%% *}
    info=${info#* }
    base=${info%% *}
    head=${info#* }
  else
    case "$sel" in
      http://*|https://*) ;;
      *[!0-9]*) head=$sel ;;
    esac
  fi
fi
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
# --head でチェックアウト中とは別のブランチを指しているときは、そのブランチを調べる。
# PR に入るのはリモートのブランチなので、origin のものを先に見る。
# owner:branch の形では、owner と同じ名前のリモートがあればそのブランチを見る。
# 無ければ、origin の URL が owner のものであるときに限り origin を見る。
# どこにも見つからないときは、HEAD を調べる。
if [ -n "$oid" ] && git cat-file -e "$oid^{commit}" 2>/dev/null; then
  head=$oid
elif [ -n "$head" ]; then
  owner=""
  case "$head" in *:*) owner=${head%%:*}; head=${head##*:} ;; esac
  use_origin=1
  if [ -n "$owner" ]; then
    case "$(git remote get-url origin 2>/dev/null)" in *[:/]"$owner"/*) ;; *) use_origin=0 ;; esac
  fi
  if [ -n "$owner" ] && git rev-parse -q --verify "refs/remotes/$owner/$head" >/dev/null 2>&1; then head="$owner/$head"
  elif [ "$use_origin" = 1 ] && git rev-parse -q --verify "refs/remotes/origin/$head" >/dev/null 2>&1; then head="origin/$head"
  elif git rev-parse -q --verify "refs/heads/$head" >/dev/null 2>&1; then :
  else head=""
  fi
fi
if [ -n "$head" ] && [ "$(git rev-parse -q --verify "$head^{commit}" 2>/dev/null)" = "$(git rev-parse -q --verify HEAD 2>/dev/null)" ]; then head=""; fi
if [ -n "$head" ]; then set -- "${base:--}" "$head"
elif [ -n "$base" ]; then set -- "$base"
else set --
fi
bash "$helper" check "$@" >/dev/null 2>&1
[ $? -eq 1 ] || exit 0

basearg=${*:+ $*}
n=$(bash "$helper" list "$@" 2>/dev/null | wc -l | tr -d ' ')
REASON="【文言が未点検】このブランチは、人に見せる日本語を ${n} 行足しています。PR を出す前に Skill(ui-copy-ja) の「別の目で点検する」を行ってください: (1) bash \"${helper}\" list${basearg} で一覧を出す → (2) 書いた本人とは別の読み手 (subagent) に一覧を渡して点検させ、指摘を直す → (3) 直した内容をコミットし、bash \"${helper}\" mark${basearg} で点検済みと記録する → (4) PR を出すコマンドをもう一度実行する。一覧がすべて人に見せない文字列 (ログ、テスト用のデータなど) なら、その判断を PR の本文に 1 行書いてから、mark で点検済みと記録してください。"
jq -n --arg r "$REASON" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
