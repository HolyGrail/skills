---
name: release
description: |
  PR をマージした後の「リリース作業」を、プロジェクト種別の判定からバージョン更新、提出物一覧の提示、リリースノート案、タグと GitHub Release の作成まで進めるワークフロー。manifest.json / tauri.conf.json / CMakeLists.txt + buildspec.json / *.xcodeproj / release-please-config.json から Chrome 拡張・Tauri・OBS プラグイン・iOS・release-please 運用を見分け、種別ごとのバージョン更新箇所と提出物を提示する。既定は「提出物一覧を先に提示し、ユーザーが提出する」流れで、ストア提出と Apple の署名・公証・TestFlight 操作は人間が行う。「リリースして」「バージョン上げて」「ストアに出す内容物」「マージしたのでリリース作業を行いたい」と言われたときに使う。PR 作成は pr-create、マージ後の掃除は /dev cleanup が担い、本 skill はマージ後から公開までだけを扱う。
compatibility: Requires git and gh CLI. Chrome 拡張では zip、iOS では Xcode の agvtool (xcrun 経由) を使う。ストアの管理画面や App Store Connect、コード署名の鍵には触らない。
---

# Release

PR をマージしたあと、変更が利用者の手元に届くまでの作業を担う。対象はバージョン番号の更新、ストアや配布先に出す提出物の一覧化、リリースノート案、タグと GitHub Release の作成まで。**ストアの管理画面に入って提出する操作と、Apple の署名、公証、TestFlight の配信操作は人間が行う**。本 skill はその手前までを揃え、提出に必要なものを一覧で渡す。

## 使い方

```bash
/release                       # マージ済みの main から次のリリースを進める
/release 1.4.0                 # バージョンを指定して進める
/release --list                # 提出物一覧と現在のバージョンだけ提示し、変更は加えない
/release --notes               # リリースノート案だけ作る (タグも Release も作らない)
```

- 引数なし: 直近のタグと `main` の差分からリリースの要否と次のバージョンを提案し、提出物一覧を提示してから更新に入る
- バージョン指定: semver の判断を省き、指定値で更新箇所を書き換える
- `--list`: 「ストアに登録する内容物一覧を提示してください」への応答。ファイルは変更しない
- `--notes`: リリースノートの下書きだけが欲しいとき

## 境界

| 段階 | 担当 |
|---|---|
| 変更の実装、PR 作成 | `/dev`、`/pr-create` |
| PR のマージ | 人間 |
| **バージョン更新、提出物の一覧化、リリースノート案、タグ、GitHub Release** | **本 skill** |
| ストア提出、署名と公証、TestFlight 配信、審査対応 | 人間 |
| マージ後の worktree とブランチの掃除 | `/dev cleanup` |

リリースの途中で実装の修正が必要になったら、本 skill の中で直さない。修正は通常の開発フローに戻し、PR をマージしてから再開する。

## Phase 1: プロジェクト種別の判定

リポジトリ root で次のファイルを探し、最初に当たった行で種別を決める。複数に当たる場合 (Tauri の中に package.json があるなど) は上の行を優先する。

| 判定ファイル | 種別 | 配布先 |
|---|---|---|
| `release-please-config.json` または `.release-please-manifest.json` | release-please 運用 | release-please が作る release PR |
| `CMakeLists.txt` と `buildspec.json` の両方 | OBS プラグイン | GitHub Release (CI が成果物を作る) |
| `src-tauri/tauri.conf.json` (または `tauri.conf.json`) | Tauri 2 | GitHub Release、Windows は msi / setup exe |
| `*.xcodeproj` (`find . -maxdepth 2 -name '*.xcodeproj'`) | iOS | TestFlight → App Store |
| `manifest.json` に `"manifest_version": 3` | Chrome 拡張 (MV3) | Chrome Web Store |

