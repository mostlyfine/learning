---
name: status
description: Instinct 一覧・昇格資格を確認する読み取り専用スキル。「learning status」で起動。
allowed-tools: Read, Glob, Grep, Bash(git rev-parse:*), SlashCommand(/learning:setup), Skill(learning:setup)
---

# /learning:status — Instinct の一覧表示

蓄積された Instinct（`.learning/instincts/*.md`）の frontmatter を集めて一覧表示する。ファイル編集は一切しない（エンジン設定が無い場合のセットアップは `/learning:setup` に委譲する）。

## 初回セットアップへの委譲（エンジン設定が無い場合のみ）

プロジェクトルート（Instinct の置き場所と同じ。worktree 内では「前提」のとおりメイン作業ツリー）に `.learning/config` が存在しなければ、`/learning:setup` を実行（SlashCommand ツール。解決できない場合は Skill ツールで `learning:setup` を起動する）してから本来の処理を続行する。

## 前提

- Instinct の置き場所: プロジェクト直下の `.learning/instincts/`。ただし git worktree 内のセッションではメイン作業ツリーに集約されるため、`git rev-parse --path-format=absolute --git-common-dir` が返すパスの親ディレクトリをプロジェクトルートとして扱う
- 一覧に使う frontmatter: `id`, `type`, `confidence`, `evidence_count`, `status`（スキーマの全体は `${CLAUDE_PLUGIN_ROOT}/skills/acquire/SKILL.md` と observer プロンプト `${CLAUDE_PLUGIN_ROOT}/hooks/prompts/observer.md` を参照）
- 昇格資格: `status: active` かつ `confidence >= 0.7`
- あと一歩（approaching）: `status: active` かつ `confidence` が 0.5 以上 0.7 未満
- instincts ディレクトリが存在しない・空の場合は「まだ Instinct が蓄積されていません。セッションを重ねると自動的に蓄積されます」と report して終了する

## 出力形式

| id | type | confidence | evidence | status |
|---|---|---|---|---|
| use-uv-not-pip | correction | 0.7 | 3 | active |

表の後に、昇格資格のある Instinct が1件以上あれば「昇格資格あり: N 件（/learning:acquire で提案を確認できます）」、0件なら「昇格資格なし」を添える。続けて、あと一歩の Instinct が1件以上あれば「あと一歩（confidence 0.5〜0.69）: N 件」を添える（0件なら何も書かない）。
