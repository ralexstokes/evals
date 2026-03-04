# Instructions

## Goal

Build an interpreter in Rust that follows spec.md.

Make a self-contained Rust repo under `sigil-YY-MM-DD-HH-MM` where Y, M and D are the date, and H and M are the current time in UTC.

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

3. Validation

`sigil` should be capable of evaluating every part of the language as given in the spec.

`sigil` should be able to run the tests in `tests/tests.sigil` with no error.

## Implementation notes

* The `core` namespace MUST only contain the names in the spec and no others.

* Use multiple files, with related concerns in specific files, e.g. the reader is separate from the evaluator, with a separate Cargo bin for the binary with logic for the REPL and Script modes.
