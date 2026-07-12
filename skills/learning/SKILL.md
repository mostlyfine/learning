---
name: learning
description: セッション観察で蓄積された Instinct の確認と昇格を行う。「instinct の一覧」「学習状況を見せて」で status を、「instinct を昇格」「学習内容をレビュー」で review を実行する。
allowed-tools: SlashCommand(/learning:status), SlashCommand(/learning:review)
argument-hint: "[status|review]"
---

# learning - Instinct の管理と昇格

実際の手順はコマンド側（`commands/status.md`, `commands/review.md`）にある。この skill は自然言語での呼びかけを対応するコマンドへ振り分けるだけ。

- `$ARGUMENTS` が `review`、またはユーザーの意図が昇格レビューなら → SlashCommand ツールで `/learning:review` を実行する
- それ以外（空・`status`・一覧確認の意図）→ SlashCommand ツールで `/learning:status` を実行する
