# learning-skills 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code セッションを SessionEnd hook で観察し、Instinct として蓄積、承認制で CLAUDE.md / skill / agent に昇格させる自己完結型 skill を構築する。

**Architecture:** 観察（session-end.sh + observe.sh + observer プロンプト）・蓄積（`.claude/skills/learning/instincts/` の Markdown ファイル群）・昇格（`/learning` skill）の3コンポーネント疎結合構成。分析は `claude -p`（ヘッドレス、既定 haiku）で行い、ユーザーセッションを一切ブロックしない。

**Tech Stack:** bash + jq（ランタイム依存はこの2つのみ）、bats-core 1.13（テスト）、Claude Code hooks / skills / headless mode

**Spec:** `docs/superpowers/specs/2026-07-12-learning-skills-design.md`

## Global Constraints

- `session-end.sh` はいかなる失敗でも **exit 0**（セッション終了を絶対にブロックしない）
- ランタイム依存は bash と jq のみ。追加インストールを要求しない
- 閾値（定数）: ターン数下限 `10`、stale ロック `1800` 秒、confidence 初期値 `0.3`・加算 `+0.2`・上限 `1.0`・昇格資格 `0.7`
- observer のモデル既定は `haiku`、環境変数 `LEARNING_SKILLS_MODEL` で上書き
- 再帰防止環境変数は `LEARNING_SKILLS_OBSERVER=1`、テスト用同期実行は `LEARNING_SKILLS_SYNC=1`、ターン数下限上書きは `LEARNING_SKILLS_MIN_TURNS`
- `instincts/`, `logs/`, `.lock` は commit しない（`.claude/skills/learning/.gitignore` で除外)
- 1 Instinct = 1 Markdown ファイル。frontmatter スキーマ: `id`, `type`(correction|error-solution|workflow), `status`(active|promoted|rejected), `confidence`, `evidence_count`, `promote_to`(rules|instructions|skill|agent), `created`, `updated`, （promoted 時のみ）`promoted_to`
- このリポジトリ自体が導入例（dogfooding）: 実装は `.claude/skills/learning/` 配下、テストはリポジトリルートの `tests/`
- コミットメッセージ末尾に `Claude-Session: https://claude.ai/code/session_01LWvko5t2KQ1Y3nhmSJSTcK` を付ける

---

### Task 1: session-end.sh（SessionEnd hook 本体とガード判定）

**Files:**
- Create: `.claude/skills/learning/scripts/session-end.sh`
- Test: `tests/session_end.bats`

**Interfaces:**
- Consumes: stdin の hook JSON（`transcript_path`, `cwd` キーを使用）
- Produces: `observe.sh <transcript_path> <cwd>` の起動規約（Task 2 が実装）、`.lock` ファイル（epoch 秒を1行、observe.sh が削除）、`logs/observer.log`（observe.sh の stdout/stderr 追記先）

- [ ] **Step 1: 失敗するテストを書く**

`tests/session_end.bats` を以下の内容で作成:

