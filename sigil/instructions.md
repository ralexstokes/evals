# Instructions

## Goal

Build an interpreter in Rust that follows spec.md.

The interpreter should provide a single binary, e.g. `sigil`, with the following functionality:

1. REPL mode

`sigil` (no args) starts a REPL

REPL starts in `user` namespace

Reads one form at a time, evaluates, prints result

Prints exceptions in a stable, test-friendly way

Exit on EOF (Ctrl-D)

2. Script mode

```
sigil path/to/file.sigil [args...]
```

Loads file, evaluates top-level forms sequentially

Provide access to CLI args through the binding `*command-line-args*`

## Validation

### Conformance

`sigil` should be capable of evaluating every part of the language as given in the spec.

`sigil` should be able to run the tests in `tests/tests.sigil` with no error.

### Performance

Find the lowest-hanging fruit(s) in terms of performance and fix those.

## Implementation notes

* Keep code simple. Do not add unnecessary functions or variables.

* Keep dependencies minimal, but use popular ones if they expedite implementation (e.g. the persistent data structures).

* The name of the package itself can just be `sigil`.

* Use persistent data structures for `list`, `vector`, `hash-map`, and `hash-set` types.

* The `core` namespace MUST only contain the names in the spec and no others.

* The REPL should have history and Emacs like keybindings for navigation at the prompt.

* Use multiple files, with related concerns in specific files, e.g. the reader is separate from the evaluator, with a separate Cargo bin for the binary with logic for the REPL and Script modes.

* Make a self-contained Rust repo under `result/YY-MM-DD-HH-MM-GITCOMMIT` where Y, M, D, H, and M are the date/time in UTC, and GITCOMMIT is the short commit hash of this repo.

* There may be other attempts under `result/`; do NOT reference them in your own work.

* Take notes as you go under the package root `notes/*.md`, so others can follow your thought process.
