# Plan: TypeScript Binding Generation (`viewy bindgen`)

**Source roadmap:** `.agents/docs/roadmap/ts-bindgen.md`
**Status as of 2026-06-14:** NOT implemented. Only the upstream dump-metadata
infrastructure exists. This plan implements the generator, the CLI command, the
metadata gap it depends on, and a runnable example app.

## What "done" looks like

A Nim backend that does:

```nim
import viewy

type Todo = object
  id: int
  title: string
  done: bool

viewyType Todo                      # NEW: registers Todo's field graph for bindgen

expose greet(name: string): string = "Hello, " & name
expose addTodo(t: Todo): seq[Todo] = ...
```

…produces, via `viewy bindgen`, a typed frontend module:

```ts
// src/viewy-bindings.ts  (generated — do not edit)
export interface Todo { id: number; title: string; done: boolean }
export function greet(name: string): Promise<string>;
export function addTodo(t: Todo): Promise<Todo[]>;
```

…whose stubs forward to the existing `window.__viewy.call(name, ...args)`
runtime. The example app under `examples/ts-bindgen/` imports and calls these.

## Verified ground truth (read before planning changes)

| Thing the plan depends on | Where it lives today | State |
| --- | --- | --- |
| `expose` macro | `src/viewy/rpc.nim:245-361` | exists |
| Compile-time dump (`-d:viewyDumpBindings`) | `src/viewy/rpc.nim:154-159` | exists, newline-delimited JSON, one binding/line |
| Runtime dump `dumpBindingsJson*()` | `src/viewy/rpc.nim:143-147` | exists, JSON array |
| Binding metadata schema | `src/viewy/rpc.nim:41-57` (`RpcBindingMetadata`, `RpcParamMetadata`) | exists |
| Object/enum **field graph** in dump | — | **MISSING — must add (Phase 1)** |
| JS runtime call surface | `src/viewy/runtime_js.nim` — `window.__viewy.call(name, ...args)` | exists |
| CLI dispatch / commands | `cli/src/viewy_cli/dispatch.nim` — `CommandKind`, `parseCommand`, `runCli` | exists, no `bindgen` |
| `viewy.json` config | `cli/src/viewy_cli/config.nim` — `ViewyConfig` | exists, no bindgen field |
| Build flow / lib-path resolution | `cli/src/viewy_cli/build.nim` — `viewyLibPath()`, `buildApp()` | exists, reusable |
| Existing examples | `examples/{hello,todo,menus,tray-app}` | exist; use **embedded HTML**, not a TS frontend |
| Frontend template (TS + vite) | `cli/src/viewy_cli/templates/vanilla/` | exists — model the example on this |
| Dump tests | `tests/test_dump_bindings.nim`, `tests/test_rpc_dump.nim` | exist; binding schema must stay byte-stable |

## The central design problem

The current dump records each parameter/return type as a **bare Nim type-name
string** (`"typ":"Todo"`, `"returnType":"seq[Todo]"`). It does **not** record
what `Todo` *is*. To emit `interface Todo { ... }` the generator needs `Todo`'s
fields. Two parts follow from this:

1. **Phase 1** adds an opt-in `viewyType T` macro that captures an object's
   fields (or an enum's values) via typed reflection and emits a new
   *type-metadata* line in the same dump — without changing the existing binding
   line format (so `tests/test_dump_bindings.nim` stays green).
2. **Phase 2** gives the generator a small recursive parser for Nim type-name
   strings (`seq[Todo]`, `Option[int]`, `Table[string, Todo]`) so it can map
   composite types whose leaves are scalars or registered types.

Auto-discovering referenced types (so users don't write `viewyType`) is a
follow-up, not v1 — see `01-metadata-type-graph.md` §"Deferred".

## Phase index

1. [`01-metadata-type-graph.md`](01-metadata-type-graph.md) — `viewyType` macro + type-metadata dump (the prerequisite).
2. [`02-generator.md`](02-generator.md) — `bindgen.nim`: dump invocation, Nim→TS type mapper, TS emitter.
3. [`03-cli-integration.md`](03-cli-integration.md) — `viewy bindgen` command wiring + `viewy.json` `bindingsOut` field.
4. [`04-example-app.md`](04-example-app.md) — `examples/ts-bindgen/` full app with a real TS frontend.
5. [`05-tests-and-verification.md`](05-tests-and-verification.md) — unit + golden + `tsc --noEmit` roundtrip + acceptance gates.
6. [`beads.md`](beads.md) — proposed bead graph to track the work.

## Sequencing

Phase 1 → Phase 2 → Phase 3 are a hard chain (each consumes the prior). Phase 4
(example) depends on 1–3 landing but its scaffolding (frontend files, `main.nim`)
can be written in parallel. Phase 5 tests are written alongside each phase, not
at the end.

## Out of scope for v1 (record, don't build)

- Object **variants** → TS tagged unions (roadmap open question; emit a clear
  "unsupported, mapped to `unknown`" warning).
- Generic exposed procs (document as unsupported).
- Auto-regeneration wired into `viewy dev` file-watch (Phase 3 leaves a seam; a
  one-shot regen on `build` is the only auto-hook in v1, behind a flag).
