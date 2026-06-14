# Phase 4 — Example app (`examples/ts-bindgen/`)

**Goal:** a runnable app that demonstrates the full loop: Nim backend with
`viewyType` + `expose` → `viewy bindgen` → typed TS frontend that imports the
generated module and calls procs with autocomplete and type-checking.

**Why a new example (not reusing `examples/todo`):** existing examples embed
their HTML as a Nim string const and have **no TS frontend** (confirmed:
`examples/todo` is just `src/main.nim` + nimble + nim.cfg). Bindgen's whole point
is a typed *frontend*, so this example needs a real vite/TS project. Model its
frontend on `cli/src/viewy_cli/templates/vanilla/` (the canonical TS layout).

## 4.1 Directory layout

```
examples/ts-bindgen/
  viewy.json                 # frontendDir ".", nimMain "src/main.nim",
                             # assets "scheme", bindingsOut "src/viewy-bindings.ts"
  ts-bindgen.nimble          # like examples/todo/todo.nimble
  nim.cfg                    # like examples/todo/nim.cfg
  index.html                 # vite entry, #app mount (copy vanilla template)
  package.json               # vite + typescript (copy vanilla template deps)
  package-lock.json          # REQUIRED — CI runs `npm ci`, which needs a lockfile
  tsconfig.json              # copy vanilla template (strict)
  vite.config.ts             # copy vanilla template
  .gitignore                 # ignore src/viewy_assets.nim (build output) + dist/ build/ nimcache/
                             # but NOT src/viewy-bindings.ts (committed generated)
  src/
    main.nim                 # backend: types + viewyType + expose
    main.ts                  # frontend: imports ./viewy-bindings, calls procs
    style.css                # minimal
    viewy-bindings.ts        # GENERATED — committed so the example browses cleanly
    vite-env.d.ts            # copy vanilla template (must NOT declare __viewy —
                             # viewy-bindings.ts owns that global, see Phase 2)
  README.md                  # how to regen + run
```

**Two generated artifacts, two policies.** `viewy build` also writes
`src/viewy_assets.nim` (`build.nim:194`) on every run — that is build output and
must be **gitignored**, or the CI drift check (Phase 5) fails on unrelated
`viewy_assets.nim` noise. `src/viewy-bindings.ts` is the opposite: **committed**
and drift-checked. The vanilla `.gitignore` covers `dist/`/`build/`/`nimcache/`
but not `viewy_assets.nim`, so add it explicitly.

## 4.2 Backend (`src/main.nim`) — exercises the common mapping paths

Include the common type-mapper branches (scalars, `enum`, `object`, `Option`,
`seq`, sync + async). Exhaustive coverage of `array`/`Table`/deep nesting lives
in the `test_bindgen_typemap.nim` unit test (Phase 5), not the example — keep the
example readable rather than contriving a `Table` field into a todo item.

Note `import std/options` explicitly: `src/viewy.nim:7` re-exports `app, rpc,
events, assets, …, menu, runtime_js` but **not** `std/options`, so `Option[...]`
is undeclared without it.

```nim
import std/[strutils, options]
import viewy

type
  Priority = enum         # -> TS string-literal union
    pLow = "low", pMed = "med", pHigh = "high"

  Todo = object           # -> TS interface
    id: int               # number
    title: string         # string
    done: bool            # boolean
    priority: Priority    # Priority union
    note: Option[string]  # string | null

viewyType Priority
viewyType Todo

expose greet(name: string): string = "Hello, " & name & " from Nim!"
expose addTodo(t: Todo): seq[Todo] = ...        # seq[Todo] -> Todo[]
expose listTodos(): seq[Todo] = ...
expose setDone(id: int, done: bool): seq[Todo] = ...
expose countLater(todos: seq[Todo]): Future[int] = ...   # async -> Promise<number>
```

Follow the gcsafe / `App` wiring pattern from `examples/todo/src/main.nim`
(thread-safe `{.cast(gcsafe).}` accessors, `newApp().run()`).

## 4.3 Frontend (`src/main.ts`) — proves type-checking

```ts
import { greet, addTodo, listTodos } from "./viewy-bindings";

const out = document.querySelector<HTMLPreElement>("#out")!;

document.querySelector("#ping")?.addEventListener("click", async () => {
  out.textContent = await greet("viewy");          // greet: (name: string) => Promise<string>
});

document.querySelector("#add")?.addEventListener("click", async () => {
  const todos = await addTodo({                    // arg type-checked against interface Todo
    id: 0, title: "write bindings", done: false,
    priority: "high", note: null,
  });
  out.textContent = JSON.stringify(todos, null, 2);
});
```

The acceptance signal is that **`tsc --noEmit` fails** if `addTodo`'s argument
shape is wrong — that is the property the example demonstrates.

## 4.4 README

Document the loop explicitly:

```
# regenerate bindings from the Nim backend
viewy bindgen                     # writes src/viewy-bindings.ts

# type-check the frontend against them
npm install && npm run build      # runs `tsc && vite build`

# run the desktop app
viewy dev
```

Note that `src/viewy-bindings.ts` is **committed but generated** — never edited
by hand — and that re-running `viewy bindgen` after changing `main.nim` keeps it
in sync (the single-source-of-truth guarantee from the roadmap).

## 4.5 Wiring into CI / example coverage

**There is no example-build matrix.** Verified: `.github/workflows/ci.yml` builds
examples as individual hardcoded steps — "Build hello example" (~`:542`), "Build
todo example" (~`:549`), each a bare `nim c`. The only TS/vite path is
`cli/tests/test_templates.py` (run at ci.yml ~`:607`, **Linux-only**), and it
hardcodes `TEMPLATES = ("react", "svelte")`. So the concrete CI work is:

- Add an explicit **"Build ts-bindgen example"** step modeled on the hello/todo
  steps (compile the Nim backend with the same flags).
- Add a **Linux-gated** roundtrip + drift step (its own script, or extend
  `test_templates.py`): run `viewy bindgen` → `npm ci && npm run build` (which
  runs `tsc`) → `git diff --exit-code` over `src/viewy-bindings.ts`. Decide
  explicitly which (new script vs extend `test_templates.py`) and name it.
  `npm ci` requires the committed `package-lock.json` (§4.1).
- Gate the Node steps on Linux/Node availability the way `test_templates.py`
  already is.
- Add a line to the top-level examples list (README/docs) describing it.

## Acceptance

- [ ] `viewy bindgen` in the example writes a `viewy-bindings.ts` whose committed
      copy matches (drift check in CI: regen, `git diff --exit-code`).
- [ ] `npm run build` (tsc + vite) succeeds against the generated bindings.
- [ ] `viewy dev` launches and the Ping / Add buttons round-trip to Nim.
- [ ] Deliberately breaking a call arg makes `tsc --noEmit` fail (manual check
      noted in README).
