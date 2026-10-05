---
name: dev
description: |
  git worktree (k1LoW/git-wt) 上にタスク専用環境を作り、計画 issue の登録から実装・検証・PR 作成・CI と Codex レビューへの対応までをセッション管理付きで自律実行し、マージ後の worktree とブランチの掃除も行う開発ワークフロー。新規タスクを隔離環境で進めたいとき、issue URL / #番号 を作業指示として渡してその issue 自身を計画書に使いたいとき、`/dev resume` で中断セッションを再開したいとき、`/dev cleanup` でマージ後の worktree とブランチを掃除したいときに使う。
compatibility: Requires git, gh CLI, k1LoW/git-wt (`git wt`), and jq. Phase 2 で Claude Code 組み込みの `/simplify` を使う (実行不能なら skip を記録して続行)。Phase 5.5 は `gh pr checks` で CI を、Codex (`chatgpt-codex-connector[bot]`) 設定済みリポジトリではレビューも監視する (pr-relay mod があれば監視を任せ、無ければ `run_in_background` Bash でポーリングし、不能時は ScheduleWakeup)。Codex 未設定なら CI 監視のみ。実装委任と、ユーザーが求めたときのローカルレビューに codex CLI (`codex exec` / `codex review`) を任意で使う (無ければ skip か subagent にフォールバック)
---

# Dev

Plan から PR 作成・レビュー完了まで一貫した開発ワークフローを、**git worktree 上に隔離して自律実行する**。`k1LoW/git-wt` (`git wt` サブコマンド) でタスクごとに worktree を作り、計画・実装・検証・PR 作成・CI/レビュー対応までその中で完結させる。フェーズ間で承認待ちのために停止せず、**CI 全成功 + レビュー収束** かエスカレーション条件に達するまで自走する。PR マージ後は `/dev cleanup` で worktree とブランチをまとめて掃除する。

## 使い方

```bash
/dev [タスクの説明]              # 新規タスク (Phase 0〜5.5 を自律実行、CI 全成功 + レビュー収束まで)
/dev <issue URL | #番号>         # issue を作業指示として起動 (その issue 自身が計画書になる)
/dev resume [slug]               # 既存セッション再開 (途中中断 or post-PR モード)
/dev review [slug]               # 中断した CI+Review Loop の再開 (Phase 5.5。通常は Phase 5 から自動突入)
/dev cleanup [branch]            # PR マージ後の後片付け (worktree + ブランチ削除 + followup を issue 化)
```

