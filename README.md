# learning-skills

Claude Code のセッションを自動観察し、行動パターンを Instinct として蓄積、承認制で CLAUDE.md / skill / agent に昇格させる自己完結型 skill。

## 仕組み

```
SessionEnd hook → ガード判定 → claude -p (haiku) で transcript を分析
  → .learning/instincts/*.md に蓄積（confidence 0.3 から開始）
  → 別セッションで再観察されるたび +0.2
  → 0.7 以上で /learning review の昇格提案対象に
```

昇格はすべてユーザー承認制。蓄積中の Instinct がセッションの挙動に影響することはない。

## 導入（他プロジェクトへ）

1. `.claude/skills/learning/` を導入先プロジェクトの同じパスにコピーする
2. 導入先の `.claude/settings.json` に SessionEnd hook を追記する:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/skills/learning/scripts/session-end.sh"
          }
        ]
      }
    ]
  }
}
```

依存: bash, jq, claude CLI

ランタイムデータ（Instinct・ログ・ロック）はプロジェクト直下の `.learning/` に置かれる（初回実行時に自動作成、`.learning/.gitignore` により全体が commit 対象外）。`.claude/` 配下に置かない理由: headless の claude は `.claude/` 配下への書き込みが保護により拒否されるため。

## 使い方

- 蓄積は自動（10 ターン以上のセッション終了時に分析が走る）
- `/learning status` — Instinct の一覧と昇格資格の確認
- `/learning review` — 昇格提案を 1 件ずつ承認 / 却下 / 保留

## 設定（環境変数）

| 変数 | 既定 | 意味 |
|---|---|---|
| `LEARNING_SKILLS_MODEL` | `haiku` | observer が使うモデル |
| `LEARNING_SKILLS_MIN_TURNS` | `10` | 分析対象とする最小ターン数 |

## 開発

```bash
bats tests/                      # ユニットテスト
tests/manual/verify-observer.sh  # observer の受け入れ検証（実 API 消費）
```
