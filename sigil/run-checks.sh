#!/usr/bin/env bash

set -u

SIGIL_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EMPTY_FILE=""
FAILURES=0

BUILD_TIMEOUT_SECS=600
CASE_TIMEOUT_SECS=30
BENCH_TIMEOUT_SECS=90
BENCH_LIMIT_SECS=60

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

# Kill the command if it runs longer than the given number of seconds.
# Implemented with perl because macOS has no timeout(1) by default.
with_timeout() {
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' "$@"
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

LOCKED=""
if [ -f "$CANDIDATE_DIR/Cargo.lock" ]; then
  pass "Cargo.lock present"
  LOCKED="--locked"
else
  fail "Cargo.lock present (commit a lockfile; builds run with --locked)"
fi

if (cd "$CANDIDATE_DIR" && with_timeout "$BUILD_TIMEOUT_SECS" cargo build --release $LOCKED >/dev/null); then
  if [ -x "$BIN" ]; then
    pass "cargo build --release"
  else
    fail "cargo build --release (target/release/sigil missing)"
  fi
else
  fail "cargo build --release"
fi

if cargo +1.96.0 --version >/dev/null 2>&1; then
  if (cd "$CANDIDATE_DIR" && with_timeout "$BUILD_TIMEOUT_SECS" cargo +1.96.0 build --release $LOCKED >/dev/null); then
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

  with_timeout "$CASE_TIMEOUT_SECS" "$@" >"$stdout_file" 2>"$stderr_file"
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

# For checks whose output includes an implementation-defined :message string:
# match a pattern on one stream and require the other stream to be empty.
run_grep_case() {
  label=$1
  expected_status=$2
  pattern_stream=$3
  pattern=$4
  empty_stream=$5
  shift 5

  safe=$(safe_name "$label")
  stdout_file="$TMP/$safe.stdout"
  stderr_file="$TMP/$safe.stderr"

  with_timeout "$CASE_TIMEOUT_SECS" "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?

  ok=1
  if [ "$status" -ne "$expected_status" ]; then
    ok=0
  fi
  if ! grep -Eq "$pattern" "$TMP/$safe.$pattern_stream"; then
    ok=0
  fi
  if [ "$empty_stream" != "none" ] && [ -s "$TMP/$safe.$empty_stream" ]; then
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

    { TIMEFORMAT=%R; time with_timeout "$BENCH_TIMEOUT_SECS" "$BIN" "$SIGIL_DIR/bench/fib.sigil" >"$stdout_file" 2>"$stderr_file" </dev/null; } 2>"$time_file"
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

  if [ "$ok" -eq 1 ] && [ "$best" = "" ]; then
    ok=0
  fi
  if [ "$ok" -eq 1 ] && awk -v best="$best" -v limit="$BENCH_LIMIT_SECS" 'BEGIN { exit !(best + 0 > limit + 0) }'; then
    fail "$label best=${best}s exceeds ${BENCH_LIMIT_SECS}s limit"
    return
  fi

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
  fail "tests/repl-eof-session.txt (binary unavailable)"
  fail "tests/invalid-utf8.sigil (binary unavailable)"
  fail "randomized args (binary unavailable)"
  fail "randomized script (binary unavailable)"
  fail "randomized repl (binary unavailable)"
  fail "bench/fib.sigil (binary unavailable)"
  finish
fi

run_case "tests/tests.sigil" 0 \
  "$SIGIL_DIR/tests/expected-output.txt" "$EMPTY_FILE" \
  "$BIN" "$SIGIL_DIR/tests/tests.sigil" </dev/null

run_case "tests/fail.sigil" 1 \
  "$SIGIL_DIR/tests/fail-expected-output.txt" "$SIGIL_DIR/tests/fail-expected-stderr.txt" \
  "$BIN" "$SIGIL_DIR/tests/fail.sigil" </dev/null

run_case "tests/args.sigil with args" 0 \
  "$SIGIL_DIR/tests/args-expected-output.txt" "$EMPTY_FILE" \
  "$BIN" "$SIGIL_DIR/tests/args.sigil" a b c </dev/null

run_case "tests/args.sigil empty args" 0 \
  "$SIGIL_DIR/tests/args-empty-expected-output.txt" "$EMPTY_FILE" \
  "$BIN" "$SIGIL_DIR/tests/args.sigil" </dev/null

run_case "tests/repl-session.txt" 0 \
  "$SIGIL_DIR/tests/repl-expected.txt" "$EMPTY_FILE" \
  "$BIN" < "$SIGIL_DIR/tests/repl-session.txt"

# The :message text of built-in errors is implementation-defined, so these two
# match on :type with a pattern instead of an exact diff.
run_grep_case "tests/repl-eof-session.txt" 0 \
  stdout '^user=> error: .*:error/reader' stderr \
  "$BIN" < "$SIGIL_DIR/tests/repl-eof-session.txt"

run_grep_case "tests/invalid-utf8.sigil" 1 \
  stderr '^error: .*:error/reader' stdout \
  "$BIN" "$SIGIL_DIR/tests/invalid-utf8.sigil" </dev/null

# Randomized checks: regenerated on every run so expected output cannot be
# replayed from a recording of the fixed fixtures.
RAND_A=$((RANDOM % 9000 + 1000))
RAND_B=$((RANDOM % 9000 + 1000))
RAND_T1="r$((RANDOM % 90000 + 10000))"
RAND_T2="r$((RANDOM % 90000 + 10000))"

printf '["%s" "%s"]\n' "$RAND_T1" "$RAND_T2" > "$TMP/rand-args.expected"
run_case "randomized args" 0 \
  "$TMP/rand-args.expected" "$EMPTY_FILE" \
  "$BIN" "$SIGIL_DIR/tests/args.sigil" "$RAND_T1" "$RAND_T2" </dev/null

{
  printf '(ns gen-test)\n'
  printf '(println "sum =" (+ %d %d))\n' "$RAND_A" "$RAND_B"
  printf '(println "product =" (* %d %d))\n' "$RAND_A" "$RAND_B"
  printf '(println "diff =" (- %d %d))\n' "$RAND_A" "$RAND_B"
} > "$TMP/rand-script.sigil"
{
  printf 'sum = %d\n' "$((RAND_A + RAND_B))"
  printf 'product = %d\n' "$((RAND_A * RAND_B))"
  printf 'diff = %d\n' "$((RAND_A - RAND_B))"
} > "$TMP/rand-script.expected"
run_case "randomized script" 0 \
  "$TMP/rand-script.expected" "$EMPTY_FILE" \
  "$BIN" "$TMP/rand-script.sigil" </dev/null

{
  printf '(* %d %d)\n' "$RAND_A" "$RAND_B"
  printf '(+ %d 1)\n' "$RAND_B"
} > "$TMP/rand-repl.session"
{
  printf 'user=> %d\n' "$((RAND_A * RAND_B))"
  printf 'user=> %d\n' "$((RAND_B + 1))"
} > "$TMP/rand-repl.expected"
run_case "randomized repl" 0 \
  "$TMP/rand-repl.expected" "$EMPTY_FILE" \
  "$BIN" < "$TMP/rand-repl.session"

run_bench
finish