```bash
#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  PROJECT="$TMP/project"
  LEARNING="$PROJECT/.claude/skills/learning"
  mkdir -p "$LEARNING/scripts"
  cp "$BATS_TEST_DIRNAME/../.claude/skills/learning/scripts/session-end.sh" \
    "$LEARNING/scripts/session-end.sh"
  # observe.sh スタブ: 呼び出し引数を記録するだけ
  cat >"$LEARNING/scripts/observe.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$(cd "$(dirname "$0")/.." && pwd)/observe-invoked.txt"
STUB
  chmod +x "$LEARNING/scripts/session-end.sh" "$LEARNING/scripts/observe.sh"
  export LEARNING_SKILLS_SYNC=1
  unset LEARNING_SKILLS_OBSERVER 2>/dev/null || true
}

teardown() { rm -rf "$TMP"; }

# $1: user/assistant 行の合計数
make_transcript() {
  local n="$1" f="$TMP/transcript.jsonl" i
  : >"$f"
  for ((i = 0; i < n; i++)); do
    if ((i % 2 == 0)); then
      echo '{"type":"user","message":{"content":"hello"}}' >>"$f"
    else
      echo '{"type":"assistant","message":{"content":"hi"}}' >>"$f"
    fi
  done
  echo '{"type":"summary","summary":"noise"}' >>"$f"
  echo "$f"
}

# $1: transcript_path, $2: cwd
hook_input() {
  jq -n --arg t "$1" --arg c "$2" \
    '{hook_event_name:"SessionEnd", reason:"exit", transcript_path:$t, cwd:$c}'
}

run_hook() {
  run bash -c 'printf "%s" "$1" | "$2"' _ "$1" "$LEARNING/scripts/session-end.sh"
}

@test "happy path: observer が transcript と cwd を引数に起動される" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$LEARNING/observe-invoked.txt" ]
  [ "$(sed -n 1p "$LEARNING/observe-invoked.txt")" = "$t" ]
  [ "$(sed -n 2p "$LEARNING/observe-invoked.txt")" = "$PROJECT" ]
}

@test "happy path: epoch 秒が入ったロックファイルが作成される" {
  t=$(make_transcript 12)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ -f "$LEARNING/.lock" ]
  [[ "$(cat "$LEARNING/.lock")" =~ ^[0-9]+$ ]]
}

@test "再帰防止: LEARNING_SKILLS_OBSERVER=1 なら起動しない" {
  t=$(make_transcript 12)
  export LEARNING_SKILLS_OBSERVER=1
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "短小セッション: ターン数が10未満なら起動しない" {
  t=$(make_transcript 9)
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "プロジェクト外: cwd に .claude も CLAUDE.md もなければ起動しない" {
  t=$(make_transcript 12)
  mkdir -p "$TMP/plain"
  run_hook "$(hook_input "$t" "$TMP/plain")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "transcript が存在しなければ起動しない" {
  run_hook "$(hook_input "$TMP/no-such.jsonl" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "stdin が不正な JSON でも exit 0 で起動しない" {
  run bash -c 'echo "not json" | "$1"' _ "$LEARNING/scripts/session-end.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "新しいロックがあれば起動しない" {
  t=$(make_transcript 12)
  date +%s >"$LEARNING/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/observe-invoked.txt" ]
}

@test "stale ロック（30分超）は奪取して起動する" {
  t=$(make_transcript 12)
  echo "$(($(date +%s) - 1801))" >"$LEARNING/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "ロック内容が数値でなければ stale 扱いで起動する" {
  t=$(make_transcript 12)
  echo "garbage" >"$LEARNING/.lock"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
  [ -f "$LEARNING/observe-invoked.txt" ]
}

@test "observer がエラー終了しても hook は exit 0" {
  t=$(make_transcript 12)
  cat >"$LEARNING/scripts/observe.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$LEARNING/scripts/observe.sh"
  run_hook "$(hook_input "$t" "$PROJECT")"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bats tests/session_end.bats`
Expected: 全テスト FAIL（`session-end.sh` が存在せず setup の cp が失敗する）

- [ ] **Step 3: session-end.sh を実装**

`.claude/skills/learning/scripts/session-end.sh` を以下の内容で作成し、`chmod +x` する:

