---
name: export
description: 蓄積された Instinct を他プロジェクトやチームメンバーと共有するため、ファイルにまとめて書き出す。「instinct をエクスポートして」「学習内容を共有したい」「他のプロジェクトにも持っていきたい」等で実行する。
allowed-tools: Read, Glob, Grep, AskUserQuestion, Bash(git rev-parse:*, git remote get-url origin), Write(.learning/exports/**)
---

# /learning:export — Instinct のエクスポート

蓄積された Instinct（`.learning/instincts/*.md`）のうち、ある程度検証が進んだものを選んで1つのファイルにまとめ、`.learning/exports/` に書き出す。書き出したファイルの他プロジェクトへの配布・共有は行わない（このスキルの権限は `.learning/exports/` への書き込みに限定される）。

## 前提

- Instinct の置き場所: プロジェクト直下の `.learning/instincts/`。git worktree 内のセッションでは `git rev-parse --path-format=absolute --git-common-dir` が返すパスの親ディレクトリをプロジェクトルートとして扱う
- エクスポート対象の目安: `status: active` かつ `confidence >= 0.5`、または `status: promoted`（`status: rejected` は対象外）
- instincts ディレクトリが存在しない・空の場合、または対象の目安を満たす Instinct が0件の場合は「エクスポートできる Instinct がありません」と report して終了する

## 手順

1. 対象の目安を満たす Instinct を一覧する（id, type, confidence, status を表示）
2. AskUserQuestion（複数選択）で、実際にエクスポートするものをユーザーに選ばせる。デフォルトは全選択
3. `git remote get-url origin` が取れればそれを `exported_from` として使う。取れなければ省略する
4. 選択された Instinct ファイルの内容をそのまま連結し、先頭に以下のヘッダを付けて `.learning/exports/<YYYY-MM-DD>-instincts.md` に書き出す（同名ファイルがあれば連番を付ける）:

```markdown
# Exported Instincts

exported_from: <git remote origin url、無ければ省略>
exported_date: <today>
count: <選択件数>

---
```

ヘッダの後に、選択した Instinct ファイルの内容（frontmatter + 本文）をそのまま `---` 区切りで連結する。

5. 書き出したファイルの絶対パスを提示し、「このファイルを共有先にコピーしてください（このスキル自身はプロジェクト外への書き込み権限を持ちません）」と案内する

## 制約

- `.learning/exports/` 以外の場所には書き込まない
- 元の Instinct ファイル（`.learning/instincts/**`）は一切変更しない（エクスポートは複製であり移動ではない）
