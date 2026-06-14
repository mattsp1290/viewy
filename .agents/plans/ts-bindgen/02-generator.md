# Phase 2 — The generator (`cli/src/viewy_cli/bindgen.nim`)

**Goal:** a pure-ish module that (a) obtains the dump, (b) maps Nim types to TS,
(c) emits the `.ts` bindings string. Keep emission a pure function over parsed
metadata so it is golden-testable without invoking the compiler.

**New file:** `cli/src/viewy_cli/bindgen.nim`. **Reuses:** `config.nim`
(`ViewyConfig`), `build.nim` (`viewyLibPath()`, `ExecProc`/`defaultExec`
pattern), `src/viewy/rpc.nim` types via JSON parse (do **not** import rpc into
the CLI; parse JSON to local mirror structs to avoid a runtime→CLI dependency).

## 2.1 Module shape

```nim
type
  BindgenError* = object of CatchableError

  TsBinding = object        # local mirror of RpcBindingMetadata
    name: string
    params: seq[tuple[name, typ: string]]
    returnType: string
    async: bool

  TsType = object           # local mirror of RpcTypeMetadata
    kind: string            # "object" | "enum"
    name: string
    fields: seq[tuple[name, typ: string]]
    values: seq[string]

  BindgenInput = object
    bindings: seq[TsBinding]
    types: seq[TsType]
    warnings: seq[string]   # unknown types, skipped variants, etc.

proc parseDump*(lines: string): BindgenInput
proc nimTypeToTs*(nimType: string; known: HashSet[string];
                  warnings: var seq[string]): string
proc renderBindings*(input: BindgenInput; header = true): string   # PURE — golden-tested
proc dumpFromProject*(nimMain, libPath: string; exec: ExecProc): string
proc generate*(cfg: ViewyConfig; projectDir, outPath: string; exec: ExecProc): string
```

## 2.2 Obtaining the dump (`dumpFromProject`)

The dump is emitted by a **compile-time** `echo` (Phase 1), so the generator
must invoke the Nim compiler, not run the binary. Use **`nim check`** (semantic
pass only — runs macros, no codegen, fast) with the same path flags `buildApp`
uses (`build.nim:216-237`):

```
nim check --hints:off --mm:orc --threads:on <backendDefine> -d:viewyDumpBindings \
  --path:<nimSrcDir> --path:<viewyLibPath()> <nimMain>
```

- **Match the real compile path's flags.** A bindgen-target backend may use async
  (`Future[T]` → needs `asyncdispatch`), `{.gcsafe.}` accessors, and
  backend-conditional code. `dev.nim`/`build.nim` compile with `--mm:orc
  --threads:on` plus a backend define (`backendDefine`, `build.nim:176-183`).
  Verified empirically: `tests/test_dump_bindings.nim:39` itself runs the dump
  under `nim c --mm:orc --threads:on`. Use the same flag set (default
  `-d:viewyBackend=lite` for the check, matching `dev.nim`) so the semantic pass
  succeeds on a real async/gcsafe backend instead of erroring on missing threads
  support. Confirm the example backend `nim check`s green under these flags.
- Capture stdout; keep only lines beginning with `{`.
- `viewyLibPath()` already resolves checkout / nimble / sibling-pkg cases
  (`build.nim:60-78`) — reuse it; raise `BindgenError` with its message if empty.
- **Verify during implementation:** that a compile *error* in the user's backend
  surfaces clearly (non-zero exit → raise `BindgenError` with captured output),
  and that `nim check` actually triggers the macro echo. `viewyDumpBinding`
  (`rpc.nim:154-159`) echoes inside a `when defined(...)` macro body at
  semantic-analysis time, so `nim check` *should* fire it — but probe it; if not,
  fall back to `nim c --compileOnly --hints:off ...`. Note this as a build-time
  check, not an assumption.

## 2.3 Nim→TS type mapping (`nimTypeToTs`)

Input is a Nim type-name **string** (from metadata), so a tiny recursive parser
is required. Algorithm: strip whitespace; match a generic head `Name[...]` by
splitting on the outermost brackets (respect nesting; split args on top-level
commas only).

> **Parser edge cases to cover with tests:** `array[N, T]`'s first arg may itself
> be a range (`0..3`) or const expr containing dots/brackets, and is discarded —
> the top-level comma split must isolate it correctly before dropping it. Nested
> generics (`seq[Option[Todo]]`, `Table[string, seq[Todo]]`) must split on the
> *top-level* comma only. These are explicit cases in `test_bindgen_typemap.nim`
> (Phase 5).