```bash
#!/usr/bin/env bash
# SessionEnd hook: セッション transcript の学習分析（observer）を起動する。
# 学習系の失敗はセッション終了を妨げてはならないため、常に exit 0 する。
set -u

MIN_TURNS="${LEARNING_SKILLS_MIN_TURNS:-10}"
LOCK_STALE_SECONDS=1800

main() {
  # 再帰防止: observer 自身の claude -p セッションでは何もしない
  [ "${LEARNING_SKILLS_OBSERVER:-}" = "1" ] && return 0

  local input transcript_path cwd
  input=$(cat) || return 0
  transcript_path=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null) || return 0
  cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || return 0
  { [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; } || return 0
  { [ -n "$cwd" ] && [ -d "$cwd" ]; } || return 0

  # プロジェクト外のセッションは学習対象外
  [ -d "$cwd/.claude" ] || [ -f "$cwd/CLAUDE.md" ] || return 0

  # 短小セッションには学習素材がない
  local turns
  turns=$(jq -r 'select(.type == "user" or .type == "assistant") | .type' \
    "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')
  [ "${turns:-0}" -ge "$MIN_TURNS" ] || return 0

  local script_dir base_dir lock_file now
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  base_dir=$(cd "$script_dir/.." && pwd)
  lock_file="$base_dir/.lock"
  now=$(date +%s)

  # 多重起動防止。observer 異常終了で学習が止まらないよう stale ロックは奪取する
  if [ -f "$lock_file" ]; then
    local ts age
    ts=$(cat "$lock_file" 2>/dev/null)
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    age=$((now - ts))
    [ "$age" -gt "$LOCK_STALE_SECONDS" ] || return 0
  fi
  echo "$now" >"$lock_file"

  mkdir -p "$base_dir/logs"
  if [ "${LEARNING_SKILLS_SYNC:-}" = "1" ]; then
    "$script_dir/observe.sh" "$transcript_path" "$cwd" \
      >>"$base_dir/logs/observer.log" 2>&1 || true
  else
    nohup "$script_dir/observe.sh" "$transcript_path" "$cwd" \
      >>"$base_dir/logs/observer.log" 2>&1 &
  fi
  return 0
}

main || true
exit 0
```

- [ ] **Step 4: テストが通ることを確認**

Run: `bats tests/session_end.bats`
Expected: `11 tests, 0 failures`

- [ ] **Step 5: コミット**

```bash
git add .claude/skills/learning/scripts/session-end.sh tests/session_end.bats
git commit -m "feat: SessionEnd hook のガード判定と observer 起動を実装

Claude-Session: https://claude.ai/code/session_01LWvko5t2KQ1Y3nhmSJSTcK"
```

---

### Task 2: observe.sh（observer 起動スクリプト）

**Files:**
- Create: `.claude/skills/learning/scripts/observe.sh`
- Test: `tests/observe.bats`

**Interfaces:**
- Consumes: 引数 `$1`=transcript_path, `$2`=project_dir（Task 1 の起動規約）、`../prompts/observer.md`（プレースホルダ `{{TRANSCRIPT_PATH}}` `{{INSTINCTS_DIR}}` `{{TODAY}}` を含むテキスト。実物は Task 3 で作成、テストではフィクスチャを使用）、`../.lock`（Task 1 が作成）
- Produces: `claude -p <prompt> --model <model> --allowedTools "Read,Write,Edit,Glob,Grep"` の呼び出し（環境変数 `LEARNING_SKILLS_OBSERVER=1` 付き）、終了時の `.lock` 削除、`instincts/` ディレクトリ作成

- [ ] **Step 1: 失敗するテストを書く**

`tests/observe.bats` を以下の内容で作成:

