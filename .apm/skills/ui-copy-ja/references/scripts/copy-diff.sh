#!/usr/bin/env bash
# copy-diff.sh — ブランチで足した「人に見せる日本語」を抜き出す (ui-copy-ja skill の部品)。
#
#   copy-diff.sh list  [base]   足した日本語の行を「ファイル: 文」で出す (点検の入力、PR 本文用)
#   copy-diff.sh check [base]   点検が要らない / 済んでいれば 0、未点検なら 1、判定できなければ 3
#   copy-diff.sh mark  [base]   いまの一覧を点検済みとして記録する (一覧が変わると無効になる)
#
# 対象: base との merge-base から HEAD までに足した行のうち、ひらがな・カタカナを含む行。
#       コミット済みの行だけを見る。未コミットの変更は一覧に出ない。
#       かなで判定するので、中国語・韓国語の訳は拾わない。
# 除外: Markdown、docs/、エージェント用の設定、テスト、スナップショット、コメントだけの行。
set -u
mode=${1:-list}
base=${2:-}

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 3
cd "$root" || exit 3

if [ -z "$base" ]; then
  base=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$base" ]; then
    for b in origin/main origin/master main master; do
      if git rev-parse -q --verify "$b" >/dev/null 2>&1; then base=$b; break; fi
    done
  fi
fi
[ -n "$base" ] || exit 3
mb=$(git merge-base "$base" HEAD 2>/dev/null) || exit 3

extract() {
  git -c core.quotePath=false diff --no-color -U0 "$mb" HEAD -- . \
    ':(exclude,glob)**/*.md' ':(exclude,glob)**/*.mdx' ':(exclude,glob)docs/**' \
    ':(exclude,glob).claude/**' ':(exclude,glob).agents/**' ':(exclude,glob).github/**' \
    ':(exclude,glob)**/__tests__/**' ':(exclude,glob)**/*.test.*' ':(exclude,glob)**/*.spec.*' \
    ':(exclude,glob)e2e/**' ':(exclude,glob)**/*.snap' ':(exclude,glob)**/fixtures/**' \
    ':(exclude,glob)seeds/**' ':(exclude,glob)scripts/**' 2>/dev/null \
  | perl -CSD -Mutf8 -ne '
      if (m{^\+\+\+ "?b/(.*?)"?\s*$}) { $f = $1; next }
      next unless /^\+/ && !/^\+\+\+/;
      s/^\+\s*//; s/\s+$//;
      next if m{^(//|#|\*|/\*|<!--|\{/\*)};      # コメントだけの行
      next unless /[\x{3041}-\x{3096}\x{30A1}-\x{30FA}]/;   # かなを含む行だけ
      print "$f: $_\n";
    '
}

cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-copy-check"
list=$(extract)
hash=$(printf '%s' "$list" | shasum -a 256 | cut -c1-32)

case "$mode" in
  list)  [ -n "$list" ] && printf '%s\n' "$list"; exit 0 ;;
  check) [ -z "$list" ] && exit 0; [ -f "$cache/$hash" ] && exit 0; exit 1 ;;
  mark)  mkdir -p "$cache" && : > "$cache/$hash" && echo "点検済みとして記録しました"; exit 0 ;;
  *)     echo "usage: copy-diff.sh list|check|mark [base]" >&2; exit 2 ;;
esac
