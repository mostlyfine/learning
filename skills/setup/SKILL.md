---
name: setup
description: 学習プラグインが観察に使う分析エンジン（claude / codex / copilot）の初回セットアップと再設定を行う。「learning のセットアップ」「観察エンジンを変更したい」、observer ログに unknown engine が出たときの修復、および recall / acquire からの委譲で実行する。
allowed-tools: Read, Glob, Grep, AskUserQuestion, Write, Edit
---

# /learning:setup — 分析エンジンの設定

セッション観察（observer）に使う分析エンジンを、プラグインルート（`${CLAUDE_PLUGIN_ROOT}`。トークンが使えない環境ではこのスキル定義ファイルの位置から辿る）の `.learning/config` に保存する。既存の config がある場合は現在値を提示してから上書きする（再設定）。

## 手順

1. 選択肢 `claude` / `codex` / `copilot` を提示する（AskUserQuestion ツールが利用可能ならそれを使い、なければ対話で確認する）
2. 選択に応じて `.learning/config` を書き込む:
   - claude → `engine=claude` と `model=haiku`
   - copilot → `engine=copilot` と `model=claude-haiku-4.5`
   - codex → `engine=codex` のみ（モデルは CLI 既定に任せる）
3. 「保存しました。以降のセッション終了時から観察が有効になります」と伝える。recall / acquire から委譲された場合は元の処理を続行する

## 備考

- `engine` に上記以外の文字列があると観察は実行されず、有効値の案内がプロジェクトの `.learning/logs/observer.log` に出る
- プラグイン更新でキャッシュが入れ替わると設定は消え、次回 `/learning:recall` か `/learning:acquire` の実行時にこのセットアップへ委譲される