```bash
#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  LEARNING="$TMP/project/.claude/skills/learning"
  mkdir -p "$LEARNING/scripts" "$LEARNING/prompts" "$TMP/bin"
  cp "$BATS_TEST_DIRNAME/../.claude/skills/learning/scripts/observe.sh" \
    "$LEARNING/scripts/observe.sh"
  chmod +x "$LEARNING/scripts/observe.sh"
  # プロンプトのフィクスチャ（プレースホルダ置換を検証できる最小内容）
  printf 'T={{TRANSCRIPT_PATH}} I={{INSTINCTS_DIR}} D={{TODAY}}\n' \
    >"$LEARNING/prompts/observer.md"
  # claude スタブ: 引数と環境変数を記録する
  cat >"$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${STUB_DIR:?}/claude-args.txt"
echo "${LEARNING_SKILLS_OBSERVER:-unset}" >"${STUB_DIR:?}/claude-env.txt"
exit "${STUB_CLAUDE_EXIT:-0}"
STUB
  chmod +x "$TMP/bin/claude"
  export PATH="$TMP/bin:$PATH"
  export STUB_DIR="$TMP"
  echo '{"type":"user","message":{"content":"x"}}' >"$TMP/transcript.jsonl"
  date +%s >"$LEARNING/.lock"
}

teardown() { rm -rf "$TMP"; }

run_observe() {
  run "$LEARNING/scripts/observe.sh" "$TMP/transcript.jsonl" "$TMP/project"
}

# 記録された引数リストから、指定フラグの次の値を返す
arg_after() {
  awk -v flag="$1" '$0 == flag { getline; print; exit }' "$TMP/claude-args.txt"
}

@test "claude を -p 付き・既定モデル haiku で起動する" {
  run_observe
  [ "$status" -eq 0 ]
  grep -qx -- "-p" "$TMP/claude-args.txt"
  [ "$(arg_after --model)" = "haiku" ]
  [ "$(arg_after --allowedTools)" = "Read,Write,Edit,Glob,Grep" ]
}

@test "LEARNING_SKILLS_MODEL でモデルを上書きできる" {
  export LEARNING_SKILLS_MODEL=opus
  run_observe
  [ "$(arg_after --model)" = "opus" ]
}

@test "プロンプトのプレースホルダが実パスに置換される" {
  run_observe
  prompt="$(arg_after -p)"
  [[ "$prompt" == *"T=$TMP/transcript.jsonl"* ]]
  [[ "$prompt" == *"I=$LEARNING/instincts"* ]]
  [[ "$prompt" == *"D=$(date +%F)"* ]]
}

@test "claude は LEARNING_SKILLS_OBSERVER=1 の環境で起動される" {
  run_observe
  [ "$(cat "$TMP/claude-env.txt")" = "1" ]
}

@test "instincts ディレクトリが作成される" {
  run_observe
  [ -d "$LEARNING/instincts" ]
}

@test "成功時にロックが削除される" {
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/.lock" ]
}

@test "claude 失敗時もロックが削除されエラーがログに出る" {
  export STUB_CLAUDE_EXIT=1
  run_observe
  [ "$status" -eq 0 ]
  [ ! -f "$LEARNING/.lock" ]
  [[ "$output" == *"observer failed"* ]]
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bats tests/observe.bats`
Expected: 全テスト FAIL（`observe.sh` が存在せず setup の cp が失敗する）

- [ ] **Step 3: observe.sh を実装**

`.claude/skills/learning/scripts/observe.sh` を以下の内容で作成し、`chmod +x` する:

```bash
#!/usr/bin/env bash
# observer 起動スクリプト: transcript を claude -p で分析し Instinct を蓄積する。
# session-end.sh からバックグラウンドで起動される前提。stdout/stderr は
# 呼び出し元によって logs/observer.log にリダイレクトされる。
set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
base_dir=$(cd "$script_dir/.." && pwd)
lock_file="$base_dir/.lock"
trap 'rm -f "$lock_file"' EXIT

transcript_path="${1:?transcript path required}"
project_dir="${2:?project dir required}"

instincts_dir="$base_dir/instincts"
mkdir -p "$instincts_dir"

prompt=$(<"$base_dir/prompts/observer.md")
prompt="${prompt//\{\{TRANSCRIPT_PATH\}\}/$transcript_path}"
prompt="${prompt//\{\{INSTINCTS_DIR\}\}/$instincts_dir}"
prompt="${prompt//\{\{TODAY\}\}/$(date +%F)}"

model="${LEARNING_SKILLS_MODEL:-haiku}"

cd "$project_dir" || exit 0
if ! LEARNING_SKILLS_OBSERVER=1 claude -p "$prompt" --model "$model" \
    --allowedTools "Read,Write,Edit,Glob,Grep"; then
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] observer failed: transcript=$transcript_path"
fi
exit 0
```

- [ ] **Step 4: テストが通ることを確認**

