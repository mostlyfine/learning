---
description: 蓄積された Instinct の一覧と昇格資格を確認する（読み取り専用）
allowed-tools: Read, Glob, Grep
---

# /learning:status — Instinct の一覧表示

蓄積された Instinct（プロジェクト直下の `.learning/instincts/*.md`）の frontmatter を集めて一覧表示する。読み取り専用であり、ファイル編集は一切しない。

## 前提

- Instinct ファイルの frontmatter: `id`, `type`(correction|error-solution|workflow), `status`(active|promoted|rejected), `confidence`, `evidence_count`, `promote_to`(rules|instructions|skill|agent), `created`, `updated`
- 昇格資格: `status: active` かつ `confidence >= 0.7`
- instincts ディレクトリが存在しない・空の場合は「まだ Instinct が蓄積されていません。セッションを重ねると自動的に蓄積されます」と report して終了する

## 出力形式

| id | type | confidence | evidence | status |
|---|---|---|---|---|
| use-uv-not-pip | correction | 0.7 | 3 | active |

表の後に「昇格資格あり: N 件（/learning:review で提案を確認できます）」を添える。
