---
name: acquire
description: 蓄積された Instinct を1件ずつ承認 / 却下 / 保留し、CLAUDE.md や skill・agent へ反映する昇格レビューを行う。「instinct を昇格して」「Instinct をレビュー」「学習内容を昇格して」だけでなく、「instinct の棚卸しをしたい」「溜まった instinct を整理して」「昇格提案を見せて」のように、蓄積した Instinct を承認・却下しながら整理したいという意図があれば実行する（GitHub の PR レビューやコードレビュー、人事・研修のレビューには使わない）。
allowed-tools: Read, Glob, Grep, AskUserQuestion, Bash(git rev-parse:*), SlashCommand(/learning:setup), Skill(learning:setup), Edit(.learning/instincts/**), Edit(.claude/rules/**), Edit(.claude/skills/**), Edit(.claude/agents/**), Edit(CLAUDE.md), Write(.claude/rules/**), Write(.claude/skills/**), Write(.claude/agents/**)
---

# /learning:acquire — Instinct の昇格提案

蓄積された Instinct（`.learning/instincts/*.md`）のうち信頼度が閾値に達したものを、ユーザー承認のもとで昇格させる。

## 初回セットアップへの委譲（エンジン設定が無い場合のみ）

プロジェクトルート（Instinct の置き場所と同じ。worktree 内では「前提」のとおりメイン作業ツリー）に `.learning/config` が存在しなければ、`/learning:setup` を実行（SlashCommand ツール。解決できない場合は Skill ツールで `learning:setup` を起動する）してから本来の処理を続行する。

## 前提

- Instinct の置き場所: プロジェクト直下の `.learning/instincts/`。ただし git worktree 内のセッションではメイン作業ツリーに集約されるため、`git rev-parse --path-format=absolute --git-common-dir` が返すパスの親ディレクトリをプロジェクトルートとして扱う（メインツリー側の編集には確認プロンプトが出るが正常な動作）
- Instinct ファイルの frontmatter: `id`, `type`(correction|error-solution|workflow), `status`(active|promoted|rejected), `confidence`, `evidence_count`, `promote_to`(rules|instructions|skill|agent), `created`, `updated`
- 昇格資格: `status: active` かつ `confidence >= 0.7`
- instincts ディレクトリが存在しない・空の場合は「まだ Instinct が蓄積されていません。セッションを重ねると自動的に蓄積されます」と report して終了する

## 手順

1. 昇格資格（前提を参照）を満たす Instinct を収集する。0 件なら「昇格資格のある Instinct はありません」と現在の最高 confidence を添えて終了する
2. 各 Instinct について昇格先を決定する。frontmatter の `promote_to` を初期値とし、内容から見て不適切なら変更する:
   - `instructions` → プロジェクトの `CLAUDE.md` に規則として追記（該当セクションがなければ末尾に追加）
   - `rules` → `.claude/rules/<id>.md` としてパスごとのルール定義を新規作成
   - `skill` → 既存 skill の手順改善、または `.claude/skills/<id>/SKILL.md` の新規作成
   - `agent` → `.claude/agents/<id>.md` としてサブエージェント定義を新規作成
3. 昇格先ファイルの現状を読み、具体的な変更案（diff 形式または新規ファイル全文）を作る
4. **1件ずつ**ユーザーに提示し、承認 / 却下 / 保留 を確認する（AskUserQuestion ツールが利用可能ならそれを使い、なければ対話で尋ねる）。質問文には Instinct の Trigger/Action、evidence_count、変更案の要約を含める
   - **承認** → 変更を適用し、Instinct の frontmatter を `status: promoted` に更新、`promoted_to: <適用先パス>` を追記する
   - **却下** → `status: rejected` に更新する（observer が同種を再作成しなくなる）
   - **保留** → 何も変更しない（次回の /learning:acquire 実行に持ち越し）
5. 全件処理後、適用結果のサマリ（承認/却下/保留の件数と適用先パス）を表示する

## 制約

- ユーザーの承認なしに昇格先ファイルを変更しない
- 一度の承認で複数の Instinct をまとめて適用しない（1件ずつ確認する）
- instincts ファイルの confidence や evidence を手動で書き換えない（それは observer の仕事）
