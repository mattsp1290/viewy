# Phase 1 — Type-graph metadata (`viewyType` + dump extension)

**Goal:** make object and enum structure available to the generator without
breaking the existing binding-metadata schema or its tests.

**Files touched:** `src/viewy/rpc.nim` (additive), new
`tests/test_dump_types.nim`, `tests/test_rpc_dump.nim` (extend).

## 1.1 New metadata types (additive)

Add alongside `RpcBindingMetadata` (`src/viewy/rpc.nim:41-57`):

```nim
type
  RpcTypeFieldMetadata* = object
    name*: string        ## field name (object) — empty for enum entries
    typ*: string         ## Nim type-name string, e.g. "int", "seq[Todo]"

  RpcTypeKind* = enum
    rtkObject = "object"
    rtkEnum   = "enum"

  RpcTypeMetadata* = object
    kind*: RpcTypeKind   ## distinguishes a type line from a binding line
    name*: string        ## TS interface / union name, e.g. "Todo"
    fields*: seq[RpcTypeFieldMetadata]  ## object fields (empty for enum)
    values*: seq[string]                ## enum WIRE values ($-value, e.g. "low"), empty for object
```

The `kind` field is the **discriminator the generator uses** to tell a type line
from a binding line in the dump (binding lines never carry `kind`/`fields`/
`values`; type lines always carry `kind`). This keeps the binding line format
byte-identical, so `tests/test_dump_bindings.nim` is unaffected.

## 1.2 `viewyType` macro

Add a **typed** macro so it can call `getTypeImpl` and walk the real AST
(the existing `expose` macro is untyped and only has access to type-name reprs,
which is why it can't produce a field graph on its own):

```nim
macro viewyType*(T: typedesc): untyped =
  ## Register an object/enum type's structure for TS binding generation.
  ## Emits a type-metadata JSON line under -d:viewyDumpBindings.
```

Implementation notes — these recipes were **verified empirically** against Nim's
macro API (probe run 2026-06-14); do not substitute the plausible-looking
alternatives below, which are wrong:

- **Unwrap the `typedesc` first.** `getTypeInst(T)` on a `T: typedesc` param
  returns `BracketExpr(Sym "typeDesc", Sym "Todo")` — not the type body. Index
  `[1]` to reach the real symbol: `let sym = getTypeInst(T)[1]`.
  `getTypeImpl(getTypeInst(T))` / `T.getType` return the `BracketExpr`, and the
  `recList` walk below would fail on it.
- **Object:** `let impl = sym.getTypeImpl` → `nnkObjectTy`. Iterate its
  `recList` (`nnkRecList`), each `nnkIdentDefs` → field name(s) + type node; use
  `.repr` for the type string (same convention the binding metadata already uses
  at `rpc.nim:281`, `typ.repr`). Skip `nnkRecCase` (variants) for v1 — emit the
  discriminator field as a normal field and log a compile-time `hint` that the
  variant arms are not mapped.
- **Enum — use `getImpl`, NOT `getTypeImpl`.** `sym.getTypeImpl` on an enum
  collapses every member to a bare `nnkSym` whose repr is the *identifier*
  (`pLow`) and **drops the string value**. jsony serializes a string-valued enum
  as its `$` value (`pLow = "low"` → wire `"low"`, confirmed via probe), so the
  TS union must carry the *values*, not the identifiers. `sym.getImpl` returns
  `TypeDef → EnumTy` whose children are `nnkEnumFieldDef(Sym "pLow", StrLit
  "low")` for valued members and a bare `nnkSym` for plain members. Extract:
  - `nnkEnumFieldDef` → child `[1]`: `StrLit` → use the string; integer lit →
    fall back to the member identifier name.
  - bare `nnkSym` (plain enum, no `=`) → use the symbol name.
  A `getTypeImpl`-based recipe silently emits `"pLow" | "pMed"` while the wire
  carries `"low" | "med"` — the single most consequential correction here.
- Build an `RpcTypeMetadata`, `toJson()` it, and emit via the **same**
  `viewyDumpBinding`-style compile-time echo path (factor the echo into a shared
  `viewyDumpMeta(json: static string)` so both bindings and types use it).
- Also register into a process-global `typeRegistry: seq[RpcTypeMetadata]` and
  expose `dumpTypesJson*(): string` + `typeMetadata*(): lent seq[RpcTypeMetadata]`,
  mirroring the existing `dumpBindingsJson*()`/`bindingMetadata*()` at
  `rpc.nim:139-147`. Extend `clearBindingsForTests*()` (`rpc.nim:149-152`) to
  also clear `typeRegistry`.

### Why typed macro / reflection

Verified: after unwrapping `getTypeInst(T)[1]`, `getTypeImpl` yields the object
impl and `getImpl` yields the enum impl with string values (see the corrected
recipes above). If field types that are themselves objects need their own line,
the user calls `viewyType` on them too (no
recursive auto-walk in v1). The generator treats any referenced type name it
has no `RpcTypeMetadata` for as "unknown" and warns (see Phase 2).

## 1.3 Dump format after this phase

`nim check -d:viewyDumpBindings <main.nim>` emits, in source order, a mix of:

```
{"name":"greet","params":[{"name":"name","typ":"string"}],"returnType":"string","async":false}
{"kind":"object","name":"Todo","fields":[{"name":"id","typ":"int"},{"name":"title","typ":"string"},{"name":"done","typ":"bool"}],"values":[]}
```

Generator rule: a JSON line with a `kind` key is an `RpcTypeMetadata`; otherwise
it is an `RpcBindingMetadata`. Lines not starting with `{` (compiler chatter)
are ignored.

## 1.4 Tests

- **`tests/test_dump_types.nim` (new):** compile a temp file that declares an
  object + an enum + `viewyType` for each, run `nim check -d:viewyDumpBindings`,
  filter `kind`-bearing lines, assert exact JSON (golden), mirroring the harness
  in `tests/test_dump_bindings.nim`.
- **`tests/test_rpc_dump.nim` (extend):** add `parseJson` assertions over a type
  line's `kind`, `name`, `fields[].name/typ`, and an enum's `values`.
- **Regression guard:** confirm `tests/test_dump_bindings.nim` still passes
  unchanged. Verified: that test compiles its fixture with `nim c` (not
  `nim check`), filters blank lines, then asserts `actual == expected` over **all
  remaining lines** (`tests/test_dump_bindings.nim:42-53`). Its fixture declares
  `Todo` but never calls `viewyType`, so no `kind` line is emitted and the output
  stays byte-identical. This is the proof the schema stayed stable — and the
  reason the deferred auto-discovery follow-up (below) is risky: if `expose`
  itself ever auto-registers referenced objects, this golden breaks and must be
  updated deliberately.

## Deferred (file as follow-up beads, do not build in v1)

- Auto-discovery: have `expose` walk its param/return type symbols and register
  referenced object/enum types automatically (removes the need for explicit
  `viewyType`). Needs a typed seam around `expose`; non-trivial.
- Object variants → tagged unions (roadmap open question).
- `Table`/`Record` field-graph emission is unnecessary (handled structurally by
  the Phase 2 string parser), but nested user objects inside a `Table` still
  require their own `viewyType`.

## Acceptance

- [ ] `viewyType Todo` emits a correct `{"kind":"object",...}` line.
- [ ] `viewyType Color` (enum) emits `{"kind":"enum",...,"values":[...]}`.
- [ ] Existing `test_dump_bindings.nim` passes byte-for-byte unchanged.
- [ ] `dumpTypesJson()` / `typeMetadata()` return the registered types at runtime.
