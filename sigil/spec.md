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
* Ratios: `a/b` where `a`, `b` are integers and `b ≠ 0`.

  * MUST normalize to lowest terms.
  * Denominator MUST be positive.

### 2.2.2 Strings

Delimited by `"`.
Supported escapes:

* `\n`, `\t`, `\\`, `\"`
* `\uXXXX` (4 hex digits)

Invalid escape → reader error.

### 2.2.3 Characters

* `\c`
* `\newline`, `\space`, `\tab`
* `\uXXXX`

Invalid form → reader error.

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

Any other `#` dispatch is an error.

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

* Scalars compare by value.
* Symbols/keywords compare by namespace+name.
* Lists/vectors compare elementwise in order.
* Maps compare by key/value pairs independent of insertion order.
* Sets compare by membership independent of insertion order.
* Metadata ignored.

### Numbers

* bigint vs bigint → exact.
* ratio vs ratio → exact.
* bigint vs ratio → exact rational comparison.
* double involved → comparison in double domain.
* NaN is not equal to anything, including itself.

---

## 4.2 Hashing

If `=(a,b)` then `hash(a) == hash(b)`.

Map/set hashes MUST be order-independent.

---

## 4.3 Deterministic Printing

Map and set printed representations MUST be deterministic.

Recommended rule:

* Sort entries by `pr-str` of key (maps) or element (sets) before printing.

Internal iteration order need not be deterministic, but printing MUST be.

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

---

## 5.3 Required Numeric Functions

* `+ - * /`
* `< <= > >= =`
* `inc dec`
* `zero? pos? neg?`
* `quot rem mod`

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

---

## 6.2 Special Forms

### `(ns name)`

* Sets current namespace.
* Creates if missing.
* MUST auto-refer core namespace.

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

# 9. Special Forms

Supported:

* `quote`
* `if`
* `do`
* `def!`
* `let*`
* `fn*`
* `loop*`
* `recur`
* `throw`
* `try*`
* `var`
* `set!`

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
* Arity must match.
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

### 11.1 Symbols

`SQ(sym)` → `(quote qualified-sym)`

Unqualified symbols MUST be qualified to current namespace.

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
* `print println read-string`
* `inc dec`
* `zero? pos? neg?`
* `quot rem mod`
* `meta with-meta`
* `atom reset! swap!`
* `deref`
* `macroexpand macroexpand-1`
* `list vec map set seq`
* `first rest nth concat`
* `eval`
* `apply`

Core MUST be auto-referred by `(ns ...)`.

---

# 13. Atoms

* `(atom x)`
* `@a`
* `(reset! a v)`
* `(swap! a f args...)`

Single-threaded semantics.
