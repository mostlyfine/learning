# learning-skills 設計ドキュメント

日付: 2026-07-12
ステータス: 承認済み設計（実装前）

## 目的

Claude Code のセッション中の行動パターンを自動的に観察・学習し、再利用可能な知識（Instinct）として蓄積する仕組み。信頼度が閾値に達した Instinct を、ユーザー承認のもとで rules / agent / skill / instructions に昇格させ、既存の Skill を自律的に育てる。

## 要件（確定事項）

| 項目 | 決定 |
|---|---|
| 成果物形態 | 自己完結した skill ディレクトリ `.claude/skills/learning/`（このリポジトリで開発し、導入先プロジェクトへコピー＋hook 登録） |
| 観察タイミング | SessionEnd hook でセッション末に transcript を一括分析 |
| 抽出対象 | ユーザーの訂正・フィードバック / エラー→解決ペア / 繰り返される作業パターン |
| 蓄積中 Instinct の扱い | 蓄積のみ。昇格して初めて行動に反映（セッションへのコンテキスト注入はしない） |
| 昇格方式 | 提案生成 → ユーザー承認で適用 |
| スコープ | プロジェクト単位のみ（グローバル学習はしない） |
| instincts の git 管理 | commit 対象外（`.gitignore` で除外。ローカル専用のランタイムデータ） |

## アーキテクチャ

観察（hook + observer）・蓄積（instincts ストア）・昇格（review skill）の3コンポーネントが疎結合で構成される。

```
SessionEnd hook (session-end.sh)
  └→ ガード判定を通過したら observe.sh をバックグラウンドで detach 起動、即 exit 0
       └→ claude -p（ヘッドレス、既定 haiku）で observer プロンプトを実行
            └→ transcript を分析し instincts/*.md を作成・強化

/learning status … 蓄積状況の一覧表示（読み取り専用）
/learning review … 閾値超えの Instinct から昇格提案（diff）を生成 → 承認で適用
```

## ディレクトリレイアウト

```
<project>/.claude/skills/learning/
├── SKILL.md                  # /learning スキル（status / review をサブコマンドとして統合）
├── scripts/
│   ├── session-end.sh        # SessionEnd hook 本体
│   └── observe.sh            # observer 起動スクリプト
├── prompts/
│   └── observer.md           # transcript 分析プロンプト
├── instincts/                # 蓄積データ（1 Instinct = 1 Markdown、gitignore 対象）
├── logs/
│   └── observer.log          # 実行ログ（gitignore 対象）
├── .lock                     # 多重起動防止ロック（gitignore 対象）
└── .gitignore                # instincts/, logs/, .lock を除外
```

- commit 対象は SKILL.md・scripts/・prompts/・.gitignore のみ。
- hook 登録は導入先プロジェクトの `.claude/settings.json` に SessionEnd → `.claude/skills/learning/scripts/session-end.sh` を記述する。

## 観察パイプライン

### session-end.sh

stdin の hook JSON（`transcript_path`, `cwd`, `reason`）を受け取り、ガード判定を通過したら `observe.sh` をバックグラウンドで detach 起動して即座に exit 0 する（hook のタイムアウトと終了ブロックを回避）。

ガード判定（すべてシェルで完結、LLM 不使用）:

1. **再帰防止**: 環境変数 `LEARNING_SKILLS_OBSERVER=1` が設定されていれば即 exit（observer 自身の `claude -p` セッションによる SessionEnd 再発火の無限ループを防ぐ）。
2. **短小セッションのスキップ**: transcript の user/assistant ターン数が閾値（初期値: 10 ターン）未満ならスキップ。API 消費の主な抑制策。
3. **プロジェクト外のスキップ**: `cwd` 配下に `.claude/` も `CLAUDE.md` もない場合はスキップ。
4. **多重起動防止**: `.lock` によるロック。取得できなければスキップ（次のセッション終了時に拾われる）。

### observe.sh

- `LEARNING_SKILLS_OBSERVER=1` を付与して `claude -p` を起動。プロンプトは `prompts/observer.md` の内容に transcript パスと instincts ディレクトリパスを埋め込む。
- モデルは既定 haiku。環境変数 `LEARNING_SKILLS_MODEL` で上書き可能。
- `trap` でロック解放を保証。

### observer の仕事（prompts/observer.md）

1. transcript を読み、3 カテゴリ（ユーザー訂正 / エラー→解決ペア / 反復作業パターン）の Instinct 候補を抽出する。
2. 既存の `instincts/*.md` を読み、同種の Instinct があれば confidence を加算して evidence を追記、なければ新規ファイルを作成する。同種判定は Trigger/Action の意味的比較で行う（ID の一致ではなく「同じ教訓か」）。
3. `status: rejected` と同種の候補は再作成しない（学習のブラックリスト）。
4. `status: promoted` のファイルには触れない（昇格先が真実源）。

