---
name: archive-deliverables
description: |
  リポジトリにコミットしたくない成果物 (マーケティング素材の動画・画像・投稿文、コンテや引き継ぎ文、撮影用のデータ、ビルド物、レポート) を、クラウド同期フォルダの `<ルート>/<リポジトリ名>/<種別>/<日付>-<スラッグ>/` に final / brief / work の 3 区分と README 台帳付きで保存する。振り分け表の提示、rsync によるコピー、台帳の生成 (commit SHA、再生成手順、素材の出どころ、配布上の注意、sha256)、両側の照合までを行い、リポジトリ側の削除は同期完了を確認してもらってから行う。「成果物を保存して」「コミットしたくないファイルを退避して」「素材をアーカイブして」と言われたとき、または動画や画像などの素材が仕上がって手元に残っているときに使う。
compatibility: Requires git, rsync, shasum。保存先は Dropbox や iCloud Drive などの同期クライアントがローカルに持つフォルダで、クラウド側の API は使わない。
---

# Archive Deliverables

動画や画像、投稿文のようなマーケティング素材は、リポジトリに入れると履歴が膨らむ一方で、捨てると撮り直しも再編集もできなくなる。本 skill はそれを同期フォルダの決まった場所へ、あとから再生成できる情報と一緒に写す。コミットの代わりに台帳 (README.md) が「いつ、どの commit から、何で作ったか」を持つ。

## 使い方

```bash
/archive-deliverables assets/promo                                   # 対象ディレクトリを指定 (種別とスラッグは対話で決める)
/archive-deliverables assets/promo --kind marketing --slug spring-campaign
/archive-deliverables dist --kind dist --slug v1.4.0                 # ビルド物も同じ形で保存できる
```

- 対象はディレクトリ 1 つ。複数の場所に散っているときは、先に 1 つのディレクトリへ集めてから呼ぶ
- `--kind` は `marketing` / `dist` / `reports` のどれか。それ以外が要るときは本人に確認する
- `--slug` は英小文字とハイフンの 2〜4 語。案件が分かる名前にし、日付は入れない (束の名前に自動で付く)

## 保存先の規則

```
$DELIVERABLE_ARCHIVE_ROOT/          # 同期フォルダの中の 1 か所。例: ~/Dropbox/development
  <repo>/                           # git remote origin の basename (無ければ作業ディレクトリ名)
    <kind>/                         # marketing / dist / reports
      <YYYY-MM-DD>-<slug>/          # 1 案件 1 束。日付は保存した日
        README.md                   # 台帳
        CHECKSUMS.txt               # 全ファイルの sha256
        final/                      # 配布するもの
        brief/                      # 指示書と判断の記録
        work/                       # 再生成に要るもの
```

- ルートは環境変数 `DELIVERABLE_ARCHIVE_ROOT` で決める。未設定なら、`~/Dropbox`、`~/Library/CloudStorage/`、`~/Library/Mobile Documents/` (iCloud Drive)、`~/Google Drive` のうち存在するものを候補に挙げて本人に聞き、以後も使うなら `~/.claude/settings.json` の `env` に入れるよう勧める。推測で決めない
- 案件ごとに束ねる。動画・画像・投稿文・撮影用のデータは互いに依存していて、種類別に分けると「どのデータでどのキャプチャを撮ったか」が切れる
- `<repo>/dist/` のような日付なしの既存フォルダがあれば、以前の置き方として残す。改名も移動もしない。同じリポジトリで `--kind dist` を使うと、その中に日付付きの束が並ぶ
- 同じ日に同じスラッグがすでにあるときは、上書きせず本人に聞く (別スラッグにするか、既存の束を更新するか)
- ファイル名はリポジトリにあったものをそのまま使う。中の文書が互いをファイル名で参照しているので、改名すると参照が切れる

## 3 区分の振り分け

| 区分 | 入れるもの | 判定の目安 |
| --- | --- | --- |
| `final/` | そのまま配信・配布するもの | `*.mp4` `*.mov` `*.gif` (作業フォルダの外にあるもの)、`images/` の `*.png` `*.jpg` `*.webp`、投稿文・告知文の `*.md` (ファイル名に caption / announcement / tweet / post を含む) |
| `brief/` | 指示書と判断の記録 | コンテ、引き継ぎ文、撮影用の SQL やフィクスチャ、仕様からの変更点、推敲の中間版。final に入らない `*.md` と `*.sql` |
| `work/` | 再生成に要るもの | 動画エディタのプロジェクト (`*.motion/` `*.prproj` など)、`captures/`、`stills/`、`*-stills/`、`bgm/`、`*.wav`、ビルドスクリプト (`build*.mjs` など)、`project.json` |
| 除外 | 写さないもの | `.DS_Store`、`node_modules/`、`*.tmp`、`*.log`、`.env` と `.env.*`、`.dev.vars` と `.dev.vars.*`、鍵や API キーを含むファイル |