Run: `bats tests/observe.bats`
Expected: `7 tests, 0 failures`

- [ ] **Step 5: 回帰確認とコミット**

Run: `bats tests/`
Expected: `18 tests, 0 failures`

```bash
git add .claude/skills/learning/scripts/observe.sh tests/observe.bats
git commit -m "feat: observer 起動スクリプトを実装

Claude-Session: https://claude.ai/code/session_01LWvko5t2KQ1Y3nhmSJSTcK"
```

---

### Task 3: observer プロンプトと .gitignore、手動検証スクリプト

**Files:**
- Create: `.claude/skills/learning/prompts/observer.md`
- Create: `.claude/skills/learning/.gitignore`
- Create: `tests/fixtures/sample-transcript.jsonl`
- Create: `tests/manual/verify-observer.sh`

**Interfaces:**
- Consumes: Task 2 のプレースホルダ規約（`{{TRANSCRIPT_PATH}}`, `{{INSTINCTS_DIR}}`, `{{TODAY}}`）
- Produces: Instinct ファイルの frontmatter スキーマ（Global Constraints 参照。Task 4 の `/learning` skill が読む）

- [ ] **Step 1: observer プロンプトを書く**

`.claude/skills/learning/prompts/observer.md` を以下の内容で作成:

````markdown
あなたは Claude Code セッションの観察者（observer）です。終了したセッションの transcript を分析し、再利用可能な知識（Instinct）を抽出・蓄積してください。応答は不要です。ツールでファイルを読み書きすることだけが仕事です。

## 入力

- transcript: `{{TRANSCRIPT_PATH}}`（JSONL 形式。1行1イベント。`type` が `user` / `assistant` の行が対話本体）
- Instinct 保存先: `{{INSTINCTS_DIR}}`
- 今日の日付: `{{TODAY}}`

## 手順

1. transcript を Read で読む（大きい場合は offset/limit で分割して全体を読む）
2. 次の3カテゴリに該当するパターンを抽出する:
   - `correction`: ユーザーが Claude の行動・方針を訂正した場面（「違う」「〜を使って」「〜はやめて」等の指示と、その後の適応）
   - `error-solution`: コマンド失敗・テスト失敗・エラーから解決に至った具体的手順
   - `workflow`: セッション内で繰り返された定型的な複数ステップの作業手順
3. `{{INSTINCTS_DIR}}` 内の既存 `.md` ファイルをすべて読む
4. 抽出した各候補を既存 Instinct と意味的に照合する（ファイル名や語句の一致ではなく「同じ教訓か」で判断）:
   - 同じ教訓の `status: active` があれば強化する。frontmatter の `confidence` に +0.2（上限 1.0）、`evidence_count` に +1、`updated` を `{{TODAY}}` に更新し、`# Evidence` に観察内容を1行追記する
   - 同じ教訓の `status: rejected` があれば何もしない（ユーザーが却下済み。再作成禁止）
   - 同じ教訓の `status: promoted` があれば何もしない（昇格先が真実源）
   - どれにも該当しなければ新規ファイルを作成する

## 新規 Instinct ファイルの形式

ファイル名は `<id>.md`（id は内容を表す英小文字ケバブケース）。

```markdown
---
id: <id>
type: <correction | error-solution | workflow>
status: active
confidence: 0.3
evidence_count: 1
promote_to: <rules | instructions | skill | agent>
created: {{TODAY}}
updated: {{TODAY}}
---

# Trigger
<この知識が適用される状況を1〜2文で>

# Action
<取るべき行動を具体的に>

# Evidence
- {{TODAY}}: <観察した事実の要約を1行で>
```

`promote_to` の推定基準:
- 方針・禁止事項・好み → `rules`
- 既存 skill（プロジェクトの `.claude/skills/` 配下）の作業中に起きたエラー解決 → `instructions`
- 反復される複数ステップの手順 → `skill`
- 独立したロールとして委譲可能な専門タスク → `agent`

