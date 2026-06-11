# Instructions

## Goal

Build an interpreter in Rust that follows spec.md.

The interpreter should provide a single binary, e.g. `sigil`, with the following functionality:

1. REPL mode

`sigil` (no args) starts a REPL

REPL starts in `user` namespace

Prompt with `<current-namespace>=> `; the initial prompt is exactly `user=> `

Reads one form at a time, evaluates, prints result

Prompts are written to stdout even when stdin is not a TTY. When stdin is
piped, bypass the interactive line editor but keep the exact same prompt and
result/error output behavior.

Prints exceptions in the stable format defined by spec.md

Exit on EOF (Ctrl-D) with status 0, without printing a further prompt (see
spec.md §14)

2. Script mode

```
sigil path/to/file.sigil [args...]
```

Loads file, evaluates top-level forms sequentially

Provide access to CLI args through the binding `*command-line-args*`

With no args after the script path, `*command-line-args*` is `[]`.

## Validation

### Conformance

`sigil` should be capable of evaluating every part of the language as given in the spec.

From this `sigil/` directory, the full validation command is:

```
./run-checks.sh path/to/candidate/repo
```

The runner builds the candidate with `cargo build --release --locked` (a
committed `Cargo.lock` is required), runs an MSRV build with the toolchain
pinned in `rust-toolchain.toml` when that toolchain is installed, executes
all fixtures below, reports one PASS/FAIL line per check, and exits nonzero
if any required check fails.

Every fixture runs under a 30-second timeout (90 seconds per benchmark run);
a hang is a failure. In addition to the fixed fixtures, the runner generates
randomized checks on every invocation — a script with fresh random operands,
random CLI args, and a randomized REPL session — so the interpreter must
compute its output; replaying recorded fixture output will not pass.

Manual validation uses `BIN=path/to/candidate/repo/target/release/sigil` and
the following exact checks from this `sigil/` directory:

```
$BIN tests/tests.sigil > /tmp/sigil-tests.out 2> /tmp/sigil-tests.err
test $? -eq 0
diff -u tests/expected-output.txt /tmp/sigil-tests.out
test ! -s /tmp/sigil-tests.err
```

```
$BIN tests/fail.sigil > /tmp/sigil-fail.out 2> /tmp/sigil-fail.err
test $? -eq 1
diff -u tests/fail-expected-output.txt /tmp/sigil-fail.out
diff -u tests/fail-expected-stderr.txt /tmp/sigil-fail.err
```

```
$BIN tests/args.sigil a b c > /tmp/sigil-args.out 2> /tmp/sigil-args.err
test $? -eq 0
diff -u tests/args-expected-output.txt /tmp/sigil-args.out
test ! -s /tmp/sigil-args.err

$BIN tests/args.sigil > /tmp/sigil-args-empty.out 2> /tmp/sigil-args-empty.err
test $? -eq 0
diff -u tests/args-empty-expected-output.txt /tmp/sigil-args-empty.out
test ! -s /tmp/sigil-args-empty.err
```

```
$BIN < tests/repl-session.txt > /tmp/sigil-repl.out 2> /tmp/sigil-repl.err
test $? -eq 0
diff -u tests/repl-expected.txt /tmp/sigil-repl.out
test ! -s /tmp/sigil-repl.err
```

Two checks match on the error `:type` with a pattern instead of an exact diff,
because the `:message` text of built-in errors is implementation-defined:

```
$BIN < tests/repl-eof-session.txt > /tmp/sigil-repl-eof.out 2> /tmp/sigil-repl-eof.err
test $? -eq 0
grep -E '^user=> error: .*:error/reader' /tmp/sigil-repl-eof.out
test ! -s /tmp/sigil-repl-eof.err
```

```
$BIN tests/invalid-utf8.sigil > /tmp/sigil-utf8.out 2> /tmp/sigil-utf8.err
test $? -eq 1
grep -E '^error: .*:error/reader' /tmp/sigil-utf8.err
test ! -s /tmp/sigil-utf8.out
```

### Performance

Time `bench/fib.sigil` before and after optimization work. The benchmark
stdout must exactly match `bench/expected-output.txt`; run it three
times and report the best timing, the timing command, before/after
measurements, and the lowest-hanging performance fix or fixes you made.

The runner fails the benchmark check if the best of three runs exceeds 60
seconds; each individual run is killed after 90 seconds.

## Implementation notes

* Keep code simple. Do not add unnecessary functions or variables.

* Keep dependencies minimal, but use popular ones if they expedite implementation (e.g. the persistent data structures).

* Commit `Cargo.lock`; the validation runner builds with `--locked`.

* The name of the package itself can just be `sigil`.

* Use Rust 2021 edition. The minimum supported Rust version is the toolchain pinned in `rust-toolchain.toml`.

* Use persistent data structures for `list`, `vector`, `hash-map`, and `hash-set` types.

* The `core` namespace MUST only contain the Vars named by the spec's Core
  Required Functions section plus spec-defined runtime Vars such as
  `*command-line-args*`. Special forms are recognized from the spec's Special
  Forms list and are not core Vars.

* The REPL should have history and Emacs like keybindings for navigation at the prompt.

* Use multiple files, with related concerns in specific files, e.g. the reader is separate from the evaluator, with a separate Cargo bin for the binary with logic for the REPL and Script modes.

* Make a self-contained Rust repo under `result/YY-MM-DD-HH-MM-GITCOMMIT`,
  where `YY-MM-DD-HH-MM` is the zero-padded UTC timestamp formatted with
  `%y-%m-%d-%H-%M`, and `GITCOMMIT` is the short commit hash of this repo.

* There may be other attempts under `result/`; do NOT reference them in your own work.

* Take notes as you go under the package root `notes/*.md`, so others can follow your thought process.
