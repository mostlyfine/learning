#!/usr/bin/env bash
# 呼び出し元スクリプトのディレクトリから plugin root（1階層上）を解決する

resolve_plugin_root() {
  (cd "$1/.." && pwd)
}
