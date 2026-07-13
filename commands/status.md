---
description: 蓄積された Instinct の一覧と昇格資格を確認する（読み取り専用）
allowed-tools: Read, Glob, Grep
---

# /learning:status — Instinct の一覧表示

蓄積された Instinct（プロジェクト直下の `.learning/instincts/*.md`）の frontmatter を集めて一覧表示する。下記の初回セットアップを除き、ファイル編集は一切しない。

## 初回セットアップ（エンジン設定が無い場合のみ）

プラグインルート（`${CLAUDE_PLUGIN_ROOT}`。トークンが使えない環境ではこのコマンド定義ファイルの位置から辿る）の `.learning/config` を確認する。存在しなければ、セッション観察に使う分析エンジンをユーザーに確認して作成する:

1. 選択肢 `claude` / `codex` / `copilot` を提示する（AskUserQuestion ツールが利用可能ならそれを使い、なければ対話で確認する）
2. 選択に応じて `.learning/config` を書き込む:
   - claude → `engine=claude` と `model=haiku`
   - copilot → `engine=copilot` と `model=claude-haiku-4.5`
   - codex → `engine=codex` のみ（モデルは CLI 既定に任せる）
3. 「保存しました。以降のセッション終了時から観察が有効になります」と伝えて本来の処理を続行する

## 前提

- 一覧に使う frontmatter: `id`, `type`, `confidence`, `evidence_count`, `status`（スキーマの全体は `commands/review.md` と observer プロンプトを参照）
- 昇格資格: `status: active` かつ `confidence >= 0.7`
- instincts ディレクトリが存在しない・空の場合は「まだ Instinct が蓄積されていません。セッションを重ねると自動的に蓄積されます」と report して終了する

## 出力形式

| id | type | confidence | evidence | status |
|---|---|---|---|---|
| use-uv-not-pip | correction | 0.7 | 3 | active |

表の後に「昇格資格あり: N 件（/learning:review で提案を確認できます）」を添える。