## Instinct データモデル

1 Instinct = 1 Markdown ファイル。frontmatter がメタデータ、本文が知識本体。

```markdown
---
id: use-uv-not-pip
type: correction        # correction | error-solution | workflow
status: active          # active | promoted | rejected
confidence: 0.5
evidence_count: 2
promote_to: instructions  # observer が推定した昇格先（review 時に変更可能）
created: 2026-07-12
updated: 2026-07-12
---

# Trigger
Python パッケージを追加するとき

# Action
pip install ではなく uv add を使う

# Evidence
- 2026-07-12: pip install 実行後にユーザーが「uvを使って」と訂正
- 2026-07-12: 別セッションで同様の訂正
```

### 信頼度モデル

単純な加算式（初期実装では減衰なし）:

- 新規検出時 `confidence: 0.3`
- 別セッションで同種の観察が再発するたび `+0.2`（同一セッション内の複数回は 1 回と数える）、上限 1.0
- `0.7` 以上（= 3 セッション以上で観察）で昇格資格を獲得し、`/learning review` の提案対象になる

### status ライフサイクル

- `active`: 蓄積・強化中
- `promoted`: 承認・適用済み。`promoted_to` に適用先パスを記録
- `rejected`: レビューで却下。observer は同種候補を再作成しない

## 昇格フロー

信頼度は昇格資格を決め、昇格先は種別と内容で決まる。

| Instinct 種別 | 昇格先 | 具体的な適用 |
|---|---|---|
| correction（方針・禁止事項・好み） | rules | プロジェクト CLAUDE.md の規則として追記 |
| error-solution（既存 skill に関連） | instructions | 関連する既存 skill の SKILL.md にトラブルシュート・注意点として追記 |
| error-solution（skill と無関係） | rules | CLAUDE.md のトラブルシュート節に追記 |
| workflow（反復手順） | skill | 既存 skill の手順改善、または新規 skill の作成 |
| workflow（独立実行可能な専門役割） | agent | `.claude/agents/*.md` としてサブエージェント定義を作成 |

### /learning review

1. `instincts/` から `status: active` かつ `confidence >= 0.7` のものを収集（該当なしならその旨を報告して終了）。
2. 各 Instinct について昇格先ファイルの現状を読み、具体的な diff 形式の提案を生成する（既存 skill への追記なら該当 SKILL.md のどこに何を足すかまで示す）。
3. 1 件ずつ提示し、承認 / 却下 / 保留を確認する。
   - 承認 → 編集を適用し、`status: promoted` に更新、`promoted_to` を記録
   - 却下 → `status: rejected`
   - 保留 → `active` のまま次回へ持ち越し
4. 全件処理後、適用結果のサマリを表示する。

### /learning status

instincts 一覧（id / type / confidence / evidence_count / status）と昇格資格ありの件数をテーブル表示する読み取り専用サブコマンド。

## エラー処理

原則: 学習系の失敗はユーザーのセッションを絶対に妨げない。

- `session-end.sh` はいかなる失敗でも exit 0。エラー詳細は `logs/observer.log` に追記するのみ。
- `observe.sh` は `trap` でロック解放を保証。`claude -p` の失敗はログに残して終了。
- stale ロック対策: `.lock` にタイムスタンプを記録し、30 分より古いロックは放棄されたものとみなして奪取する。
- transcript が存在しない・読めない場合、instinct ファイルが壊れている場合は、該当分をスキップしてログに記録する。

## テスト方針

- **シェルスクリプト（決定的な部分）**: bats-core でユニットテスト。フィクスチャ（偽の hook 入力 JSON・偽 transcript）と、PATH に置いたスタブ `claude` コマンド（起動引数を記録するだけ）で、4 つのガードと detach 起動を検証する。TDD（Red-Green-Refactor）で実装する。
- **observer プロンプト（LLM 部分）**: 決定的テスト不可のため、訂正・エラー解決・反復パターンを含むフィクスチャ transcript を用意し、実際に `claude -p` で流して期待する instinct が生成されるかを確認する検証スクリプト＋チェックリストで受け入れ確認する。
- **/learning スキル**: 昇格資格ありの instinct を仕込んだフィクスチャプロジェクトでの手動シナリオ確認（status 表示・review の承認 / 却下 / 保留の 3 経路）。

## スコープ外（YAGNI）

- グローバル（全プロジェクト共通）の Instinct 蓄積
- 蓄積中 Instinct のセッションへのコンテキスト注入
- 信頼度の時間減衰
- 昇格の自動適用（すべてユーザー承認制）
- 既存 Skill の使用結果（つまずき・逸脱）の観察