どれにも当たらなければ、既存のタグ (`git tag --sort=-v:refname | head`) と直近の GitHub Release (`gh release list --limit 5`) から運用を推定し、推定であることを明示してユーザーに確認する。

判定と同時に次も控える。

- 直近のタグとタグの書式 (`v1.2.3` か `1.2.3` か)
- 直近のタグ以降にマージされた PR (`gh pr list --state merged --base main --search "merged:>=YYYY-MM-DD"`)
- 現在のバージョン値 (Phase 2 の更新箇所から読む)
- リリース手順を定めたファイル (`RELEASING.md`、`docs/release.md`、`mise.toml` の `release:*` タスク、`.github/workflows/release*.yml`)。あればそちらを正とし、本 skill の既定手順より優先する

## Phase 2: バージョン更新

次のバージョンは直近タグ以降の PR から semver で提案する (破壊的変更 → major、機能追加 → minor、修正のみ → patch)。ユーザーが値を指定していればそれを使う。

種別ごとの更新箇所は次の表の通り。一箇所でも更新し忘れると、ストアに出る値とタグの値がずれて、どちらが本当のリリースか追えなくなる。表の全列を同じ値にする。

| 種別 | 更新箇所 | 備考 |
|---|---|---|
| Chrome 拡張 | `manifest.json` の `version`、`package.json` の `version` | `version` は数字とドットだけ、4 区切りまで。プレリリース接尾辞は不可 |
| Tauri 2 | `src-tauri/tauri.conf.json` の `version`、`src-tauri/Cargo.toml` の `[package] version`、`package.json` の `version` | `Cargo.lock` は `cargo update -p <crate名> --precise` か build で追従させる |
| OBS プラグイン | `CMakeLists.txt` の `project(<name> VERSION x.y.z)`、`buildspec.json` の `version` | CI の成果物名にこの値が入る |
| iOS | `MARKETING_VERSION` (表示バージョン)、`CURRENT_PROJECT_VERSION` (ビルド番号) | 下記の通り pbxproj を Edit ツールで触らない |
| release-please | 触らない | release-please が release PR で `version` と CHANGELOG を書き換える |

### iOS のバージョン更新

`project.pbxproj` は Edit / Write ツールで書き換えない。Xcode が生成するファイルで、同じ設定行がターゲットと構成の数だけ繰り返されるため、一部だけ書き換えるとターゲット間で値が食い違い、構文を崩せば Xcode で開けなくなる。更新は次のどちらかで行う。

```bash
# 1. agvtool (Versioning System が Apple Generic のとき)
xcrun agvtool new-marketing-version 1.4.0      # MARKETING_VERSION
xcrun agvtool new-version -all 42              # CURRENT_PROJECT_VERSION

# 2. Bash の確定的置換 (agvtool が使えないとき)。置換前後で件数が一致することを確認する
PBX=$(find . -maxdepth 2 -name '*.xcodeproj' | head -1)/project.pbxproj
grep -c 'MARKETING_VERSION = 1.3.0;' "$PBX"
sed -i '' 's/MARKETING_VERSION = 1.3.0;/MARKETING_VERSION = 1.4.0;/g' "$PBX"
grep -c 'MARKETING_VERSION = 1.4.0;' "$PBX"
```

置換後に `git diff --stat` で変更が pbxproj の該当行だけに収まっているかを見る。`CURRENT_PROJECT_VERSION` は TestFlight に同じ値を二度アップロードできないので、前回のビルド番号より大きくする。

### 更新をどこに積むか

マージ済みの PR にバージョン更新が含まれていれば、この Phase は読むだけで終わる。含まれていなければ、リリース用ブランチ (`release/1.4.0`) で更新し、`/pr-create` で PR を出してマージを待つ。`main` へ直接 push するのは、ユーザーがそう指示し、ブランチ保護がそれを許すときだけにする。

