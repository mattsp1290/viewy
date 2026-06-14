# Bead graph

This project tracks work in **beads** (`bd`), not markdown TODOs. The graph below
was created and then refined after a two-agent review of the task graph.

## As-built (authoritative) — created 2026-06-14

| Bead | Title | Pri | Blocked by |
| --- | --- | --- | --- |
| `viewy-7vo` | EPIC: TS bindgen | P1 | — (parent of all below) |
| `viewy-9ne` | P1: viewyType macro + type-metadata dump | P1 | — (READY) |
| `viewy-ahu` | P2a: bindgen pure core (parseDump + nimTypeToTs + renderBindings) | P1 | `viewy-9ne` |
| `viewy-oyh` | P2b: bindgen compiler bridge (dumpFromProject + generate) | P1 | `viewy-ahu` |
| `viewy-5ns` | P3: viewy bindgen command + bindingsOut | P1 | `viewy-oyh` |
| `viewy-x8n` | P4: examples/ts-bindgen app **+ owns all ci.yml edits** | P2 | `viewy-5ns` |
| `viewy-71l` | P5: run verification gates + tsc roundtrip + **local** drift | P2 | `viewy-x8n` |
| `viewy-rbz` | F1 (deferred): auto-discover referenced types | P3 | `viewy-71l` |
| `viewy-hdq` | F2 (deferred): variants → tagged unions | P3 | `viewy-71l` |
| `viewy-5d7` | F3 (deferred): auto-regen in `viewy dev` | P3 | `viewy-71l` |

**Review-driven refinements vs the original script below:**
- Phase 2 split into **P2a (pure core, no compiler)** + **P2b (compiler bridge)**
  to isolate the `nim check` dump invocation from the unit-testable mapper/emitter.
- **CI ownership** consolidated: P4 (`viewy-x8n`) authors all `ci.yml` steps; P5
  (`viewy-71l`) only *runs/verifies* them locally (no duplicate CI authoring).
- Explicit **acceptance criteria** added to every phase bead (`bd update --acceptance`).
- P5 now enumerates all six verification gates incl. build + `nim check` lint.
- Epic membership uses `bd update <id> --parent <epic>` (hierarchical child), not
  a blocking dep — `bd dep add <task> <epic>` is rejected ("tasks can only block
  other tasks, not epics").

## Original creation script (kept for reference)

Dependencies follow `bd dep add CHILD PARENT` (child blocked until parent closes);
phase tasks are attached to the epic with `bd update <id> --parent <epic>`.

```bash
# Epic
EPIC=$(bd create "TS bindgen: viewy bindgen command + example app" \
  -d "Implement TypeScript binding generation per .agents/plans/ts-bindgen/. Generator reads -d:viewyDumpBindings metadata and emits typed TS stubs over window.__viewy.call. Includes the type-graph metadata prerequisite and a runnable example app." \
  -t epic -p 1 -l impl --silent)

# Phase 1 — type-graph metadata (prerequisite)
P1=$(bd create "Add viewyType macro + type-metadata dump line" \
  -d "src/viewy/rpc.nim: add RpcTypeMetadata/RpcTypeFieldMetadata, a typed viewyType macro. Unwrap getTypeInst(T)[1] first; objects via getTypeImpl (nnkObjectTy/recList); enums via getImpl (NOT getTypeImpl - it drops StrLit values; jsony emits the string value). Emit a {\"kind\":...} JSON line under -d:viewyDumpBindings without changing binding line format. Add dumpTypesJson/typeMetadata + extend clearBindingsForTests. Tests in root tests/: test_dump_types.nim, extend test_rpc_dump.nim, keep test_dump_bindings.nim byte-stable." \
  -t feature -p 1 -l impl --silent)

# Phase 2 — generator
P2=$(bd create "Implement bindgen.nim generator (dump -> Nim->TS -> emit)" \
  -d "cli/src/viewy_cli/bindgen.nim: parseDump (kind discriminator), nimTypeToTs recursive string mapper (scalars/seq/array/Option/Table/known/unknown+warn; top-level comma split, drop array size arg), pure renderBindings emitter (interfaces, enum unions, Promise stubs forwarding to window.__viewy.call, sole-owner ambient __viewy decl) that compiles under strict+verbatimModuleSyntax+noUnusedParameters tsconfig, dumpFromProject via 'nim check --mm:orc --threads:on -d:viewyBackend=lite -d:viewyDumpBindings' reusing viewyLibPath(), generate orchestration. Tests in cli/tests/ (add to nimble exec list): typemap, render golden, parsedump." \
  -t feature -p 1 -l impl --silent)

# Phase 3 — CLI integration
P3=$(bd create "Wire 'viewy bindgen' command + viewy.json bindingsOut" \
  -d "cli/src/viewy_cli/dispatch.nim: ckBindgen enum + Command arm + --out option + positional case + runCli arm + usage(). config.nim: optional bindingsOut field (default src/viewy-bindings.ts, not in required validation). Optional --bindgen hook on viewy build. Extend CLI dispatch tests." \
  -t feature -p 1 -l impl --silent)

# Phase 4 — example app
P4=$(bd create "Add examples/ts-bindgen app with typed TS frontend" \
  -d "examples/ts-bindgen/: viewy.json, nimble, nim.cfg, vite/TS frontend modeled on templates/vanilla incl committed package-lock.json (npm ci needs it), .gitignore that ignores src/viewy_assets.nim but commits src/viewy-bindings.ts, src/main.nim (import std/options; Priority enum, Todo object w/ Option, sync+async expose, viewyType), src/main.ts importing generated ./viewy-bindings, committed generated viewy-bindings.ts, README. CI has NO example matrix - add an explicit Build step + Linux-gated bindgen+tsc+drift step." \
  -t feature -p 2 -l impl --silent)

# Phase 5 — verification
P5=$(bd create "Bindgen verification: roundtrip tsc --noEmit + drift CI" \
  -d "End-to-end: run viewy bindgen on examples/ts-bindgen then tsc --noEmit (gate on node). CI drift check: regen + git diff --exit-code. Run full nim test suite incl regression. Launch viewy dev and confirm a call round-trips. Then /review + /fix-review before commit." \
  -t task -p 2 -l testing --silent)

# Follow-ups (deferred, not v1)
F1=$(bd create "bindgen: auto-discover referenced types from expose signatures" \
  -d "Remove need for explicit viewyType by walking expose param/return type symbols in a typed seam and registering referenced object/enum types automatically." \
  -t feature -p 3 -l impl --silent)
F2=$(bd create "bindgen: object variants -> TS tagged unions" \
  -d "Roadmap open question. Map Nim object variants (nnkRecCase) to TS discriminated unions keyed on the discriminator field." \
  -t feature -p 3 -l impl --silent)
F3=$(bd create "bindgen: auto-regen on backend change in 'viewy dev'" \
  -d "Wire bindgen into the dev file-watch so editing main.nim regenerates viewy-bindings.ts. Seam left at cli/src/viewy_cli/dev.nim." \
  -t feature -p 3 -l impl --silent)

# Dependencies
bd dep add $P1 $EPIC
bd dep add $P2 $P1
bd dep add $P3 $P2
bd dep add $P4 $P3
bd dep add $P5 $P4
bd dep add $F1 $P5
bd dep add $F2 $P5
bd dep add $F3 $P5
```

Critical path: **P1 → P2 → P3 → P4 → P5**. Follow-ups F1–F3 are deferred and
depend on the core landing.