迷うものは `work/` に入れる。final は「公開する」の意味を持つので、公開してよいか分からないものを入れない。

## 手順

### 1. 振り分け表を出す

対象を走査し、ファイルごとに区分と保存先の相対パスを表にして見せる。コピーの前に本人の目を通す。

```bash
SRC="$PWD/assets/promo"                            # 対象
REPO_DIR="$(git rev-parse --show-toplevel)"        # 元リポジトリ。あとの手順は cd で場所が変わるので、ここで控える
ROOT="$DELIVERABLE_ARCHIVE_ROOT"
REPO="$(basename -s .git "$(git remote get-url origin 2>/dev/null || basename "$PWD")")"
KIND=marketing; SLUG=spring-campaign
B="$ROOT/$REPO/$KIND/$(date +%F)-$SLUG"
test -n "$ROOT" -a -d "$ROOT" || { echo "DELIVERABLE_ARCHIVE_ROOT が未設定か、存在しない: $ROOT"; exit 1; }
test -e "$B" && { echo "同名の束がある: $B"; exit 1; }
find "$SRC" -type l | sort                                   # symlink があれば、ここで止まって本人に聞く
find "$SRC" -type f ! -name .DS_Store ! -path '*/node_modules/*' ! -name '*.tmp' ! -name '*.log' ! -name '.env' ! -name '.env.*' ! -name '.dev.vars' ! -name '.dev.vars.*' | sort
```

この一覧をタブ区切りの対応表 `MAP` (元の絶対パス、区分、束の中の相対パス) にして保存する。手順 2 のコピーと手順 4 の照合はこの表だけを見る。`find` の除外に漏れた秘密のファイルが表に残っていれば、ここで取り除く。

symlink が 1 つでもあれば、コピーに進まない。リンク先の実体を対象の中に写して置き換えるか、除外するかを本人に聞き、決まってから表を作り直す。`-type f` の一覧には symlink が出ないので、この確認を飛ばすと気づかないまま写される。

表の形:

| リポジトリのパス | 区分 | 束の中のパス | サイズ |
| --- | --- | --- | --- |

振り分けはこの skill の規則で仮決めし、表の下に「変えたいものがあれば区分を指定してください」と添える。本人の返事がない自律実行では規則どおりに進め、変えた点を報告に残す。

### 2. コピーする

対応表 `MAP` の行ごとに `rsync` で 1 ファイルずつ写す。フォルダをまとめて `-r` で写すと、振り分け表に出なかった `.env` や `node_modules/` も一緒に入るので、フォルダ単位のコピーはしない。

```bash
mkdir -p "$B/final" "$B/brief" "$B/work"
while IFS=$'\t' read -r src kind dst; do
  mkdir -p "$B/$(dirname "$dst")"
  rsync -t --checksum "$src" "$B/$dst" || { echo "失敗: $src"; exit 1; }
done < "$MAP"
```

- `-a` ではなく `-t` を使う。同期フォルダに owner / group / 特殊パーミッションを持ち込まず、symlink も写さない (`-l` を付けると symlink が symlink のまま入り、元を消した時点でリンク先を失う)。手順 1 で symlink を 0 にしてあるので、rsync が "skipping non-regular file" を出したら手順 1 に戻る
- `--checksum` を付け、同名ファイルが残っていても内容で比べる

### 3. 台帳 (README.md) を書く

人が読む日本語なので、置く前に Skill(cognitive-rhythm-writing) で推敲する。表と一覧は対象外、地の文だけが対象。型は「台帳の型」節にある。

埋める値は記憶ではなく、その場のコマンドから取る:

```bash
git rev-parse --short HEAD; git branch --show-current; git rev-parse --show-toplevel
git -C "<素材を作ったツールのリポジトリ>" log --oneline -1   # 動画エディタやビルドツールが git 管理なら、その commit も残す
```

### 4. 照合する