release-please 運用では、ここまでの作業をすべて release-please に任せる。本 skill の仕事は、release PR が開いているかを `gh pr list --label "autorelease: pending"` で確認し、その本文 (CHANGELOG 案) を読み上げて、マージの判断材料にすることまでになる。Conventional Commits に沿わないコミットが混ざってバージョンが上がらないときは、その旨と原因のコミットを示す。

## Phase 3: 提出物一覧の提示 (既定の流れ)

**まず一覧を提示し、提出はユーザーが行う**。一覧には「ファイルの場所」「作り方」「まだ無いもの」を分けて書く。無いものを先回りして作らず、作るかどうかを一覧の中で問う。

### Chrome Web Store

| 提出物 | 要件 | 作り方 / 置き場所 |
|---|---|---|
| 拡張の zip | `manifest.json` が zip のルート直下。`node_modules`、ソースマップ、`.git` を含めない | `npm run build` 後に `cd dist && zip -r ../release/<name>-<version>.zip .`。zip の中身を `unzip -l` で確認する |
| 説明文 (日本語・英語) | 概要は 132 字以内、詳細説明は 16,000 字以内。ストアの言語ごとに入力する | `store/description.ja.md`、`store/description.en.md` があればそれを更新、無ければ README から下書きを作る |
| スクリーンショット | 1280×800 または 640×400、1〜5 枚、JPEG か 24-bit PNG (アルファ無し) | `store/screenshots/` を探す。無ければ撮影が必要と記す |
| 小型プロモーションタイル | 440×280、JPEG か 24-bit PNG | `store/promo-440x280.png`。無ければ「任意だが掲載面が増える」と記す |
| プライバシー項目 | 単一目的の説明、要求する権限ごとの使用理由、リモートコードの有無、ユーザーデータの扱い (収集の有無と用途)、プライバシーポリシー URL | `manifest.json` の `permissions` / `host_permissions` を列挙し、権限ごとに 1 行の理由案を書く。ポリシー URL は既存の掲載値を `store/` か README から探す |
| 変更点 | ストアには欄が無いが、審査コメントと GitHub Release に使う | Phase 4 のリリースノート案 |

提出先は Chrome Web Store Developer Dashboard。zip のアップロード、各欄の入力、審査への提出はユーザーが行う。審査で権限の理由を問われることが多いので、権限ごとの理由案は省かない。

### Tauri 2 (Windows 配布)

- `npm run tauri build` (または `cargo tauri build`) の成果物: `src-tauri/target/release/bundle/msi/*.msi`、`bundle/nsis/*-setup.exe`
- 成果物のファイル名にバージョンが入るので、Phase 2 のあとに build する
- 配布は GitHub Release の assets。updater を使っていれば `latest.json` も assets に含める。`createUpdaterArtifacts` が作るのはインストーラと `.sig` の署名ファイルまでで、`latest.json` は作らない。CI で tauri-action を使っていればそれが生成する。手元で build したときは、version、platform ごとのダウンロード URL、`.sig` の中身を組み合わせて自分で書き、assets に添付する
- macOS の dmg、署名、公証はこの skill では扱わない。準備中のプロジェクトでは「macOS 向け成果物は未対応」と一覧に明記する

### OBS プラグイン

- CI (`.github/workflows/`) がタグ push で各 OS の成果物 (`.zip` / `.pkg` / `.deb`) を作り、GitHub Release に添付する構成が多い。まず workflow の trigger を読み、CI が作るなら手元では build しない
- 本 skill の仕事は Phase 2 の更新とタグ push、Release の本文整備。CI 完了後に `gh release view <tag>` で assets の有無を確認する
- OBS 側のプラグイン一覧 (obsproject.com の resources) への登録・更新は人間が行う

### iOS

