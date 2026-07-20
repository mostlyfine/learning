---
name: import
description: 他プロジェクトやチームメンバーが /learning:export で書き出した Instinct バンドルを取り込む。「instinct をインポートして」「エクスポートされた学習内容を取り込みたい」等で実行する。
allowed-tools: Read, Glob, Grep, AskUserQuestion, Bash(git rev-parse:*), SlashCommand(/learning:setup), Skill(learning:setup), Write(.learning/instincts/**)
---

# /learning:import — Instinct のインポート

`/learning:export` が書き出したバンドルファイル（または同じ形式の共有ファイル）を読み、このプロジェクトの `.learning/instincts/` に取り込む。

## 初回セットアップへの委譲（エンジン設定が無い場合のみ）

プロジェクトルートに `.learning/config` が存在しなければ、`/learning:setup` を実行（SlashCommand ツール。解決できない場合は Skill ツールで `learning:setup` を起動する）してから本来の処理を続行する。

## 前提

- Instinct の置き場所: プロジェクト直下の `.learning/instincts/`。worktree 内のセッションでは `git rev-parse --path-format=absolute --git-common-dir` が返すパスの親ディレクトリをプロジェクトルートとして扱う
- バンドルファイルのパスが与えられていなければユーザーに尋ねる
- バンドル内は `---` 区切りで複数の Instinct ブロック（frontmatter + 本文）が連結されている（`/learning:export` の出力形式）

## 重要: confidence は必ずリセットする

このプラグインの confidence は「このプロジェクトで何セッション観察されたか」という厳格なカウンタであり、主観的な確信度ではない。インポート元の confidence をそのまま信用してはならない。取り込むすべての Instinct は、他の新規 Instinct と同じスタートラインに立つ。

## 手順

1. バンドルファイルを読み、`---` 区切りで Instinct ブロックに分割する
2. 各ブロックの `id` が既存 `.learning/instincts/<id>.md` と衝突するか確認する
   - 衝突する場合は AskUserQuestion で「スキップ」「上書き」「別 id にリネームして取り込む」を1件ずつ確認する
   - 衝突しない場合はそのまま取り込む
3. 取り込む各 Instinct について、以下のように frontmatter を書き換えてから `.learning/instincts/<id>.md` に書き込む:
   - `status: active` に強制する
   - `confidence: 0.3` に強制する（インポート元の値は破棄する）
   - `evidence_count: 1` に強制する
   - `created` / `updated` を今日の日付にする
   - `imported_from: <バンドルの exported_from、または与えられたファイルパス>` を追加する
   - `imported_date: <today>` を追加する
   - `promote_to` は元の値をそのまま引き継ぐ
   - 本文の `# Trigger` / `# Action` は元の内容をそのまま引き継ぐ
   - `# Evidence` は元の内容を残しつつ、先頭に `- <today>: <imported_from> からインポート` を追記する
4. 全件処理後、インポート件数・スキップ件数・上書き件数のサマリを表示する。「confidence 0.3 からのスタートのため、再度観測されるまで /learning:acquire の対象にはなりません」と添える

## 制約

- `.learning/instincts/` 以外の場所には書き込まない
- インポート元の confidence・status・evidence_count をそのまま転記しない（必ず上記のとおりリセットする）
- ユーザーに確認せず既存 Instinct を上書きしない
