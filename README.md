# learning-skills

AI コーディングエージェントのセッションを自動観察し、行動パターンを Instinct として蓄積、承認制で CLAUDE.md / skill / agent に昇格させる自己完結型プラグイン。Claude Code のほか VS Code / Codex CLI / GitHub Copilot CLI / Cursor でも動作する。

## 仕組み

```
セッション末 hook → ガード判定 → 設定した分析エンジン（claude / codex / copilot）で transcript を分析
  → .learning/instincts/*.md に蓄積（confidence 0.3 から開始）
  → 別セッションで再観察されるたび +0.2
  → 0.7 以上で /learning:acquire の昇格提案対象に
```

昇格はすべてユーザー承認制。蓄積中の Instinct がセッションの挙動に影響することはない。

ターン単位で発火するイベント（Stop 系）に対しては2段のガードで多重学習を防ぐ:
前回分析から `LEARNING_SKILLS_MIN_TURNS` 以上ターンが増えたときだけ再分析し（`.learning/analyzed.tsv`）、
Instinct の強化は Evidence に記録した session id で同一セッション1回に制限する。

## インストール

依存: bash, jq, 選択した分析エンジンの CLI（claude / codex / copilot のいずれか）

### Claude Code

```
/plugin marketplace add mostlyfine/learning
/plugin install learning@learning-skills
```

skill（`/learning:recall`, `/learning:acquire`。自然言語でも呼び出せる）と SessionEnd/Stop hook が自動で有効になる。

### VS Code (Copilot agent, Preview)

コマンドパレットの「Chat: Install Plugin From Source」に `https://github.com/mostlyfine/learning` を指定する。`.claude-plugin/plugin.json` と `hooks/hooks.json` が自動検出され、`Stop` イベントで観察が走る。

### GitHub Copilot CLI

```
/plugin marketplace add mostlyfine/learning
/plugin install learning
```

ルートの `hooks.json`（Copilot 形式）の `agentStop` イベントで観察が走る。

### Codex CLI

```
/plugin marketplace add mostlyfine/learning
/plugin install learning
```

hooks は experimental のため設定での有効化と、plugin hook の trust 承認が必要。`Stop` イベントで観察が走る。

### Cursor (2.5+)

`/plugin install` で導入する。plugin hook が登録されない場合は `hooks/configs/cursor-hooks.json` の内容を `~/.cursor/hooks.json`（または プロジェクトの `.cursor/hooks.json`）にマージし、command のパスを clone 先の実パスに書き換える。

### 対応イベントの対応表

| プラットフォーム | イベント | hook 定義 |
|---|---|---|
| Claude Code | `SessionEnd` / `Stop` | `hooks/hooks.json` |
| VS Code | `Stop` | `hooks/hooks.json`（Claude 形式を自動検出） |
| Codex CLI | `Stop` | `hooks/hooks.json`（要 trust 承認） |
| Copilot CLI | `agentStop` | ルート `hooks.json`（Copilot 形式） |
| Cursor | `stop` | `hooks/configs/cursor-hooks.json`（手動登録） |

なおこのリポジトリ自体を dogfooding する場合は、`claude --plugin-dir .` でこのディレクトリをプラグインとしてそのセッション限定で読み込む。

ランタイムデータ（Instinct・ログ・ロック）はプロジェクト直下の `.learning/` に置かれる（初回実行時に自動作成、`.learning/.gitignore` により全体が commit 対象外）。`.claude/` 配下に置かない理由: headless の claude は `.claude/` 配下への書き込みが保護により拒否されるため。git worktree でのセッションは worktree ごとに分散させず、メイン作業ツリー直下の `.learning/` に集約される（worktree 削除で学習データが消えるのを防ぐため）。

## 使い方

- 蓄積は自動（10 ターン以上のセッション終了時に分析が走る）
- `/learning:recall` — Instinct の一覧と昇格資格の確認
- `/learning:acquire` — 昇格提案を 1 件ずつ承認 / 却下 / 保留
- `/learning:setup` — 分析エンジンの設定・再設定（初回は recall / acquire から自動で委譲される）

## エンジン設定

観察に使う分析エンジンはプロジェクトごとに初回に一度だけ質問され、プロジェクト直下の `.learning/config` に保存される（2回目以降は自動適用。プラグインを更新しても消えない）。`/learning:recall` か `/learning:acquire` を最初に実行したときにセットアップが走り、それまでセッション観察は動かない。

| エンジン | 既定モデル | 実行形 |
|---|---|---|
| `claude` | `haiku` | `claude -p --allowedTools ...` |
| `codex` | CLI 既定 | `codex exec --sandbox workspace-write` |
| `copilot` | `claude-haiku-4.5` | `copilot -p --no-ask-user` |

コマンドが使えない環境（Cursor の手動 hook 登録等）では、プロジェクト直下に `.learning/config` を手で作る:

```
engine=claude
model=haiku
```

`engine` に上記以外の文字列を書くと、観察は実行されず有効なエンジン一覧の案内が `.learning/logs/observer.log` に出力される（`/learning:setup` で再設定できる）。

## 設定（環境変数）

| 変数 | 既定 | 意味 |
|---|---|---|
| `LEARNING_SKILLS_MIN_TURNS` | `10` | 分析対象とする最小ターン数。再分析に必要なターン増分の閾値を兼ねる |

## 開発

```bash
bats tests/                      # ユニットテスト
tests/manual/verify-observer.sh  # observer の受け入れ検証（実 API 消費）
```