- `mise run release:upload` のようなタスクがあればそれを使い、無ければ `xcodebuild archive` → `xcodebuild -exportArchive` の手順を一覧に書く。実行前に、署名に Apple ID やチームの資格情報が要るかを確認し、要るならユーザーに実行を委ねる
- TestFlight への配信、テスター追加、App Store 審査への提出、What's New の入力は人間が行う。本 skill はその What's New の下書き (日英) を Phase 4 で作る
- 提出物: アーカイブ (`.xcarchive`)、`ExportOptions.plist`、スクリーンショット (App Store Connect が要求するサイズはデバイスごとに異なるので、既存の掲載から流用できるものと撮り直しが要るものを分ける)

### release-please

提出物は無い。release PR の本文を提示し、マージすると release-please が tag と GitHub Release を作ることを伝える。Phase 4 は release-please の生成結果を確認するだけになる。

## Phase 4: リリースノート、タグ、GitHub Release

### リリース対象のコミットを確定する

タグもノートも build も、同じ 1 つのコミットを指すようにする。`/release` を動かしている worktree の HEAD は、マージ直前の feature ブランチや release ブランチであることが多く、そこにタグを打つと squash マージ後の `main` と中身がずれる。先に `main` を取り直し、その SHA を以後のすべてで使う。

```bash
git fetch origin main
REL=$(git rev-parse origin/main)
git log -1 --oneline "$REL"             # バージョン更新 PR のマージコミットであることを目で確認
```

`REL` がバージョン更新 PR のマージコミットでなければ (別の PR が先に入っている、まだマージされていない)、その旨を報告して止まる。

### リリースノート案

直近タグ以降のマージ済み PR を集め、利用者に見える変更を先に、内部変更を後に並べる。言語は既存の Release に揃える (無ければ日本語)。

対象の PR はコミットの範囲 (直近タグから `main` まで) で決める。マージ日時による検索は、前回タグと同じ日にマージされた PR を二重に拾うので、範囲の外の候補を探すときにだけ使う。

```bash
PREV=$(git describe --tags --abbrev=0)
# 直近タグ以降の first-parent コミットから PR 番号を取る (squash / merge commit の件名に #番号 が入る)
git log --first-parent --format=%s "$PREV".."$REL" | grep -oE '#[0-9]+' | sort -u
# 番号ごとに題名とラベルを取る
gh pr view 123 --json number,title,labels,url
```

件名に PR 番号が無いコミットが混ざるときは、`gh pr list --state merged --base main --search "merged:>=<直近タグの日時 ISO 8601>"` を候補一覧として使い、`git merge-base --is-ancestor <マージコミット> "$PREV"` で前回タグに含まれるものを除いてから採用する。

ノートは `mktemp` で取ったファイルに書き、投稿の直前に中身を確認する。固定名の `/tmp/notes.md` を使うと、別セッションが残した古い本文をそのまま投稿しかねない。

```bash
NOTES=$(mktemp -t release-notes.XXXXXX)
# ... $NOTES に本文を書く ...
head -c 300 "$NOTES"      # 意図した本文か目で確認
```

### タグと Release

タグの書式は Phase 1 で控えた既存のものに揃える。Release は draft で作り、assets が揃ったのを確認してから公開する。immutable releases を有効にしたリポジトリでは公開後に assets を足せないので、先に公開すると成果物の無い Release が残る。

```bash
git tag v1.4.0 "$REL" && git push origin v1.4.0     # タグは REL に打つ。HEAD には打たない
gh release create v1.4.0 --draft --title "v1.4.0" --notes-file "$NOTES"
rm -f "$NOTES"
# ... assets を添付し、gh release view v1.4.0 で確認してから ...
gh release edit v1.4.0 --draft=false
```