- 引数なし: 既存セッションがあれば AskUserQuestion で「新規 / 再開 / review / cleanup」を確認
- `/dev <説明>`: 指定タスクで Phase 0 から開始し、**Phase 5.5 の終端 (CI 全成功 + レビュー収束) まで自律実行する**。Phase 1 の計画は技術方針を自律決定した上で **GitHub issue (計画 issue) として登録**する (ファイルとしてコミットしない。承認待ちで停止しない)
- `/dev <issue URL | #番号>`: 指定 issue を作業指示として Phase 0 から開始。**その issue 自身を計画書として使い**、計画フォーマットに足りない節があれば計画確定後に本文を更新する ([phases-1-4.md Phase 1](references/phases-1-4.md#phase-1-plan-計画))
- `/dev resume [slug]`: セッション再開。**`status == "pr-open"` のセッションを選ぶと post-PR モード (Phase 5-bis)** に入り、人手主導の追加修正 + PR 本文更新を行う
- `/dev review [slug]`: **`status == "pr-open"` のセッションで CI+Review Loop (Phase 5.5) を再開する**。通常は Phase 5 (Open PR 作成) 完了直後に自動突入するため明示起動は不要で、セッションが中断した場合の再入口。CI (`gh pr checks`) と Codex (`chatgpt-codex-connector[bot]`) の 👀 → 指摘 → 👍 を監視し、CI FAIL の修正とレビュー指摘への自動対応 (成立確認 → 修復記録 → 修正と検証 → push → 返信) を **CI 全成功 + レビュー収束まで、push 予算 3 回の中で自走**
- `/dev cleanup`: cwd が worktree ならそのブランチが対象、違えばセッション一覧から選択。**merge 確認後に未着手の `followups[]` を GitHub issue として自動作成**
- **初回のみ**: `wt.copyignored` 等の git-wt 設定を済ませると `.dev.vars` / `.env*` のコピー漏れを防げる ([references/setup.md](references/setup.md) 参照)

## ワークフロー全体像

```
Phase 0: Prepare worktree (新規タスク時のみ)
  ├─ git-wt 前提設定をチェック、未設定なら警告して続行
  ├─ リポジトリ root と default ブランチを検出
  ├─ slug・ブランチ名を自動決定 (衝突時は連番付与で自動回避)
  ├─ 既存 worktree 再利用 / なければ git-wt で新規作成
  ├─ WT_PATH (絶対パス) を確定
  └─ セッションポインタを ~/.claude/dev-sessions/<slug>.json に保存

Phase 1: Plan        計画策定 → 技術的な実装方針は自律決定 (根拠を「設計判断」節に記録)
                     → GitHub issue 化 (計画 issue) して Phase 2 へ自動続行
                     issue 起動時はその issue 自身を計画書として使う
                     (計画はファイルとしてコミットしない。承認待ちで停止しない)
Phase 2: Implement   計画通りに実装、設計判断は自律決定して ADR 記録、
                     **最後に /simplify を必ず実行**
                     (skip 判断は禁止。差分サイズ・テスト PASS・主観的なリファクタ
                      余地の有無は skip の根拠にならない)
Phase 3: Verify      型 / lint / テスト / ビルドを自動検出して実行
                     失敗があれば「新規 vs 既存」を別 worktree で切り分け
Phase 4: Fix         新規問題は解決まで修正ループ (3 回超えたら根本原因診断に切替)、
                     既存問題は自動判断マトリクスで対応確定
                     (CI を落とす/安価なら今回 PR で修正、それ以外は followup 化)
Phase 5: PR          全検証 PASS 後に **Open PR** を作成 (Draft にしない)。
                     ローカル Codex レビューは既定で掛けず、最初の広い発見は
                     クラウドの徹底的レビューに任せる (ユーザーが求めたときだけ掛ける)
                     セッションを status: "pr-open" に更新し、Phase 5.5 へ自動続行
Phase 5.5: CI + Review Loop  Phase 5 から自動突入 (/dev review で再開も可)。
                     CI (gh pr checks) と Codex 自動レビューを能動監視し、
                     CI FAIL は修正して push、レビュー指摘は成立を確認して修正し、
                     同根の箇所をまとめて直し、検証してから 1 回 push、返信する。
                     **CI 全成功 + レビュー収束 (👍 か、head レビュー済みで
                     P1/P2 全件 disposition 済み) まで、push 予算 3 回の中で**繰り返す。
                     予算到達後は残指摘の一覧と推奨 disposition を提示してユーザー判断
Phase 5-bis: Post-PR Iteration  /dev resume で起動。人手主導の追加修正 + PR 本文更新
Phase 6: Cleanup     /dev cleanup (または pr-relay の cleanup ボタン) で起動。PR MERGED 確認後、followup を
                     GitHub issue 化、worktree + ブランチ削除
                     → プロジェクト固有の cleanup 後処理 (プロジェクトの
                     CLAUDE.md に定義があれば、ベストエフォートで実行)
```

## いつどの reference を読むか

- **Phase 0 を実装するとき / git-wt の整合性チェックロジックが必要なとき** → [references/phase-0-worktree.md](references/phase-0-worktree.md)
  - 9 段階の手順、`wt.copyignored` / `wt.copy` の状態判定ルール、ブランチ命名の自動決定、既存 worktree 再利用判定、フォールバック
- **Phase 1-4 (Plan / Implement / Verify / Fix) を実行するとき** → [references/phases-1-4.md](references/phases-1-4.md)
  - **計画 issue の 2 モード (新規作成 / 既存 issue を計画書として採用)**、設計判断プロセス (技術的判断の自律決定基準・要件レベルの判断との切り分け)、計画 issue フォーマット、ADR フォーマット、検証コマンド自動検出、別 worktree での新規 vs 既存切り分け、既存問題の自動判断マトリクス、followups[] への記録
- **作業単位を subagent / Codex に委任するとき (Phase 1 の調査、Phase 2 / 5.5 の実装ステップ)** → [references/model-routing.md](references/model-routing.md)
  - 実行主体を自律選定するための判断原則 (確実にこなせる最小コスト・メイン文脈の最小化・検収コスト・委任オーバーヘッド)、実行主体カタログ (haiku 〜 メイン同格、codex)、判定手順と選定理由のナレーション、委任プロンプトの必須要素、`cwd=$WT_PATH` などの dev 固有 Codex ルール、検収 (diff レビュー) と 2 連続 FAIL での引き取り、メインに残る責務
- **Phase 5 / Post-PR / Cleanup を実行するとき** → [references/phases-5-6.md](references/phases-5-6.md)
  - **PR 作成前ローカルレビュー (既定では掛けない。ユーザーが求めたときだけ `scripts/local-codex-review.sh` で最大 2 パス)**、Open PR 作成、PR body テンプレート (「レビュアー向けの前提」節を含む)、**Test plan 構築ルール (ローカル検証可能 / 人手必須の分類、Phase 3 で未実行の項目を Phase 5 内で能動的に追加実行、捏造禁止)**、`--body-file` 必須・デフォルトテンプレートフォールバック禁止、Phase 5.5 への自動続行、Post-PR の本文同期更新 (`gh pr edit --body-file`)、Cleanup の followup 自動 issue 化 (重複チェック・ラベル推定・5 件以上で確認)、worktree 削除フォールバック (`-D`)、**プロジェクト固有の cleanup 後処理フック (プロジェクトの CLAUDE.md に「`/dev cleanup` 後の後処理」節があれば実行)**
- **Phase 5.5 (CI + Codex レビュー対応ループ) を実行するとき / Phase 5 完了後に自動突入するとき / `/dev review` で再開するとき** → [references/phase-5.5-review-loop.md](references/phase-5.5-review-loop.md)
  - **CI 監視 (`gh pr checks`) と CI FAIL 修正ラウンド**、Codex の挙動 (実 PR 観測で確定した事実表。1 パス 1〜2 件の検出、利用上限、同一 commit 再レビュー)、監視 state machine、`scripts/poll-codex-review.sh` の使い方、triage 分類 (成立確認 → fix/rebut/followup/reply-only)、修復記録と自律修正を止める条件、push 前ローカルレビュー (既定では掛けない)、返信フロー、**baseline-diff による false-approve 防止**、**終端条件 (APPROVED / CONVERGED / REVIEW_INCOMPLETE)**、push 予算 (既定 3) とエスカレーションの 4 択、findings[] 台帳と計測。PR 本文同期と followups[] は Phase 5-bis / Phase 6 の仕組みを再利用
- **セッションファイルを書くとき / 中断・再開ロジックが必要なとき** → [references/session-management.md](references/session-management.md)
  - JSON スキーマ全フィールド、状態遷移 (`in-progress` → `pr-open` → `cleaned`)、整合性チェック、フェーズスキップ
- **初回セットアップ / Phase 0 の警告に対処するとき** → [references/setup.md](references/setup.md)
  - 必須レベル (`wt.copyignored`)、推奨レベル (`wt.symlink`)、プロジェクト別 (`wt.hook`)、確認コマンド

## Claude が守るべき行動指針

### 全フェーズ共通

1. **各フェーズ開始時に宣言する** — 「Phase N: [名前] を開始します」と明示
2. **フェーズ間で停止しない** — Phase 0 → 5.5 を連続実行し、終端 (CI 全成功 + レビュー収束) かエスカレーション条件に達するまで自走する。承認待ちのための停止をしない。フェーズの区切りでは宣言と要点のナレーションだけ行い、そのまま次へ進む
3. **技術的判断は自分で下す** — 実装アプローチ・ライブラリ選定・データ設計・エラー処理方式などは、自分が最適と判断したものを選び、根拠を計画の「設計判断」節と (重大なものは) ADR に記録する。自動実行フェーズ (Phase 0〜5.5) で AskUserQuestion を使うのは次の 3 つに限る:
   - (a) **要件レベルの曖昧さ**: 何を作るか自体が複数解釈でき、どちらを選ぶかで成果物の意味が大きく変わる場合 (技術的な How ではなく What の曖昧さ)
   - (b) **破壊的操作・特殊な外部公開操作**: 未マージ PR での `-D` 強制削除、未コミット変更の破棄、リモートブランチ削除、CLOSED issue/PR の再オープンなど
   - (c) **Phase 5.5 のエスカレーション条件**: push 予算 (max_push_rounds、既定 3) 到達後の新規指摘、同じ不変条件への 2 ラウンド目の修正や前ラウンドの判断を反転させる修正 (自律修正を止める条件)、P1/P2 の反論、自力で解決できない CI 失敗、自動 rebase 不能なコンフリクト等。エスカレーションでは残指摘の一覧と推奨 disposition を提示し、選択肢は「名指しの指摘だけ直す / 残存リスクを受け入れる / revert か分割 / 人手レビューへ」の 4 つ。ラウンド上限を上げる選択肢は出さない

   ユーザー起動の対話コマンド (`/dev` 引数なしの入口選択、`/dev cleanup` の確認フロー) はこの制限の対象外
4. **進捗はフェーズ宣言と計画 issue で追跡する** — 進捗はフェーズ宣言のナレーションと計画 issue の更新で追跡する。タスク管理ツール (TaskCreate 等) が利用可能な環境ではそれも使ってよい
5. **作業単位ごとに実行主体を自律選定してトークンを節約する** — メインは司令塔 (計画・判断・統合・検証判定・外部公開操作) に徹し、実行作業は [model-routing.md](references/model-routing.md) の判断原則 (確実にこなせる最小コスト・メイン文脈の最小化・検収コスト・委任オーバーヘッド) で、メイン直接 / subagent の model 指定 (haiku 〜 メイン同格) / codex (`codex exec`) から都度選び、1 行の選定理由を添える (数回のツール呼び出しで済む作業はメイン直接)。固定の対応表に機械的に従わない。委任してもコミット・push・`gh` 操作・`/simplify` ゲート・検証判定はメインに残る。委任成果は diff レビュー後に受け入れ、同一ステップで 2 回連続検証 FAIL したらメインが直接引き取る
6. **報告は証拠に対応させる** — フェーズの区切りや完了報告で述べる各項目 (PASS、push 済、返信済、issue 化済) は、このセッションのツール結果を指せるものだけにする。未検証の項目は「未検証」と明示する (compaction 後は要約の記憶と実結果を混同しやすい)
7. **コンテキスト圧縮の後は現在地を確定してから続行する** — セッションファイル・計画 issue 本文・`git -C "$WT_PATH" status` と `log` を読み直して現在地と未完了ステップを確定してから続行する (要約に残った記憶で進めると、済んだつもりのステップを飛ばす)

### Phase 2 完了条件 (exit checklist)

Phase 3 (Verify) に進む前に以下を **全て満たすこと**。1 つでも欠けていたら Phase 2 は未完了:

1. 計画 issue の実装ステップが全て完了している
2. ADR が必要な設計判断は `docs/adr/...` に記録済み
3. **`/simplify` skill を実行済み** ([phases-1-4.md 手順 8](references/phases-1-4.md#phase-2-implement-実装))
   - **skip 判断は禁止**。差分サイズ・テスト PASS 状況・「リファクタ余地はなさそう」という主観的見立ては skip の根拠にならない
   - リファクタ余地の有無を判定するのは `/simplify` 側の役割なので、呼ぶかどうかを自分の見立てで決めず **機械的に呼ぶ** (「3 ファイル / 150 行 / 純関数 1 個」と見立てて skip した変更から、後で Should-fix が 2 件出た)
   - skip してよいのは、呼んだが実行できなかった (skill not found 等) 場合と、ユーザーが明示的に skip を指示した場合だけ。理由を計画 issue の「結果」節に記録してナレーションで報告する
   - `/simplify` の戻り値が「変更なし」または書き換え適用後にのみ Phase 3 へ進む (書き換えは自動で受け入れ、回帰は Phase 3 の Verify で検出する)
   - **所要時間目安**: 小規模変更 (数十行 / typo / 文言修正) なら数十秒〜1 分で「変更なし」が返る。中規模 (100〜200 行) でも書き換え提案ありで 2〜3 分。「急いでいるから skip」は時間効率の観点でも誤判断 (skip 後に PR レビューで指摘される往復コストの方が大きい)

## Claude Code 実行環境の絶対条件

以下は本スキルで git 操作を組む際の前提:

1. **Bash 呼び出し間で cwd は保持される** (`cd` の効果は次の Bash 呼び出しに引き継がれる)。ハーネスが cwd をセッションの作業ディレクトリへ戻すのは、コマンドがセッションの許可ディレクトリの外へ出たときだけで、そのときは出力に `Shell cwd was reset to <path>` が出る。直前の呼び出しの cwd が残るので、worktree と main リポジトリのどちらにいるかを推測で決めない。worktree で作業する全コマンドは `cd "$WT_PATH" && ...` を先頭に付けるか、`git -C "$WT_PATH" ...` を使い、明示したパスで曖昧さを消す。所在の判断が要る場面では `pwd` を出力に含める
2. **zsh の `git wt` シェル統合は Claude Code の bash では効かない**。`git-wt` サブコマンドを直接呼び、worktree パスは `--json` 出力から取得する
3. **worktree パス・リポジトリ root は絶対パスで保持する** (セッションファイルに記録)

## Gotchas

- **`git wt` には verb サブコマンドが無い。裸の単語は全て branch/worktree 名として解釈され、無ければ作成される**。git-wt の文法は `git wt <branch|worktree|path>` = 「その worktree に switch、無ければ branch ごと作成」。`git wt version` / `git wt status` / `git wt list` / `git wt info` / `git wt check` などは **`version`/`status`/… という名前の worktree + branch を誤作成する** (git や一般 CLI の `tool <verb>` 直感がここでは逆に働く)。**読み取り専用操作は必ず以下で行う**:
  - 存在確認 → `command -v git-wt`
  - バージョン → `git-wt --version` (出力例 `git-wt version 0.29.0`)
  - 一覧 → `git wt` (引数なし) / 機械可読は `git wt --json`
  - ヘルプ → `git-wt --help`

  迷ったら **`git wt <なにか>` に裸の positional 引数を渡すのは「worktree を作る/切り替える」目的のときだけ** と覚える。確認・検査用途では絶対に渡さない。
- **`git wt --json <branch>` は list モードでのみ JSON 配列を返す**。作成時 (`git wt <branch> <start-point>`) には付けず、作成後の list で path を引く 2 段階手順を踏む ([phase-0-worktree.md 手順 7](references/phase-0-worktree.md#手順-7-worktree-新規作成))
- **`wt.copyignored=true` は gitignored なファイルだけ対象**。`.dev.vars` が `.gitignore` 未登録だと copy されない。判定ルールは [phase-0-worktree.md 手順 0](references/phase-0-worktree.md#手順-0-git-wt-前提セットアップの自動チェック)
- **検証失敗の切り分けで `git checkout` を使わない**。作業状態を壊すリスクがあるので、必ず別 worktree で再実行 ([phases-1-4.md Phase 3](references/phases-1-4.md#phase-3-verify-検証))
- **「間違った場所を編集した」と思ったら、復旧操作の前に両方の差分を見る**。`cp` や `git checkout --` で戻す前に、worktree と main リポジトリの両方で `git -C <path> status` と `git -C <path> diff --stat` を確認する。diff が空なら、そこは編集されていない。復旧のつもりの `cp` / `git checkout --` は破壊的操作である。cwd が保持されていないと思い込み、worktree に正しく入っていた編集を「main を汚した」と誤診して、main の clean なファイルを worktree へ `cp` し、自分の編集を消した実例がある
- **PR 作成・更新は常に `--body-file`**。Phase 5 の初回作成は `gh pr create --body-file`、Phase 5-bis の更新は `gh pr edit --body-file`。`--body ""` は事故のもと、`/pr-create` 経由や Claude Code デフォルトの `## Test plan` プレースホルダにフォールバックすると Phase 3 結果と整合しない PR が出る ([phases-5-6.md Phase 5](references/phases-5-6.md#phase-5-pr-プルリクエスト) / [Phase 5-bis](references/phases-5-6.md#phase-5-bis-post-pr-iteration))
- **計画 issue の作成・本文更新は計画確定後に 1 回で行う**。issue の作成・編集はリポジトリ watcher に通知が飛ぶ外部公開操作。ドラフト段階で issue を作って編集を繰り返さない。issue 起動モードで既存 issue の本文を計画フォーマットに更新するときも、**元の本文を黙って破棄しない** (原文の要素を各節に組み込むか「## 経緯 (原文)」節として保全する)
- **PR / issue の本文・タイトルは投稿前に cognitive-rhythm-writing で推敲**。`gh pr create/edit`・`gh issue create/edit`（および MCP）で投稿する前に Skill(cognitive-rhythm-writing) を発火させ（PR / issue は人間が読む文章なので japanese-tech-writing 単独より優先。併用規範として japanese-tech-writing も読み込まれる）、`--body-file` に書き出す本文と `--title` を推敲してから投稿する。投稿コマンド実行時には PreToolUse hook (`~/.claude/hooks/jtw-guard.sh`) が推敲済みかを確認する safety net が走る（グローバル CLAUDE.md「日本語文章」を参照）
- **Test plan を「未確認のまま PR」にしない**。計画の検証方法のうちローカル検証可能な項目は Phase 5 内で能動的に追加実行してチェック済みにし、`[x]` には実コマンド・実結果を併記する。実行していない項目を `[x]` にしたり、「ロールプレイで PASS」のような擬似結果を本文に書いたりしない (詳細: [phases-5-6.md Test plan 構築ルール](references/phases-5-6.md#test-plan-構築ルール))
- **`gh issue create` の長文 body は `--body-file` を使う**。shell 展開で改行・引用符がクラッシュする。`issue_url` が既に入っている followup を再作成しない (冪等性違反)
- **`--body-file` の指定先は `mktemp` で生成した動的パス**。`/tmp/followup-1.md` のような固定名は別 worktree / 別セッションが同じ `/tmp` を共有しているため、過去に他セッションが書き残した古い内容をそのまま投稿する事故が起こりうる。`BODY=$(mktemp -t followup.XXXXXX)` で取り、使い終わったら `rm -f "$BODY"`
- **`gh issue create` / `gh issue edit` / `gh pr create` / `gh pr edit` の `--body-file` は投稿直前に head で検証**。Write tool は `<tool_use_error>File has not been read yet` で拒否されることがあり、エラーを見逃すと意図と異なる中身を投稿してしまう。`head -c 300 "$BODY"` で先頭 300 byte を出力し、想定する書き出し (PR 番号や issue 番号など) が含まれることを目視で確認してから投稿する
- **PR state が MERGED でない状態で `-D` を勝手に使わない**。明示ユーザー同意のみ
- **未コミット変更を勝手に破棄しない / 実行中プロセスを勝手に kill しない** (警告のみ)
- **Phase 2 末尾の `/simplify` を skip しない**。「差分が小さい」「typecheck/test PASS した」「リファクタ余地はなさそう」「ユーザーが急いでいる」は skip の根拠にならない。リファクタ余地の判定主体は `/simplify` 側。実例: 「3 ファイル / 150 行 / 純関数 1 個 / テスト付き」と判断して skip した結果、後で `/simplify` を実行すると Should-fix が 2 件 (コンポーネント抽出・冗長 sort 削除) 検出された。skip 判断ではなく **`/simplify` 呼び出し → 戻り値が "変更なし" を確認** の手順を踏むこと ([SKILL.md Phase 2 完了条件](#phase-2-完了条件-exit-checklist))

### Phase 5.5 (CI + Codex レビュー対応) の Gotchas

- **CI 判定は `gh pr checks` の bucket で行う**。`pass` / `skipping` 以外の bucket (`fail` / `pending` / `cancel`) が残っていれば CI 未達。checks が 1 つも無いリポジトリ (「no checks reported」エラー) は CI 条件を満たしたとみなす。`--watch` は前景 sleep がブロックされるため **`run_in_background` で起動する**
- **終端は APPROVED / CONVERGED / REVIEW_INCOMPLETE のいずれかで、いずれも「最新 push に対する CI 全成功」を伴う**。APPROVED と CONVERGED は head レビューの確認も伴い、REVIEW_INCOMPLETE は head が未レビューであることを記録して報告する。👍 だけ、CI 緑だけで終了しない。逆に「👍 が付くまで push を続ける」もしない。head に対する最新レビューの P1/P2 が全て disposition 済みなら、👍 が無くても CONVERGED で終了する
- **Codex は 1 パスに 1〜2 件しか指摘を出さなかった** (2026-03〜09 の 506 ラウンドで 1 件 74%、2 件 22%。2026-09-07 から「徹底的なコードレビュー」ON)。指摘を 1 件直して push するたびに次の 1〜2 件が出るので、同根の箇所をまとめて直し、修正とその影響先を検証してから 1 回 push する。**ローカルの Codex レビュー (`scripts/local-codex-review.sh`) は、PR 作成前も push 前も既定で掛けない**。2026-10-02 の実測では 1 パスで週間メーターがおよそ 1〜1.5 ポイント動き、クラウドのレビュー 1 回より大きかった。掛けた PR でもクラウドのラウンドは減らなかった。ユーザーが明示的に求めたときだけ掛ける
- **指摘は問題の記述として読み、提案コードをそのまま貼らない**。成立を一次情報で確認してから fix にし、P1 と並行制御・状態遷移・永続化の P2 には修復記録 (失敗 / 不変条件 / 修復 / 証拠) を書く。同根の箇所は同じ commit で直す。12 ラウンド続いた PR は 13 件中 10 件が「提案どおり直した箇所への次の指摘」だった
- **push 予算は 3 回 (`max_push_rounds`)。エスカレーションの中で上げない**。上限 5 ラウンドの時代に「続行」で 8 / 10 / 12 に上がった実績があるので、選択肢に「続行」を置かない
- **返信だけのラウンドで `@codex review` を投げない**。同じ commit が再レビューされ、前のパスで出なかった指摘が出る (#1145 R5)。`@codex review` は push 後に自動レビューが来ないときの 1 PR 1 回のフォールバック
- **利用上限コメント (「You have reached your Codex usage limits」) を無視して待ち続けない**。`signal=usage_limited` は REVIEW_INCOMPLETE の終端で、approved と報告しない。head が未レビューであることを報告する
- **P1 の fix には再現テストを付ける**。Codex は自分の P1 に対する fix の有効性を再検証しない (PRAGMA no-op の見逃しが実例)
- **CI 失敗を `gh run rerun` の連打で握りつぶさない**。rerun は flaky 切り分けとして 1 回のみ。2 回連続で落ちたら実問題として修正する
- **Codex の approved を「+1 が存在する」で判定しない**。GitHub は (user, content) で reaction を dedupe するため codex の +1 は 1 つしか存在せず created_at が固定されうる。過去ラウンドの +1 を見て早期終了する事故が起きるので、**`review.last_push_at` より新しい +1 だけ**を approved シグナルにする (baseline-diff)。baseline は push のときだけ動かし、push しないラウンドの同じ review の再返却は `--processed-reviews` (処理済みの review id) で止める。判定ロジックは [`references/scripts/poll-codex-review.sh`](references/scripts/poll-codex-review.sh) に集約 ([phase-5.5-review-loop.md](references/phase-5.5-review-loop.md))
- **再レビューで commit 完全一致を待たない**。Codex は最新コミットをレビューし中間コミットをスキップ、最終コミットは review なしで +1 のみのことが多い。`last_push_at` 以降の 👍 と、未処理の review (処理済みの id に無いもの) で判定する。**1 ラウンド 1 push に直列化**する (複数 push すると Codex が中間をスキップして追跡が壊れる)
- **ツール一覧に `mcp__pr-relay__watch` があれば、push 後に監視を頼んでターンを終える (relay モード)**。`--watch`、`sleep`、ScheduleWakeup で待たない。起こされたときの入り方と、起こされない事象 (利用上限、時間切れ) の扱いは [phase-5.5-review-loop.md 待ち方](references/phase-5.5-review-loop.md#待ち方-relay-モードと-poll-モード)
- **poll モード (pr-relay が無い) では `poll-codex-review.sh --watch` を `run_in_background` で起動する**。前景 Bash では sleep がブロックされる。watch が使えない環境は 1 ショット呼び出し + ScheduleWakeup (240-270s、prompt cache TTL 内) にフォールバック
- **Codex レビューへの返信本文も `--body-file`/`--input` + `mktemp` + `head` 検証の対象**。`gh api repos/{o}/{r}/pulls/{n}/comments/{id}/replies` に `jq -n --rawfile b "$BODY" '{body:$b}'` で JSON 化して `--input -` で渡す (shell 展開で改行・引用符が壊れる事故を防ぐ)
- **Codex の指摘を黙って全部修正しない / 黙って全部無視しない**。全件 triage し、誤指摘は一次情報を根拠に反論 (rebut)、スコープ外は followup 化する

## 注意事項

- **計画 issue を登録してから実装に入る** — Phase 1 で計画を確定して issue 化してから Phase 2 に進む。PR 本文の計画リンクと Test plan は計画 issue の「検証方法」節から組む。ユーザーが計画のスキップを明示した場合だけ Phase 2 から始める ([session-management.md フェーズスキップ](references/session-management.md#フェーズスキップ))
- **既存コードの尊重** — 変更箇所以外のコードスタイルやパターンに合わせる
- **コミットは適切な粒度で** — 1 つの論理的変更 = 1 コミットを原則とする
- **main を壊さない** — Phase 5 (PR 作成) 前に全検証 PASS を必須とする。検証失敗を発見したら必ず「新規 vs 既存」を切り分け、既存問題は Phase 4-B の自動判断マトリクスで対応を確定する (CI を落とすなら今回修正、それ以外は followup 化して PR に明記)。「main にも同じエラーがあるから無視」は禁止
- **検証失敗のスルー禁止** — 「自分の変更による失敗ではない」と判断しても、切り分けと記録 (修正 or followup 化) なしに無視して PR を作成しない
- **main リポジトリ側で作業しない** — Phase 0 以降は必ず worktree 内で作業。Read/Write/Edit は `$WT_PATH` 配下の絶対パスを使う (git-wt 未検出で従来動作にフォールバックした場合を除く)
- **cleanup の自動化禁止** — PR マージ確認は `gh pr view --json state` が `MERGED` を返した場合のみ削除。未マージで勝手に `-D` しない

## 実行例

```
# 基本的な使い方 (Phase 0〜5.5)
/dev ユーザープロフィールページに画像アップロード機能を追加する

# 期待される動作
# Phase 0: worktree 準備 → .wt/feat-profile-image-upload/ 作成
#          → ~/.claude/dev-sessions/profile-image-upload.json 保存
# Phase 1: 計画策定 (技術方針は自律決定、根拠を「設計判断」節に記録)
#          → gh issue create で計画 issue 化 → セッションファイルに plan_issue (URL) 記録
# Phase 2: 実装 (worktree 内、設計判断は自律決定 → ADR 記録)
# Phase 3: 検証 (テスト・lint・型チェック自動実行、失敗は default branch worktree で切り分け)
# Phase 4: 修正 (問題があれば修正ループ)
# Phase 5: Open PR 作成 → セッションファイルに pr_url 記録
#          → 計画 issue の「結果」節を記入 (クローズは PR の Closes / 部分消化ルールに従う)
# Phase 5.5: CI (gh pr checks) と Codex レビューを監視し、
#            CI FAIL の修正・レビュー指摘への対応を
#            CI 全成功 + レビュー収束まで、push 予算 3 回の中で自動で繰り返す
#            → 完了報告 (受信レビュー数、push 回数、対応内訳、PR URL)。マージ後は /dev cleanup

# issue を作業指示として起動 (その issue が計画書になる)
/dev https://github.com/org/repo/issues/120
/dev #120

# 期待される動作 (新規タスクとの差分)
# Phase 1: issue #120 の本文を計画の下書きとして読み込み、
#          必須節 (目的 / スコープ / 実装ステップ / 検証方法) が不足していれば
#          コードベース調査と自律設計判断で補完 → gh issue edit で本文を計画フォーマットに更新
#          (原文は保全)。新規 issue は作らない

# 途中再開
/dev resume                              # セッション一覧から選択
/dev resume profile-image-upload         # slug 指定

# PR マージ後の後片付け
/dev cleanup                             # cwd が worktree ならそのまま対応
/dev cleanup feat-profile-image-upload   # ブランチ指定
```

## 関連スキル

- `/plan` : 計画策定のみ (Phase 1 相当)
- `/pr-create` : PR 作成のみ (Phase 5 相当)
- `/spec` : 仕様駆動開発 (より大規模な機能向け)
- `/spec-new` : ゼロからの仕様策定
- `/simplify` : Phase 2 の最後に呼ばれるリファクタリング
- `/pr-feedback` : Phase 5.5 のコメント分類体系 (must/imo/nits/q) と返信テンプレートの参照元
