---
name: status
description: learning プラグインがこれまでに何を学習したかを確認するとき必ず使う（読み取り専用）。蓄積された Instinct（学習で得た知見）の一覧表示と、昇格資格のある Instinct の確認を行う。「learning status」「learning の状態」「学習状況を見せて」のような直接の呼びかけに加え、蓄積された instinct・知見・学習内容を見たい、学習が進んでいるか知りたい、昇格できそうなものを確認したい、といった learning プラグインの現状把握を求めるあらゆる質問で実行する。エンジン設定が未作成なら初回セットアップ（/learning:setup）へ委譲する。
allowed-tools: Read, Glob, Grep, Bash(git rev-parse:*), SlashCommand(/learning:setup)
---

# /learning:status — Instinct の一覧表示

蓄積された Instinct（`.learning/instincts/*.md`）の frontmatter を集めて一覧表示する。ファイル編集は一切しない（エンジン設定が無い場合のセットアップは `/learning:setup` に委譲する）。

## 初回セットアップへの委譲（エンジン設定が無い場合のみ）

プラグインルート（`${CLAUDE_PLUGIN_ROOT}`。トークンが使えない環境ではこのスキル定義ファイルの位置から辿る）に `.learning/config` が存在しなければ、`/learning:setup` を実行（SlashCommand ツール）してから本来の処理を続行する。

## 前提

- Instinct の置き場所: プロジェクト直下の `.learning/instincts/`。ただし git worktree 内のセッションではメイン作業ツリーに集約されるため、`git rev-parse --path-format=absolute --git-common-dir` が返すパスの親ディレクトリをプロジェクトルートとして扱う
- 一覧に使う frontmatter: `id`, `type`, `confidence`, `evidence_count`, `status`（スキーマの全体は `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` と observer プロンプト `${CLAUDE_PLUGIN_ROOT}/hooks/prompts/observer.md` を参照）
- 昇格資格: `status: active` かつ `confidence >= 0.7`
- instincts ディレクトリが存在しない・空の場合は「まだ Instinct が蓄積されていません。セッションを重ねると自動的に蓄積されます」と report して終了する

## 出力形式

| id | type | confidence | evidence | status |
|---|---|---|---|---|
| use-uv-not-pip | correction | 0.7 | 3 | active |

表の後に「昇格資格あり: N 件（/learning:review で提案を確認できます）」を添える。