| Nim (head) | TS |
| --- | --- |
| `string`, `cstring` | `string` |
| `int`,`int8..64`,`uint`,`uint8..64`,`byte`,`float`,`float32`,`float64` | `number` |
| `bool` | `boolean` |
| `void` | `void` |
| `char` | `string` |
| `seq[T]`, `openArray[T]`, `varargs[T]` | `${ts(T)}[]` |
| `array[N, T]` | `${ts(T)}[]` (drop the size arg) |
| `Option[T]` | `${ts(T)} \| null` |
| `Table[K,V]`, `OrderedTable[K,V]` | `Record<${ts(K)}, ${ts(V)}>` |
| name in `known` (registered `viewyType`) | that name verbatim |
| anything else | `unknown` + push a warning |

Notes:
- `known` is the set of `TsType.name`s parsed from the dump.
- `Record<K,...>` requires `K` to map to `string`/`number`; if `K` is an object,
  warn and emit `Record<string, ...>`.
- Keep this a **pure function** with `warnings` collected by ref so the CLI can
  print them and tests can assert them.

## 2.4 TS emission (`renderBindings` — pure, golden-tested)

Emit, in this order:

1. Header banner: `// viewy-bindings.ts (generated by 'viewy bindgen' — do not edit)`
   and an `/* eslint-disable */` line.
2. **Types** — for each `TsType`:
   - object → `export interface Name { field: tsType; ... }`
   - enum → `export type Name = "A" | "B" | "C";` (string-literal union; the
     runtime jsony encodes Nim enums as their string value — confirm against
     `jsony` enum behavior during impl and pick union vs TS `enum` accordingly).
3. **Stubs** — for each `TsBinding`:
   ```ts
   export function greet(name: string): Promise<string> {
     return window.__viewy.call("greet", name) as Promise<string>;
   }
   ```
   - Param list maps each `(name, typ)` via `nimTypeToTs`.
   - Return is always `Promise<ts(returnType)>` (async flag does **not** change
     the TS surface — both sync and async procs are `Promise<T>` on the wire, per
     roadmap §"Async procs"; `void` → `Promise<void>`).
   - Forward args positionally to `window.__viewy.call(name, ...args)` matching
     the runtime in `src/viewy/runtime_js.nim`.
4. A minimal ambient declaration so the file type-checks standalone:
   ```ts
   declare global {
     interface Window { __viewy: { call(name: string, ...args: unknown[]): Promise<unknown> } }
   }
   ```
   **Verified:** no template ships a `__viewy` global — `templates/*/src/vite-env.d.ts`
   contains only `/// <reference types="vite/client" />`. So the generated
   `viewy-bindings.ts` is the **sole owner** of this `declare global` block. The
   example must NOT add a competing `__viewy` decl in its `vite-env.d.ts`, or
   `tsc` errors on a duplicate global.

**Must type-check under the strict vanilla tsconfig.** The example (and the
golden test) use `templates/vanilla/tsconfig.json` verbatim, which sets `strict`,
`noUnusedLocals`, `noUnusedParameters`, and `verbatimModuleSyntax: true`. The
emitter must satisfy all of these: every generated stub param is forwarded (so
`noUnusedParameters` is fine), and `import`/`export` must be type-correct under
`verbatimModuleSyntax`. The Phase 5 golden roundtrip runs `tsc --noEmit` with
exactly this config — do an actual `tsc` run during Phase 2, don't defer it.

Generate a single `.ts` file by default (types + stubs + ambient). **Deliberate
scope decision:** the roadmap (`ts-bindgen.md:9,79`) mentions emitting both `.ts`
and `.d.ts`; v1 emits one self-contained `.ts` because it is simpler and
`tsc`-checkable on its own. Record this divergence in the example README so the
review pass validates it rather than flagging it as a miss.

## 2.5 `generate` orchestration

`generate(cfg, projectDir, outPath, exec)`:
1. Resolve `nimMain = projectDir / cfg.nimMain`, `nimSrcDir = parentDir`.
2. `dumpFromProject` → raw lines.
3. `parseDump` → `BindgenInput`.
4. `renderBindings` → TS string.
5. `createDir(parentDir(outPath))`, `writeFile(outPath, ts)`.
6. Return a human summary (count of types + functions, list of warnings),
   following the `buildApp` summary-string convention (`build.nim:242-248`).

## Acceptance

- [ ] `nimTypeToTs` unit tests pass for scalars, `seq`, `Option`, `Table`,
      nested (`seq[Option[Todo]]`), unknown→`unknown`+warning.
- [ ] `renderBindings` golden test matches a fixed expected `.ts` byte-for-byte.
- [ ] `generate` on the example backend writes a file that `tsc --noEmit` accepts
      (Phase 5).