## 抽出の基準

- このプロジェクトで再利用可能な教訓のみ。一般常識・一度きりの事象・セッション固有の文脈は除外する
- 同一セッション内で同じ教訓が複数回現れても、強化は1回だけ（confidence 加算は別セッションでの再観察を意味する）
- 確信の持てない曖昧な候補は作らない。偽陽性を混ぜるより取りこぼす方がよい
- 1回の分析で新規作成する Instinct は最大5件
- `{{INSTINCTS_DIR}}` の外にあるファイルを変更しない
````

- [ ] **Step 2: .gitignore を作成**

`.claude/skills/learning/.gitignore`:

```gitignore
instincts/
logs/
.lock
```

- [ ] **Step 3: フィクスチャ transcript を作成**

`tests/fixtures/sample-transcript.jsonl` を作成する。correction（pip→uv の訂正）と error-solution（テスト失敗→解決）を含む 12 ターン:

```jsonl
{"type":"user","message":{"content":"依存に requests を追加して"}}
{"type":"assistant","message":{"content":"pip install requests を実行します"}}
{"type":"user","message":{"content":"違う、このプロジェクトでは pip は使わない。uv add を使って"}}
{"type":"assistant","message":{"content":"uv add requests を実行しました"}}
{"type":"user","message":{"content":"テストを実行して"}}
{"type":"assistant","message":{"content":"pytest を実行したところ ModuleNotFoundError: No module named 'requests' で失敗しました"}}
{"type":"user","message":{"content":"原因を調べて直して"}}
{"type":"assistant","message":{"content":"uv sync を実行してから pytest を再実行したところ、全テストが通りました。uv add 後は uv sync が必要でした"}}
{"type":"user","message":{"content":"OK"}}
{"type":"assistant","message":{"content":"完了です"}}
{"type":"user","message":{"content":"コミットして"}}
{"type":"assistant","message":{"content":"コミットしました"}}
```

- [ ] **Step 4: 手動検証スクリプトを作成**

`tests/manual/verify-observer.sh` を以下の内容で作成し、`chmod +x` する（実 API を消費するため bats には含めない）:

```bash
#!/usr/bin/env bash
# observer プロンプトの受け入れ検証（実 API を消費する。手動実行専用）。
# 一時プロジェクトを作り、フィクスチャ transcript を実際に分析させて
# 期待する Instinct が生成されるかを確認する。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'echo "作業ディレクトリ: $work（確認後に手動で削除してください）"' EXIT

project="$work/project"
mkdir -p "$project/.claude"
cp -R "$repo_root/.claude/skills" "$project/.claude/skills"
rm -rf "$project/.claude/skills/learning/instincts" "$project/.claude/skills/learning/logs"

echo "=== observer を実行中（モデル: ${LEARNING_SKILLS_MODEL:-haiku}）==="
date +%s >"$project/.claude/skills/learning/.lock"
"$project/.claude/skills/learning/scripts/observe.sh" \
  "$repo_root/tests/fixtures/sample-transcript.jsonl" "$project"

echo "=== 生成された Instinct ==="
ls -la "$project/.claude/skills/learning/instincts/" || true
for f in "$project/.claude/skills/learning/instincts/"*.md; do
  echo "--- $f ---"
  cat "$f"
done

cat <<'CHECKLIST'

=== 受け入れチェックリスト（目視確認） ===
[ ] correction 型の Instinct が生成されている（pip ではなく uv を使う）
[ ] error-solution 型の Instinct が生成されている（uv add 後に uv sync）
[ ] 各ファイルの frontmatter に id/type/status/confidence/evidence_count/promote_to/created/updated が揃っている
[ ] confidence が 0.3、status が active である
[ ] 無関係・自明な Instinct が生成されていない
[ ] もう一度このスクリプトの observe.sh 実行部分だけ再実行すると、新規作成ではなく既存の confidence が 0.5 に強化される
CHECKLIST
```

- [ ] **Step 5: 回帰確認とコミット**

