#!/usr/bin/env bash
# copy-diff.sh — ブランチで足した「人に見せる日本語」を抜き出す (ui-copy-ja skill の部品)。
#
#   copy-diff.sh list  [base] [head] 足した日本語の行を「ファイル: 文」で出す (点検の入力、PR 本文用)
#   copy-diff.sh check [base] [head] 点検が要らない / 済んでいれば 0、未点検なら 1、判定できなければ 3
#   copy-diff.sh mark  [base] [head] いまの一覧を点検済みとして記録する (一覧が変わると無効になる)
#
# base を省くか - にすると、既定のブランチ (origin/HEAD、無ければ main / master) を使う。
# head を省くと HEAD を使う。チェックアウトしていないブランチを調べるときに指定する。
#
# 対象: base との merge-base から head までに足した行のうち、ひらがな・カタカナを含む行。
#       コミット済みの行だけを見る。未コミットの変更は一覧に出ない。
#       かなで判定するので、中国語・韓国語の訳は拾わない。
# 除外: Markdown、docs/、エージェント用の設定、テスト、スナップショット、コメントだけの行。
#       コメントかどうか決められない行 (JSX の本文が * や # で始まる場合など) は、一覧に残す。
set -u
mode=${1:-list}
base=${2:-}
head=${3:-HEAD}
[ "$base" = "-" ] && base=""

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
git rev-parse -q --verify "$head^{commit}" >/dev/null 2>&1 || exit 3
mb=$(git merge-base "$base" "$head" 2>/dev/null) || exit 3

extract() {
  git -c core.quotePath=false diff --no-ext-diff --no-textconv --no-color --src-prefix=a/ --dst-prefix=b/ -U0 "$mb" "$head" -- . \
    ':(exclude,glob)**/*.md' ':(exclude,glob)**/*.mdx' ':(exclude,glob)docs/**' \
    ':(exclude,glob).claude/**' ':(exclude,glob).agents/**' ':(exclude,glob).github/**' \
    ':(exclude,glob)**/__tests__/**' ':(exclude,glob)**/*.test.*' ':(exclude,glob)**/*.spec.*' \
    ':(exclude,glob)e2e/**' ':(exclude,glob)**/*.snap' ':(exclude,glob)**/fixtures/**' \
    ':(exclude,glob)seeds/**' ':(exclude,glob)scripts/**' 2>/dev/null \
  | COPY_DIFF_HEAD="$head" perl -CSD -Mutf8 -ne '
      # "#" で始まる行をコメントと見なすのは、"#" がコメントになる種類のファイルだけ。
      sub hash_lang {
        return $_[0] =~ m{(?:^|/)(?:Dockerfile[^/]*|Makefile|Gemfile|Rakefile|\.env[^/]*|\.gitignore)$
                          |\.(?:sh|bash|zsh|fish|py|rb|pl|pm|ya?ml|toml|ini|cfg|conf|properties|tf|hcl|r|jl|exs?|nix|mk|cmake|ps1|graphqls?|gql|php)$}xi;
      }
      # YAML では、ブロックスカラー (key: | や key: > の本文) の中の "#" は文字列なので、コメントと見なさない。
      sub in_yaml_block {
        my ($file, $n) = @_;
        unless ($yscan{$file}) {
          my (%c, $i);
          my $ind = -1;
          if (open(my $fh, "-|", "git", "show", "$ENV{COPY_DIFF_HEAD}:$file")) {
            while (my $l = <$fh>) {
              $i++;
              if ($ind >= 0) {
                if ($l =~ /^\s*$/) { $c{$i} = 1; next }
                $l =~ /^( *)/;
                if (length($1) > $ind) { $c{$i} = 1; next }
                $ind = -1;
              }
              $ind = length($1) if $l =~ /^( *)(?:- +)*(?:[^\#\s][^\#]*:|-)\s*[|>][+-]?\d*[+-]?\s*(?:\#.*)?$/;
            }
            close $fh;
          }
          $yscan{$file} = \%c;
        }
        return $yscan{$file}{$n};
      }
      # "*" で始まる行をコメントと見なすのは、head のファイルでブロックコメントの中にある行だけ。
      # JSX の本文が "*" で始まる場合 (必須項目の注記など) は、一覧に残る。
      sub in_block {
        my ($file, $n) = @_;
        unless ($scan{$file}) {
          my (%c, $in, $i);
          if (open(my $fh, "-|", "git", "show", "$ENV{COPY_DIFF_HEAD}:$file")) {
            while (my $l = <$fh>) {
              $i++;
              if ($in) { $c{$i} = 1; $in = 0 if $l =~ m{\*/} }
              elsif ($l =~ m{(?:^|[\s\{(,;])/\*(.*)$}) { $in = 1 unless $1 =~ m{\*/} }
            }
            close $fh;
          }
          $scan{$file} = \%c;
        }
        return $scan{$file}{$n};
      }
      if (m{^\+\+\+ "?b/(.*?)"?\s*$}) { $f = $1; next }
      if (m{^@@ -\S+ \+(\d+)}) { $ln = $1; next }
      next unless /^\+/ && !/^\+\+\+/;
      my $n = $ln++;
      s/^\+\s*//; s/\s+$//;
      next unless /[\x{3041}-\x{3096}\x{30A1}-\x{30FA}]/;
      next if m{^(//|/\*|<!--|\{/\*)};
      next if /^#/ && hash_lang($f) && !($f =~ /\.ya?ml$/i && in_yaml_block($f, $n));
      next if /^\*/ && in_block($f, $n);
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
  *)     echo "usage: copy-diff.sh list|check|mark [base] [head]" >&2; exit 2 ;;
esac
