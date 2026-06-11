#!/usr/bin/env bash

set -u

SIGIL_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EMPTY_FILE=""
FAILURES=0

usage() {
  echo "usage: $0 PATH_TO_CANDIDATE_REPO" >&2
}

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

warn() {
  printf 'WARN %s\n' "$1"
}

safe_name() {
  printf '%s' "$1" | tr ' /' '__'
}

finish() {
  if [ "$FAILURES" -eq 0 ]; then
    echo "PASS all checks"
    exit 0
  fi

  printf 'FAIL %s check(s)\n' "$FAILURES"
  exit 1
}

if [ "${1:-}" = "" ]; then
  usage
  exit 2
fi

if [ ! -d "$1" ]; then
  echo "candidate path is not a directory: $1" >&2
  exit 2
fi

case "$1" in
  /*) CANDIDATE_DIR=$1 ;;
  *) CANDIDATE_DIR=$PWD/$1 ;;
esac

TMP_ROOT=${TMPDIR:-/tmp}
TMP=$(mktemp -d "$TMP_ROOT/sigil-checks.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT
EMPTY_FILE="$TMP/empty"
: > "$EMPTY_FILE"

BIN="$CANDIDATE_DIR/target/release/sigil"

if (cd "$CANDIDATE_DIR" && cargo build --release >/dev/null); then
  if [ -x "$BIN" ]; then
    pass "cargo build --release"
  else
    fail "cargo build --release (target/release/sigil missing)"
  fi
else
  fail "cargo build --release"
fi

if cargo +1.96.0 --version >/dev/null 2>&1; then
  if (cd "$CANDIDATE_DIR" && cargo +1.96.0 build --release >/dev/null); then
    pass "cargo +1.96.0 build --release"
  else
    fail "cargo +1.96.0 build --release"
  fi
else
  warn "cargo +1.96.0 unavailable; skipped MSRV check"
fi

run_case() {
  label=$1
  expected_status=$2
  expected_stdout=$3
  expected_stderr=$4
  shift 4

  safe=$(safe_name "$label")
  stdout_file="$TMP/$safe.stdout"
  stderr_file="$TMP/$safe.stderr"
  stdout_diff="$TMP/$safe.stdout.diff"
  stderr_diff="$TMP/$safe.stderr.diff"

  "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?

  ok=1
  if [ "$status" -ne "$expected_status" ]; then
    ok=0
  fi
  if ! diff -u "$expected_stdout" "$stdout_file" >"$stdout_diff"; then
    ok=0
  fi
  if ! diff -u "$expected_stderr" "$stderr_file" >"$stderr_diff"; then
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    pass "$label"
  else
    fail "$label (status=$status, see $TMP)"
  fi
}

run_bench() {
  label="benchmark"
  expected_stdout="$SIGIL_DIR/bench/expected-output.txt"
  best=""
  ok=1

  for run in 1 2 3; do
    stdout_file="$TMP/bench.$run.stdout"
    stderr_file="$TMP/bench.$run.stderr"
    time_file="$TMP/bench.$run.time"
    stdout_diff="$TMP/bench.$run.stdout.diff"
    stderr_diff="$TMP/bench.$run.stderr.diff"

    { TIMEFORMAT=%R; time "$BIN" "$SIGIL_DIR/bench/fib.sigil" >"$stdout_file" 2>"$stderr_file"; } 2>"$time_file"
    status=$?
    elapsed=$(sed -n '1p' "$time_file")

    if [ "$status" -ne 0 ]; then
      ok=0
    fi
    if ! diff -u "$expected_stdout" "$stdout_file" >"$stdout_diff"; then
      ok=0
    fi
    if ! diff -u "$EMPTY_FILE" "$stderr_file" >"$stderr_diff"; then
      ok=0
    fi
    if [ "$elapsed" != "" ]; then
      if [ "$best" = "" ]; then
        best=$elapsed
      else
        best=$(awk -v best="$best" -v elapsed="$elapsed" 'BEGIN { if (elapsed + 0 < best + 0) print elapsed; else print best }')
      fi
    fi
  done

  if [ "$ok" -eq 1 ]; then
    pass "$label best=${best}s"
  else
    fail "$label (see $TMP)"
  fi
}

if [ ! -x "$BIN" ]; then
  fail "tests/tests.sigil (binary unavailable)"
  fail "tests/fail.sigil (binary unavailable)"
  fail "tests/args.sigil with args (binary unavailable)"
  fail "tests/args.sigil empty args (binary unavailable)"
  fail "tests/repl-session.txt (binary unavailable)"
  fail "bench/fib.sigil (binary unavailable)"
  finish
fi

run_case "tests/tests.sigil" 0 \
  "$SIGIL_DIR/tests/expected-output.txt" "$EMPTY_FILE" \
  "$BIN" "$SIGIL_DIR/tests/tests.sigil"

run_case "tests/fail.sigil" 1 \
  "$SIGIL_DIR/tests/fail-expected-output.txt" "$SIGIL_DIR/tests/fail-expected-stderr.txt" \
  "$BIN" "$SIGIL_DIR/tests/fail.sigil"

run_case "tests/args.sigil with args" 0 \
  "$SIGIL_DIR/tests/args-expected-output.txt" "$EMPTY_FILE" \
  "$BIN" "$SIGIL_DIR/tests/args.sigil" a b c

run_case "tests/args.sigil empty args" 0 \
  "$SIGIL_DIR/tests/args-empty-expected-output.txt" "$EMPTY_FILE" \
  "$BIN" "$SIGIL_DIR/tests/args.sigil"

run_case "tests/repl-session.txt" 0 \
  "$SIGIL_DIR/tests/repl-expected.txt" "$EMPTY_FILE" \
  "$BIN" < "$SIGIL_DIR/tests/repl-session.txt"

run_bench
finish