Run: `bats tests/`
Expected: `18 tests, 0 failures`（本タスクの成果物は bats 対象外。既存が壊れていないことの確認）

```bash
git add .claude/skills/learning/prompts/observer.md \
  .claude/skills/learning/.gitignore \
  tests/fixtures/sample-transcript.jsonl tests/manual/verify-observer.sh
git commit -m "feat: observer プロンプトと手動検証スクリプトを追加

Claude-Session: https://claude.ai/code/session_01LWvko5t2KQ1Y3nhmSJSTcK"
```

---

### Task 4: /learning skill（status / review サブコマンド）

**Files:**
- Create: `.claude/skills/learning/SKILL.md`

**Interfaces:**
- Consumes: Task 3 の Instinct frontmatter スキーマ（`instincts/*.md`）
- Produces: `/learning status` と `/learning review` のユーザー向け動作。review 承認時の昇格先ファイル編集と frontmatter 更新（`status: promoted` + `promoted_to`）

- [ ] **Step 1: SKILL.md を書く**

`.claude/skills/learning/SKILL.md` を以下の内容で作成:

````markdown
---
name: learning
description: セッション観察で蓄積された Instinct の確認と昇格を行う。「/learning status」「instinct の一覧」「学習状況を見せて」で status を、「/learning review」「instinct を昇格」「学習内容をレビュー」で review を実行する。
---

# learning - Instinct の管理と昇格

蓄積された Instinct（`.claude/skills/learning/instincts/*.md`）を確認し、信頼度が閾値に達したものをユーザー承認のもとで昇格させる skill。サブコマンドは引数で指定される（既定は `status`）。

## 共通の前提

- Instinct ファイルの frontmatter: `id`, `type`(correction|error-solution|workflow), `status`(active|promoted|rejected), `confidence`, `evidence_count`, `promote_to`(rules|instructions|skill|agent), `created`, `updated`
- 昇格資格: `status: active` かつ `confidence >= 0.7`
- instincts ディレクトリが存在しない・空の場合は「まだ Instinct が蓄積されていません。セッションを重ねると自動的に蓄積されます」と report して終了する

## /learning status

読み取り専用。`instincts/*.md` の frontmatter を集めて次の形式で表示する:

| id | type | confidence | evidence | status |
|---|---|---|---|---|
| use-uv-not-pip | correction | 0.7 | 3 | active |

表の後に「昇格資格あり: N 件（/learning review で提案を確認できます）」を添える。ファイル編集は一切しない。

## /learning review

1. `status: active` かつ `confidence >= 0.7` の Instinct を収集する。0 件なら「昇格資格のある Instinct はありません」と現在の最高 confidence を添えて終了する
2. 各 Instinct について昇格先を決定する。frontmatter の `promote_to` を初期値とし、内容から見て不適切なら変更する:
   - `rules` → プロジェクトの `CLAUDE.md` に規則として追記（該当セクションがなければ末尾に追加）
   - `instructions` → 関連する既存 skill の `SKILL.md` にトラブルシュート・注意点として追記
   - `skill` → 既存 skill の手順改善、または `.claude/skills/<id>/SKILL.md` の新規作成
   - `agent` → `.claude/agents/<id>.md` としてサブエージェント定義を新規作成
3. 昇格先ファイルの現状を読み、具体的な変更案（diff 形式または新規ファイル全文）を作る
4. **1件ずつ** AskUserQuestion で提示し、承認 / 却下 / 保留 を確認する。質問文には Instinct の Trigger/Action、evidence_count、変更案の要約を含める
   - **承認** → 変更を適用し、Instinct の frontmatter を `status: promoted` に更新、`promoted_to: <適用先パス>` を追記する
   - **却下** → `status: rejected` に更新する（observer が同種を再作成しなくなる）
   - **保留** → 何も変更しない（次回の review に持ち越し）
5. 全件処理後、適用結果のサマリ（承認/却下/保留の件数と適用先パス）を表示する

