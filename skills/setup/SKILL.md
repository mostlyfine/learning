---
name: setup
description: 学習プラグインが観察に使う分析エンジン（claude / codex / copilot）の初回セットアップと再設定を行う。「learning のセットアップ」「観察エンジンを変更したい」、observer ログに unknown engine が出たときの修復、および status / acquire からの委譲で実行する。
allowed-tools: Read, Glob, Grep, AskUserQuestion, Write(.learning/config), Write(.learning/.gitignore), Edit(.learning/config)
---

# /learning:setup — 分析エンジンの設定

セッション観察（observer）に使う分析エンジンを、プロジェクト（cwd）直下の `.learning/config` に保存する。既存の config がある場合は現在値を提示してから上書きする（再設定）。

## 手順

1. 選択肢 `claude` / `codex` / `copilot` を提示する（AskUserQuestion ツールが利用可能ならそれを使い、なければ対話で確認する）
2. 選択に応じて `.learning/config` を書き込む:
   - claude → `engine=claude` と `model=haiku`
   - copilot → `engine=copilot` と `model=claude-haiku-4.5`
   - codex → `engine=codex` のみ（モデルは CLI 既定に任せる）
3. `.learning/.gitignore` が無ければ内容 `*` で作成する（config を含む `.learning` 全体をリポジトリの追跡対象から外す）
4. 「保存しました。以降のセッション終了時から観察が有効になります」と伝える。status / acquire から委譲された場合は元の処理を続行する

## 備考

- 設定はプロジェクト単位。学習データと同じ `.learning` に置かれるため、プラグインを更新しても消えない
- git worktree のセッションでは観察データがメイン作業ツリーの `.learning` に集約されるため、setup もメイン作業ツリーで実行する
- `engine` に上記以外の文字列があると観察は実行されず、有効値の案内がプロジェクトの `.learning/logs/observer.log` に出る