- CI がタグ push で成果物を作る構成 (OBS、Tauri の一部) では、まず workflow が Release 自体を作るかを読む。作るなら `git tag v1.4.0 "$REL" && git push origin v1.4.0` でタグだけ push して CI に任せ、CI が公開まで行うか draft で止まるかに従う。作らない (既存 Release に upload するだけ) なら、タグを push したあと `gh release create v1.4.0 --draft` で draft を作り、CI の upload が終わって `gh release view v1.4.0` で assets を確認してから `--draft=false` にする。draft の Release を先に作ってもタグは push されず CI は動かないので、タグ push を省かない
- 成果物を手元で作る構成 (Tauri を手動 build) では、`gh release create ... --draft` で作り、`gh release upload v1.4.0 <files>` で添付してから `gh release edit v1.4.0 --draft=false` で公開する
- ストア配布が主の種別 (Chrome 拡張、iOS) では、GitHub Release は履歴の記録として作る。ストアの審査が通るまで公開したくなければ `--draft` のままにし、その旨を報告に含める
- release-please 運用では作らない。`gh release list --limit 3` で生成結果を確認する

### 完了報告

次を 1 つのブロックで返す。

- バージョン: 旧 → 新、更新したファイル
- タグと Release の URL (作った場合)
- 提出物一覧 (場所、未作成のもの)
- ユーザーがこれから行う操作 (ストア提出、署名、TestFlight 配信)

## 注意事項

- **提出は人間が行う**：ストアの管理画面、App Store Connect、署名鍵、公証の資格情報には触らない。ブラウザを操作して提出することもしない
- **一覧を先に出す**：ファイルの更新や zip の作成より前に、何を出すかの一覧を提示する。一覧の時点でユーザーが止められるようにする
- **バージョンは全箇所を同時に**：種別の表にある更新箇所を一度に書き換え、`grep -rn "<旧バージョン>"` で取り残しが無いかを見る
- **pbxproj を Edit しない**：iOS のバージョンは agvtool か Bash の確定的置換で更新し、置換前後の件数を確認する
- **タグは `origin/main` の SHA に打つ**：worktree の HEAD に打たない。`git fetch origin main` で取り直した SHA をタグ、ノートの範囲、build のすべてに使う
- **タグは打ち直さない**：公開済みタグの付け替え (`git tag -f` + force push) はしない。間違えたら次のバージョンで直す
- **リリース手順書を優先する**：リポジトリに手順書や release タスクがあれば、本 skill の既定手順よりそちらに従う
- **`--notes-file` は mktemp と head 確認**：固定名の一時ファイルを使わず、投稿直前に中身を確認する

## 実行例

```
# Chrome 拡張: マージ後に提出物を確認してから進める
/release --list

# 期待される動作
# Phase 1: manifest.json (manifest_version 3) を検出 → Chrome 拡張、直近タグ v1.3.0
# Phase 3: zip / 説明文 (ja, en) / スクリーンショット / 440×280 タイル / プライバシー項目 を
#          「ある・更新が要る・無い」に分けて一覧提示。permissions ごとの理由案を添える
#          → ここで停止 (--list)

/release 1.4.0

# 期待される動作
# Phase 2: manifest.json と package.json の version を 1.4.0 に更新
#          → release/1.4.0 ブランチで /pr-create → マージ待ち
# Phase 3: npm run build → dist/ を zip 化、unzip -l で中身を確認
# Phase 4: リリースノート案 → gh release create v1.4.0 --draft
#          → 完了報告: zip の場所、入力する説明文、ユーザーが行うストア提出の手順

# OBS プラグイン: CI が成果物を作る
/release 0.3.0

# Phase 2: CMakeLists.txt の project VERSION と buildspec.json を 0.3.0 に
# Phase 4: git fetch origin main で REL を確定 → git tag 0.3.0 "$REL" && git push origin 0.3.0 で CI を起動
#          → workflow が Release を作らなければ draft を作る
#          → CI 完了後に assets を確認してから draft を外す
```

## 関連スキル

- `/pr-create` : バージョン更新 PR の作成
- `/dev cleanup` : マージ後の worktree とブランチの掃除 (本 skill の前後どちらでもよい)
- `/semantic-commit` : バージョン更新と他の変更が混ざったときの分割
