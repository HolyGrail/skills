---
name: x-research
description: >-
  X (Twitter) 上の実データ調査を grok build CLI (`grok -p`) に委譲する。X 上の反応・トレンド・
  特定アカウントの発言・スレッド本文・投稿の伸び (いいね/RT/表示数) を知りたいとき、x.com /
  twitter.com の URL の中身を読みたいとき、「X で何が言われているか」「X で話題か」を
  問われたときに使う。Claude Code 内蔵の WebSearch / WebFetch は X のログイン壁で本文も
  エンゲージメント数も取得できないため、X が絡む調査は必ずこれを使う。
---

# X 調査を grok build に委譲する

## なぜ grok か

grok CLI は X ネイティブの検索ツールを内蔵している。

| ツール | 用途 |
| --- | --- |
| `x_keyword_search` | キーワード・期間・エンゲージメント閾値での検索 |
| `x_semantic_search` | 意味検索（言い回しが定まらない話題を拾う） |
| `x_user_search` | アカウント特定・プロフィール |
| `x_thread_fetch` | 投稿 URL からスレッド本文を取得 |

これらは投稿本文・いいね/RT/引用/ブックマーク/表示数・投稿日時を実データで返す。
Claude Code 側の WebSearch は X をインデックス断片でしか拾えず、WebFetch は x.com で弾かれる。

## 起動

```bash
grok -p '<下記のプロンプト型>' --max-turns 12 --yolo --output-format json --no-auto-update | jq -r '.text'
```

- **Bash tool の `timeout` は 300000 以上**を指定する。デフォルト 120 秒では足りない。
- `--cwd` は指定しないか、プロジェクト外の一時ディレクトリを指す。git リポジトリ内で起動すると
  grok がそのリポジトリを project root として走査し、起動が遅くなる。
- 実測: 1 クエリあたり **40〜90 秒 / $0.13〜0.35**。安くはないので、複数の問いは 1 回の
  プロンプトにまとめる。

## プロンプトの型

先頭に必ずこのヘッダを置く。これが無いと grok は web_search 経由の遠回りを始め、所要時間が
倍以上・コストが 2〜3 倍になる。

```
x_keyword_search / x_semantic_search / x_user_search / x_thread_fetch ツールを使って
X を直接検索してください。シェル (run_terminal_command) は使用禁止です。

調査内容: <本文>
```

本文には必ず含める:

- **期間** — 「直近3日」「2026-07-20 以降」など。省くと古い投稿が混ざる
- **出力項目** — 「投稿者ハンドル / 投稿URL / 日付 / エンゲージメント / 要約」など表形式で指定
- **件数の上限**
- **「実データのみ、推測禁止」** — これを書かないと数値を埋めてくることがある
- **「要約は日本語で」**

## 追い質問

`--output-format json` の `sessionId` を保持すれば文脈を引き継げる。

```bash
# 1 回目: sessionId も拾う
grok -p '<プロンプト>' --max-turns 12 --yolo --output-format json --no-auto-update \
  | jq -r '.text, "SESSION: \(.sessionId)"'

# 2 回目以降
grok -p '<追い質問>' --resume <sessionId> --max-turns 12 --yolo --output-format json --no-auto-update \
  | jq -r '.text'
```

## 落とし穴（実測で確認済み）

- **`--tools` allowlist は使わない。** stock profile が既定ツールを注入した後に allowlist を
  適用する仕様のため、X ツールだけに絞れない。逆に `run_terminal_command` が残り、grok が
  fxtwitter/nitter を curl で叩く遠回りを始めて **20 分以上返ってこない**。
- **`--disallowed-tools` で `scheduler_create` / `scheduler_delete` を外すと起動に失敗する。**
  `scheduler_list` が依存を解決できず `RequirementError` になる。scheduler 群は分割できない。
- 制限は `--tools` ではなく**プロンプトのヘッダ**でかける。これが最も速く安定する。
- `--max-turns` を付けて暴走を止める。X 検索だけなら 12 で十分（正常時は 1〜3 ターンで終わる）。

## 結果の扱い

- 返ってくる数値・日付は grok の検索スナップショット時点のもの。ユーザーに提示するときは
  **投稿 URL を必ず添える**。
- Claude 側の WebFetch では x.com を検証できない。裏取りが必要なら、同じ grok セッションに
  `x_thread_fetch` で当該 URL を再取得させる。
- grok の要約はそのまま貼らず、問いに対する答えの形に整えてから返す。

## 認証

`grok models` で確認できる。grok.com ログイン（`grok login`）または `XAI_API_KEY` のいずれか。
未認証なら `grok login` をユーザーに依頼する（ブラウザが開くため Claude 側では実行しない）。
