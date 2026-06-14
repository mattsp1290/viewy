# Phase 5 — Tests & verification

Write tests alongside each phase, not at the end. The matrix below is the exit
gate; nothing is "done" on compile-success alone (per the project's verification
rule — run them).

## Test matrix

| Test file | Phase | Asserts |
| --- | --- | --- |
| `tests/test_dump_types.nim` (new) | 1 | `viewyType` emits exact `{"kind":"object"/"enum",...}` JSON lines (golden, compile + capture). |
| `tests/test_rpc_dump.nim` (extend) | 1 | `parseJson` over a type line: `kind`, `name`, `fields[].name/typ`, enum `values`. |
| `tests/test_dump_bindings.nim` (unchanged) | 1 | Regression: binding line output byte-identical (proves schema stability). |
| `cli/tests/test_bindgen_typemap.nim` (new) | 2 | `nimTypeToTs` over scalars, `seq`, `array[N,T]`, `Option`, `Table`, nested `seq[Option[Todo]]`, unknown→`unknown`+warning. |
| `cli/tests/test_bindgen_render.nim` (new) | 2 | `renderBindings` over a fixed `BindgenInput` → exact `.ts` (golden). Pure, no compiler. |
| `cli/tests/test_bindgen_parsedump.nim` (new) | 2 | `parseDump` splits binding vs type lines on the `kind` discriminator; ignores non-`{` lines. |
| `cli/tests/test_dispatch.nim` (extend) | 3 | `parseCommand`/`runCli` for `bindgen`, `--out`, rejected flags, default-config path. |
| `cli/tests/test_bindgen_roundtrip.nim` or CI step | 2/4 | End-to-end: run `viewy bindgen` on `examples/ts-bindgen`, then `tsc --noEmit` the output → exit 0. Gate on `nim` + `node`/`npx` presence. |

**Test placement (verified):** the `test_dump_*`/`test_rpc_dump` tests exercise
the runtime lib (`src/viewy/rpc.nim`) and belong in **root `tests/`** (auto-walked
by `viewy.nimble`). The `test_bindgen_*` and dispatch tests exercise
`cli/src/viewy_cli/bindgen.nim` and belong in **`cli/tests/`**, and each new file
MUST be added to the hardcoded `task test` exec list in `cli/viewy_cli.nimble`
(it does not auto-discover). See Phase 3 §3.4.

## Golden-file discipline

- Keep golden TS in the test file as a `const expected = """..."""` (the dump
  tests at `tests/test_dump_bindings.nim` already use this in-file pattern —
  follow it, don't add a fixtures dir unless one already exists).
- The `renderBindings` golden is the contract for the generated format; update it
  deliberately when the format changes, and review the diff.
- The roundtrip `tsc --noEmit` step must use the **exact** vanilla
  `tsconfig.json` (`strict`, `noUnusedParameters`, `verbatimModuleSyntax`) so the
  golden proves the emitter satisfies the real strict flags the example compiles
  under (see Phase 2 §2.4).

## Verification gates before declaring done

1. **Build:** `nimble build` (or the project's test task) green, all targets.
   Confirm the CLI still builds (`cli/`) and the runtime lib builds.
2. **Tests:** run **both** suites — root `tests/` (auto-walked, incl. the
   untouched `test_dump_bindings.nim` regression proof) **and** the `cli/` suite
   via the `task test` exec list in `cli/viewy_cli.nimble` (confirm the new
   `test_bindgen_*` files were added to it). Report pass counts.
3. **Type-check roundtrip:** `viewy bindgen` on the example → `tsc --noEmit`
   passes. This is the roadmap's headline correctness property (wire format and
   generated types cannot drift). Run it, don't assume.
4. **Runtime:** `viewy dev` in `examples/ts-bindgen` launches and a button click
   round-trips Nim↔JS (per the project's "it builds ≠ it works" rule). Note the
   observed result.
5. **Drift check:** committed `examples/ts-bindgen/src/viewy-bindings.ts` equals
   a fresh regen (`git diff --exit-code` after `viewy bindgen`). Wire into CI as
   a concrete new step (no example matrix exists — see Phase 4 §4.5). Ensure
   `src/viewy_assets.nim` is gitignored so it does not pollute the diff.
6. **Lint/vet:** `tsc --noEmit` clean for the example frontend; `nim check` clean
   for changed Nim.

## Review pass

Per the repo's review-workflow rule, this is a multi-file change touching a
serialization boundary (Nim type metadata → TS) and a public CLI surface — run
`/review` (dual reviewer) before commit, reconcile findings, then `/fix-review`,
then re-verify gates 1–4. Pay special attention to:
- casing across the Nim↔TS boundary (field names, enum values),
- the `kind` discriminator never colliding with a real binding field,
- `nimTypeToTs` bracket-nesting parser edge cases (commas inside nested generics).
