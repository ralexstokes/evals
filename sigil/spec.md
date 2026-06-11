# Sigil Language Specification v0.1

Sigil is a Clojure-like language with a reduced feature set and precisely defined semantics. This specification is normative.

Normative keywords: **MUST**, **MUST NOT**, **SHOULD**, **MAY**.

## Table of Contents

* [1. Source Text and Encoding](#1-source-text-and-encoding)
* [2. Reader (Surface Syntax)](#2-reader-surface-syntax)
* [3. Runtime Model](#3-runtime-model)
* [4. Equality and Hashing](#4-equality-and-hashing)
* [5. Numeric Model](#5-numeric-model)
* [6. Namespaces and Vars](#6-namespaces-and-vars)
* [7. Lexical Environments and Destructuring](#7-lexical-environments-and-destructuring)
* [8. Evaluation](#8-evaluation)
* [9. Special Forms](#9-special-forms)
* [10. Macro System](#10-macro-system)
* [11. Syntax-Quote](#11-syntax-quote)
* [12. Core Required Functions](#12-core-required-functions)
* [13. Atoms](#13-atoms)
* [14. Errors and Program Execution](#14-errors-and-program-execution)

---

# 1. Source Text and Encoding

* Sigil source text MUST be decoded from bytes using **UTF-8**.
* Invalid UTF-8 input MUST produce a reader error.
* A Sigil string value is a finite sequence of Unicode scalar values.
* When printing program text to a byte sink, output MUST be encoded as UTF-8.

---

# 2. Reader (Surface Syntax)

## 2.1 Separators and Comments

* Whitespace and commas `,` are separators.
* `;` begins a comment extending to end of line.
* `#_` discards exactly one complete form at read time.

---

## 2.2 Literals and Forms

### 2.2.1 Scalars

* `nil`, `true`, `false`
* Integers: arbitrary precision decimal, optional leading sign.
* Floats: decimal with dot and/or exponent (`e`/`E`), IEEE-754 double.
* Non-finite doubles: `##NaN`, `##Inf`, `##-Inf`.
* Ratios: `a/b` where `a`, `b` are integers and `b ≠ 0`.

  * MUST normalize to lowest terms.
  * Denominator MUST be positive.
  * The reader MUST accept signs on either side of `/`; for example, `1/-2`
    reads and normalizes to `-1/2`.

### 2.2.2 Strings

Delimited by `"`.
Supported escapes:

* `\n`, `\t`, `\\`, `\"`
* `\uXXXX` (4 hex digits)

Invalid escape → reader error. A `\uXXXX` escape in the surrogate range
`D800` through `DFFF` MUST produce a reader error.

### 2.2.3 Characters

* `\c`
* `\newline`, `\space`, `\tab`
* `\uXXXX`

Invalid form → reader error. A `\uXXXX` character in the surrogate range
`D800` through `DFFF` MUST produce a reader error.

---

### 2.2.4 Symbols

Token form: `name` or `ns/name`.

Symbols are not resolved at read time.

---

### 2.2.5 Keywords

* `:a`
* `:ns/a`
* `::a`
* `::alias/a`

Auto-resolution rules:

* `::a` resolves to keyword with namespace = current namespace.
* `::alias/a` resolves using current namespace alias map.
* Unknown alias → reader error.

Auto-resolution occurs at read time.

---

### 2.2.6 Collections

* List: `(a b c)`
* Vector: `[a b c]`
* Map: `{k v ...}` (even number of forms required)
* Set: `#{a b c}`

Map duplicate keys → last wins.
Set duplicates collapse.

---

## 2.3 Reader Macros

| Syntax   | Expands To       |
| -------- | ---------------- |
| `'x`     | `(quote x)`      |
| `` `x `` | syntax-quote     |
| `~x`     | unquote          |
| `~@x`    | unquote-splicing |
| `@x`     | `(deref x)`      |
| `^m x`   | metadata         |
| `#( … )` | fn literal       |
| `#{ … }` | set literal      |
| `#'sym`  | `(var sym)`      |
| `#_`     | discard          |

Any other `#` dispatch is an error. The non-finite double tokens `##NaN`,
`##Inf`, and `##-Inf` are scalar literals, not dispatch macros.

---

### 2.3.1 Function Literals

`#(form)` reads as `(fn* [params...] form)` with implicit parameters derived
from placeholder symbols in `form`.

* `%` is equivalent to `%1`.
* `%N`, where `N` is a positive decimal integer, names the Nth positional
  argument.
* `%&` names the rest argument.
* The fixed arity is the highest `%N` used. If no `%N` or `%` placeholder is
  used, the fixed arity is zero.
* If `%&` is used, the generated `fn*` is variadic.
* A nested `#(...)` inside another `#(...)` is a reader error.

Reader-generated parameter symbols MUST NOT capture or conflict with user
symbols in the function body.

---

### 2.3.2 Metadata Reader Syntax

`^m x` attaches metadata to `x`.

* `^{...}` uses the map as metadata.
* `^:kw` is equivalent to `^{:kw true}`.
* `^sym` is equivalent to `^{:tag sym}`.
* Any other metadata form is a reader error.

Multiple metadata prefixes are allowed and stack right-to-left. Metadata maps
MUST be merged in application order; later applications replace earlier values
for duplicate keys.

---

# 3. Runtime Model

## 3.1 Value Types

Sigil values:

* nil
* boolean
* bigint
* double
* ratio
* string
* character
* symbol
* keyword
* list
* vector
* hash-map
* hash-set
* Var
* function (closure)
* atom

Metadata MAY be attached to any value type that supports it.

Metadata MUST NOT affect equality or hashing.

---

# 4. Equality and Hashing

## 4.1 Structural Equality (`=`)

* Scalars compare by value, except numbers follow the rules below.
* Symbols/keywords compare by namespace+name.
* Lists and vectors compare as sequential values: they are equal when they
  have the same length and their elements compare pairwise equal, regardless
  of whether either operand is a list or a vector.
* Maps compare by key/value pairs independent of insertion order.
* Sets compare by membership independent of insertion order.
* Vars compare by identity, i.e. they are equal only when they are the same Var
  object. Updating a Var root binding with `def!` or `set!` MUST NOT replace
  the Var object.
* Metadata ignored.

### Numbers

* bigint vs bigint → exact.
* ratio vs ratio → exact.
* bigint vs ratio → exact rational comparison.
* double vs double → IEEE-754 numeric comparison.
* double vs any non-double numeric type → not equal.
* NaN is not equal to anything, including itself.

---

## 4.2 Hashing

If `=(a,b)` then `hash(a) == hash(b)`.

Map/set hashes MUST be order-independent.

---

## 4.3 Printing

Sigil defines two printed representations: readable and human.

Readable output MUST use these forms:

* `nil`, booleans, symbols, keywords, bigints, and ratios print as their source
  tokens.
* Doubles print with the shortest round-trip decimal representation. Finite
  integral doubles MUST include `.0`. Non-finite doubles print as `##NaN`,
  `##Inf`, and `##-Inf`. Finite doubles printed with exponent notation MUST
  use lowercase `e`, omit `+` on positive exponents, and omit leading zeroes
  in the exponent unless the exponent is zero.
* Strings print quoted, with `\n`, `\t`, `\\`, `\"`, and `\uXXXX` escapes as
  needed.
* Characters print as `\newline`, `\space`, `\tab`, `\uXXXX`, or `\c`.
* Lists print as `(a b c)` and vectors as `[a b c]`.
* Maps print as `{k v ...}` and sets as `#{a b c}`.
* Vars print as `#'ns/name`.
* Functions print as `#<function>`.
* Atoms print as `#<atom readable-value>`.

Map and set readable output MUST be deterministic. Map entries MUST be sorted
by the readable representation of the key. Set elements MUST be sorted by their
readable representation. Internal iteration order need not be deterministic.

Human output is the same as readable output except strings and characters print
as their raw scalar values, without quotes or reader escapes. `print` and
`println` use human output, join multiple arguments with a single space, and
write arguments in left-to-right order. `print` writes no trailing newline;
`println` writes one trailing newline. The REPL prints evaluation results with
readable output. `pr-str` returns the readable output of its arguments joined
with a single space.

---

# 5. Numeric Model

## 5.1 Types

* Integer: arbitrary precision
* Float: IEEE-754 double
* Ratio: reduced `p/q`, `q>0`

---

## 5.2 Arithmetic Promotion

If any operand is double → result double.

Else:

* bigint ⊕ bigint → bigint
* bigint ⊕ ratio → ratio
* ratio ⊕ ratio → ratio

`/` on two integers MUST return ratio.

After exact arithmetic, any ratio result with denominator `1` MUST normalize
to a bigint value.

---

## 5.3 Required Numeric Functions

* `+ - * /`
* `< <= > >= =`
* `inc dec`
* `zero? pos? neg?`
* `quot rem mod`

`+` accepts zero or more arguments and returns `0` with zero arguments. `*`
accepts zero or more arguments and returns `1` with zero arguments.

`-` accepts one or more arguments. With one argument, it returns the numeric
negation of that argument. With zero arguments, it MUST throw `:error/arity`.

`/` accepts one or more arguments. With one argument, it returns the reciprocal
of that argument. With zero arguments, it MUST throw `:error/arity`.

`=` accepts one or more arguments. With one argument, it returns `true`; with
multiple arguments, it compares each adjacent pair.

Ordering comparisons `<`, `<=`, `>`, and `>=` MUST accept any numeric types and
compare by numeric value. If any operand is a double, comparison is in the
double domain. Any comparison involving NaN MUST return false. Ordering
comparisons require at least one argument; with one argument they return
`true`, and with multiple arguments they compare each adjacent pair in the
chain.

### Integer division semantics

Let `a`, `b` integers, `b ≠ 0`.

* `quot(a,b)` → truncate toward zero.
* `rem(a,b)` → `a - b*quot(a,b)`
* `mod(a,b)`:

  * If `rem == 0` → 0
  * Else if `sign(rem) == sign(b)` → rem
  * Else → `rem + b`

Non-integer input to these functions → error.

---

# 6. Namespaces and Vars

## 6.1 Namespace Model

Namespace contains:

* name
* symbol → Var mappings
* alias → namespace mappings

A global namespace registry MUST exist.

The required core namespace is named `core`.

Aliases are created with `(alias 'alias-name 'namespace-name)`. The target
namespace MUST already exist. The alias is added to the current namespace's
alias map, replacing any previous mapping for the same alias name, and the form
returns `nil`.

---

## 6.2 Namespace Forms

### `(ns name)`

* Sets current namespace.
* Creates if missing.
* Core remains available through the resolution fallback in §6.3; `(ns ...)`
  MUST NOT copy core Vars into the target namespace.

### `(in-ns 'name)`

* Switch current namespace.
* Creates if missing.

---

## 6.3 Vars

A Var contains:

* namespace
* name
* root binding
* metadata

### `(def! sym expr?)`

* Creates/updates Var in current namespace.
* Returns the Var.

### `(var sym)`

Returns Var object.

### Dereferencing Vars

`(deref var)` and `@var` MUST return the Var's current root binding when their
operand is a Var.

### Resolution

Unqualified symbol resolution order:

1. Lexical env
2. Current namespace
3. Core namespace

Qualified symbol `ns/name` resolves directly.

Unresolved symbol → error.

---

## 6.4 `set!`

`(set! sym expr)`:

* `sym` MUST resolve to a Var.
* MUST NOT refer to lexical binding.
* If `sym` resolves to a lexical binding, `set!` MUST throw `:error/type` and
  MUST NOT mutate any Var.
* Sets root binding.
* Returns new value.

---

# 7. Lexical Environments and Destructuring

Supported in:

* `let*`
* `fn*`
* `loop*`

## 7.1 Vector destructuring

Supports:

* positional
* `& rest`
* `:as name`
* nested patterns

---

## 7.2 Map destructuring

Supports:

* `:keys`
* `:syms`
* `:strs`
* explicit `{k v}`
* `:or`
* `:as`
* nested patterns

Missing keys bind to nil unless overridden by `:or`.

Map destructuring keys are derived as follows:

* `:keys [x]` binds `x` from keyword key `:x`.
* `:syms [x]` binds `x` from symbol key `'x`.
* `:strs [x]` binds `x` from string key `"x"`.
* Explicit map entries are `binding-form lookup-key` pairs; `lookup-key` is
  used as a literal lookup key and is not evaluated.
* `:or` maps binding symbols to default values.
* `:as` binds the complete input map.

---

# 8. Evaluation

## 8.1 Self-evaluating

* nil, booleans, numbers, strings, chars, keywords

## 8.2 Symbol

* resolves to lexical binding or Var value

---

## 8.3 Collections

* Vector, map, set elements evaluated left-to-right.
* Lists follow special/macro/function rules.

---

## 8.4 List Evaluation

Given `(op arg1 ... argN)`:

1. If special form → evaluate per rule.
2. Else macroexpand fully.
3. Else:

   * Evaluate `op`
   * Evaluate args left-to-right
   * Apply

---

## 8.5 Eagerness

All core functions MUST be eager. Sigil has no lazy sequence type: functions
such as `map`, `concat`, `rest`, and `seq` MUST compute and return their result
before returning to the caller.

---

# 9. Special Forms

Supported:

This list is authoritative for recognizing special forms during list evaluation
and syntax-quote symbol qualification.

* `quote`
* `if`
* `do`
* `def!`
* `ns`
* `in-ns`
* `let*`
* `fn*`
* `loop*`
* `recur`
* `throw`
* `try*`
* `var`
* `set!`
* `defmacro`

---

## 9.1 `if`

Truthiness: only `nil` and `false` are false.

---

## 9.2 `let*`

Sequential binding.

---

## 9.3 `fn*`

* Single or multi-arity.
* Supports variadic via `&`.
* Lexical closure.

---

## 9.4 `loop*` and `recur`

* `recur` MUST appear in tail position.
* `recur` targets the nearest enclosing `loop*` bindings or `fn*` parameters.
* Arity must match the target's binding or parameter count.
* Arity mismatch MUST throw `:error/arity`.
* Must not grow stack.

---

## 9.5 `throw`

Throws value.

---

## 9.6 `try*`

Form:

```
(try* body...
      (catch sym catch-body...)
      (finally fin-body...))
```

Semantics:

* Body executes.
* On throw:

  * First catch executes.
  * `sym` bound to thrown value.
* `finally` always runs.
* If `finally` throws, it replaces prior result.

---

# 10. Macro System

## 10.1 `defmacro`

* Defines macro Var.
* Macro receives raw argument forms.
* Must return a form.

---

## 10.2 Macro Expansion

### `macroexpand-1`

If list head resolves to macro Var → call macro with raw args.

### `macroexpand`

Repeatedly apply until fixed point (bounded recursion).

Evaluation MUST macroexpand before applying.

---

# 11. Syntax-Quote

Define recursive function `SQ(form)`.

Nested syntax-quote behavior is unspecified. Conforming programs and tests
MUST NOT depend on the expansion of a syntax-quote form that appears inside
another syntax-quote form.

### 11.1 Symbols

`SQ(sym)` → `(quote qualified-sym)`

Symbol qualification MUST be determined by resolution:

* Special form names in the authoritative list in §9, plus `ns`, `in-ns`, and
  `defmacro`, MUST remain unqualified.
* A symbol that resolves to a Var MUST be qualified to that Var's namespace.
* A symbol that does not resolve MUST be qualified to the current namespace.

---

### 11.2 Scalars & Keywords

`SQ(x)` → `(quote x)`

---

### 11.3 Lists

`SQ((e1 ... en))` →

```
(apply list
  (concat chunk1 chunk2 ... chunkN))
```

Where:

* If `ei` is `~x` → `(list x)`
* If `ei` is `~@x` → `(seq x)`
* Else:

  * Let `Ei = SQ(ei)`
  * chunk → `(list Ei)`

`~@` invalid outside list/vector.

---

### 11.4 Vectors

`SQ([e1 ... en])` →

```
(vec
  (concat chunk1 chunk2 ... chunkN))
```

Chunk rules identical to list.

---

### 11.5 Maps

`~@` invalid in map.

`SQ({k v ...})` → map literal where each key/value is replaced by `SQexpr`.

---

### 11.6 Sets

`~@` invalid in set.

`SQ(#{e1 ...})` → set literal with `SQexpr` elements.

---

# 12. Core Required Functions

Core namespace MUST provide:

* `+ - * /`
* `< <= > >= =`
* `print println pr-str read-string`
* `not`
* `inc dec`
* `zero? pos? neg?`
* `quot rem mod`
* `meta with-meta`
* `atom reset! swap!`
* `deref`
* `macroexpand macroexpand-1`
* `list vec map set seq`
* `first rest nth concat`
* `get`
* `eval`
* `apply`
* `alias`

The core namespace MUST be available through the resolution fallback described
in §6.3.

`map` MUST accept a function and one or more collections, apply the function to
items from each collection in lockstep, stop at the shortest collection, and
return a list. `concat` MUST return a list. `rest` MUST return a list. `seq`
MUST return either `nil` or a list.

Collection functions operate on these sequenceable values:

* `nil` is empty.
* Lists and vectors are traversed in element order.
* Strings are traversed as characters.
* Maps are traversed as two-element vectors `[k v]`, sorted by the readable
  representation of `k`.
* Sets are traversed as elements sorted by readable representation.

`first` returns `nil` for `nil` or an empty collection. `rest` returns `()` for
`nil` or an empty collection. `seq` returns `nil` for `nil` or an empty
collection, otherwise it returns a list.

`nth` accepts two or three arguments: `(nth coll index)` and
`(nth coll index default)`. `index` MUST be a non-negative integer. If `index`
is in bounds, `nth` returns the item at that zero-based position in the
sequenceable view of `coll`. If `index` is out of bounds and a default is
provided, `nth` returns the default. If `index` is out of bounds without a
default, `nth` throws `:error/index`.

`get` accepts two or three arguments: `(get coll key)` and
`(get coll key default)`. For maps, it returns the value for `key` or the
default. For sets, it returns the equal set element or the default. For `nil`,
it returns the default. If no default is supplied, the default is `nil`.
Calling `get` on any other type throws `:error/type`. Keywords and maps MUST
NOT be callable as functions.

`read-string` MUST read the first complete form from its string argument and
ignore trailing input. An empty or whitespace-only string MUST throw
`:error/reader`.

`apply` MUST accept a function, zero or more leading arguments, and one final
sequenceable argument. `(apply f a b [c d])` is equivalent to `(f a b c d)`.
The final argument MUST be sequenceable; otherwise `apply` MUST throw
`:error/type`.

---

# 13. Atoms

* `(atom x)`
* `@a`
* `(reset! a v)`
* `(swap! a f args...)`

Single-threaded semantics.

---

# 14. Errors and Program Execution

Runtime errors MUST throw catchable Sigil values. Built-in runtime errors MUST
use this hash-map shape:

```
{:type :error/<kind> :message "..."}
```

The `:type` keyword MUST identify a stable error kind. Required kinds include
`:error/arithmetic`, `:error/unresolved`, `:error/arity`, `:error/reader`, and
`:error/type`, and `:error/index`. The `:message` string MUST be non-empty and
stable enough for human debugging, but tests SHOULD match primarily on `:type`.

Examples of required runtime errors:

* Division by zero MUST throw `:error/arithmetic`.
* Resolving an unknown symbol MUST throw `:error/unresolved`.
* Calling a function with unsupported arity MUST throw `:error/arity`.
* `read-string` on invalid input MUST throw `:error/reader`.
* Applying an operation to an unsupported value type MUST throw `:error/type`.
* Accessing an out-of-bounds sequence index MUST throw `:error/index`.

`throw` MAY throw any Sigil value. `try*` catches both user-thrown values and
built-in runtime error values.

In REPL mode, prompts MUST be written to stdout, including when stdin is not a
TTY. When stdin is not a TTY, implementations MUST bypass interactive line
editing but MUST still emit the same prompts. The REPL reads one complete form
at a time; if a form is incomplete at the end of a line, it MUST continue
reading until the form is complete. EOF while a form is incomplete MUST produce
`:error/reader`.

In REPL mode, an uncaught throw MUST print exactly one line to stdout using
readable output with this prefix:

```
error: <value>
```

The REPL MUST continue after printing an uncaught throw. In script mode, an
uncaught throw MUST print the same line to stderr and exit with status code 1.
A script that completes without an uncaught throw MUST exit with status code 0.

The core namespace MUST contain the Var `*command-line-args*`. In script mode,
its root binding MUST be a vector of strings containing the arguments after the
script path. If no arguments follow the script path, the vector MUST be empty.
In REPL mode, its root binding MUST be `nil`.
