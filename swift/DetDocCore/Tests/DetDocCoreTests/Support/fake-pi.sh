#!/usr/bin/env bash
# Minimal fake `pi --mode rpc` for PiProcessTransport tests.
# Ignores command contents; on the first `prompt` command, emits a canned plan and exits.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while IFS= read -r line; do
  case "$line" in
    *'"type":"prompt"'*)
      cat "$here/fake-pi-plan.jsonl"
      exit 0
      ;;
  esac
done