両側の sha256 を突き合わせ、ファイル数と不一致 0 件を確かめる。

```bash
(cd "$B" && find final brief work -type f ! -name .DS_Store -print0 | sort -z | xargs -0 shasum -a 256 > CHECKSUMS.txt)
test -z "$(find "$B" -type l)" || echo "束の中に symlink がある"
# 元のパスと束のパスの対応表 (タブ区切り) を使って元側を計算し、diff で比べる
```

- ファイル名に空白や引用符があっても壊れないよう、`-print0` / `sort -z` / `xargs -0` でつなぐ。並び順は `sort -z` で固定する
- 対応表 `MAP` も同じ理由でタブ区切りにし、読み出しは `while IFS=$'\t' read -r ...` にする。元側の sha256 は `MAP` の行から計算し、束側の `CHECKSUMS.txt` と件数も含めて diff する

照合が通ったら、束の絶対パスと、区分ごとのファイル数・合計サイズを報告する。

### 5. リポジトリ側を消す (本人の確認後)

削除は本人が「消してよい」と言ってから行う。順序は次のとおり。

1. 同期が終わったことを本人に同期クライアントの表示で見てもらう (Dropbox なら Finder のアイコンが緑のチェック)。同期状態を xattr やコマンドで確かに読む方法は見つけていない (未確認)
2. 元リポジトリを基準に `TRACKED="$(git -C "$REPO_DIR" ls-files -- "$SRC")" && test -z "$TRACKED"` が真になることを確かめる。1 行でも出れば tracked のファイルが混ざっているので削除しない。`git status --short` は変更のない tracked ファイルを表示しないため、`??` だけを見ても混在は分からない。また手順 4 のあとは作業ディレクトリが束の側に移っていることがあり、そこで `git ls-files` を実行するとリポジトリ外で exit 128 を返して出力が空になる。空出力だけで判定せず、`git -C "$REPO_DIR"` で元リポジトリを指し、終了コードも見る
3. `rm -rf "$SRC"` を実行し、`git status --short` が空になったことを示す

`.git/info/exclude` に対象を足せば `??` を消せるが、worktree では共通ディレクトリ側に効いて全 worktree で隠れる。既定にはせず、本人が望んだときだけ行う。

## 台帳の型

````markdown
# <案件名>

保存日: <YYYY-MM-DD>。元のリポジトリ: <URL> のブランチ `<branch>` (commit `<sha>`)、作業ディレクトリ `<path>`。

## 何の素材か
<1〜3 文。目的、対象、配信先 (SNS、コミュニティ、ストアなど)。採用が確定したものと別案の区別>

## 再生成の手順
<番号付き。データのリセットと撮影用のデータ、dev server の起動、ビルドスクリプト、使ったツールの場所と commit。コマンドは checkout 先で実行できる形で書く>

## 素材の出どころ
<生成 AI で作ったもの (サービス名、モデル、URL)、システムフォント、ロゴなど>

## 配布上の注意
<公開してよいのは final/ だけ、といった制約。フォントやライセンスの制約があればここ>

## 未決の判断
<この束を作った時点で決まっていないこと。決まったら追記する>

## ファイル一覧
| リポジトリのパス | 束の中のパス | サイズ |
| --- | --- | --- |

sha256 は `CHECKSUMS.txt`。
````

## 注意事項

- **commit しない**。この skill は保存の代わりであって、リポジトリに何も足さない。`.gitignore` も変えない
- **final に入れるものは公開できるものだけ**。本番画面のキャプチャ、実在する人の名前、ライセンスの不明なフォントやロゴが混ざっていれば work に下げ、台帳の「配布上の注意」に書く
- **秘密の値を写さない**。`.env` や API キーを含むファイルは除外し、台帳にも値を書かない
- **再生成に要るものを落とさない**。プロジェクトフォルダに複製されたフォントや、生成 BGM の元 WAV は work に残す。これが無いと再編集できない
- **削除は最後、確認のあと**。コピーの照合が通っても、同期が終わる前にリポジトリ側を消さない
- **ディスク容量の対策にはならない**。同期フォルダも同じディスクにある。手元を空けたいときは同期クライアントの「オンラインのみ」に相当する設定を使う

## 関連スキル

- `handoff-prompt`: 制作を別セッションに渡すときの引き継ぎ文。引き継ぎ文も brief に入れる
- `release`: ビルド物の提出。提出物を `--kind dist` で保存すると同じ束の形になる