## 制約

- ユーザーの承認なしに昇格先ファイルを変更しない
- 一度の承認で複数の Instinct をまとめて適用しない（1件ずつ確認する）
- instincts ファイルの confidence や evidence を手動で書き換えない（それは observer の仕事）
````

- [ ] **Step 2: フィクスチャで status 経路を手動確認**

一時プロジェクトを作って動作確認する:

```bash
work=$(mktemp -d) && mkdir -p "$work/proj/.claude" && cp -R .claude/skills "$work/proj/.claude/skills"
mkdir -p "$work/proj/.claude/skills/learning/instincts"
cat >"$work/proj/.claude/skills/learning/instincts/use-uv-not-pip.md" <<'EOF'
---
id: use-uv-not-pip
type: correction
status: active
confidence: 0.7
evidence_count: 3
promote_to: rules
created: 2026-07-10
updated: 2026-07-12
---

# Trigger
Python パッケージを追加するとき

# Action
pip install ではなく uv add を使い、直後に uv sync を実行する

# Evidence
- 2026-07-10: pip install 実行後にユーザーが「uv add を使って」と訂正
- 2026-07-11: 別セッションで同様の訂正
- 2026-07-12: 別セッションで同様の訂正
EOF
cd "$work/proj" && claude
```

起動した対話セッションで `/learning status` を実行し、確認後に `exit` する。

Expected: 表に `use-uv-not-pip / correction / 0.7 / 3 / active` が表示され、「昇格資格あり: 1 件」と出る。ファイルは変更されない。

- [ ] **Step 3: review の3経路（承認/却下/保留）を手動確認**

同じ一時プロジェクトの対話セッションで `/learning review` を実行する。

Expected:
- 承認を選ぶと `CLAUDE.md` に uv の規則が追記され、instinct が `status: promoted` + `promoted_to` 付きに更新される
- （instinct を active に戻してから再実行し）却下を選ぶと `status: rejected` になり CLAUDE.md は変更されない
- （同様に戻してから）保留を選ぶと何も変更されない

3経路を確認したら `rm -rf "$work"` で掃除する。

- [ ] **Step 4: コミット**

```bash
git add .claude/skills/learning/SKILL.md
git commit -m "feat: /learning skill（status/review）を追加

Claude-Session: https://claude.ai/code/session_01LWvko5t2KQ1Y3nhmSJSTcK"
```

---

### Task 5: hook 登録（dogfooding）と README

**Files:**
- Create: `.claude/settings.json`
- Create: `README.md`

**Interfaces:**
- Consumes: Task 1 の `session-end.sh`（`$CLAUDE_PROJECT_DIR` 経由で参照）
- Produces: このリポジトリ自体での SessionEnd hook 稼働、導入手順ドキュメント

- [ ] **Step 1: .claude/settings.json を作成**

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

- [ ] **Step 2: README.md を作成**

````markdown
# learning-skills

Claude Code のセッションを自動観察し、行動パターンを Instinct として蓄積、承認制で CLAUDE.md / skill / agent に昇格させる自己完結型 skill。

## 仕組み

```
SessionEnd hook → ガード判定 → claude -p (haiku) で transcript を分析
  → .claude/skills/learning/instincts/*.md に蓄積（confidence 0.3 から開始）
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
````

- [ ] **Step 3: 全テストと E2E 確認**

Run: `bats tests/`
Expected: `18 tests, 0 failures`

E2E（このリポジトリで hook が発火することの確認）: このリポジトリで `claude` の対話セッションを開いて 10 ターン以上やりとりして終了し、`.claude/skills/learning/logs/observer.log` が生成される（または短ければ何も起きない）ことを確認する。

- [ ] **Step 4: コミット**

```bash
git add .claude/settings.json README.md
git commit -m "feat: SessionEnd hook 登録（dogfooding）と README を追加

Claude-Session: https://claude.ai/code/session_01LWvko5t2KQ1Y3nhmSJSTcK"
```
