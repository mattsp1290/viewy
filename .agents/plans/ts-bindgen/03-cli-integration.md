# Phase 3 — CLI integration (`viewy bindgen`)

**Goal:** expose the generator as a first-class subcommand and a `viewy.json`
output field, matching the existing dispatch patterns exactly.

**Files touched:** `cli/src/viewy_cli/dispatch.nim`, `cli/src/viewy_cli/config.nim`,
optionally `cli/src/viewy_cli/build.nim` (opt-in regen hook).

## 3.1 `viewy.json` field (`config.nim`)

Add one optional field to `ViewyConfig` (`config.nim:12-21`) and `DefaultConfig`
(`config.nim:25-35`):

```nim
bindingsOut*: string   ## output path for generated TS bindings,
                       ## relative to the project root.
```

Default: `"src/viewy-bindings.ts"`, interpreted **relative to the project root
and independent of `frontendDir`** (note: `DefaultConfig.frontendDir` is
`"frontend"`, `config.nim:33`; the vanilla *template* overrides it to `.`). Add a
`validate` rule **only** if non-empty when
present — keep it optional so existing configs without the field still load
(jsony leaves it `""`; treat `""` as "use default" in the bindgen handler, do
not fail validation). Do **not** add it to the required-non-empty checks at
`config.nim:55-69`.

## 3.2 Dispatch wiring (`dispatch.nim`)

> **Line numbers below are approximate** (verified off by a few lines — e.g.
> `CommandKind` is ~`:12-19`, `runCli` starts ~`:141`). Treat them as navigation
> hints; the **structural** guidance (mirror the `ckBuild` path end-to-end) is
> what matters and is accurate.

Mirror the `ckBuild` plumbing exactly:

1. Add `ckBindgen` to `CommandKind` (`dispatch.nim:13-19`).
2. Add an `of ckBindgen:` arm to the `Command` variant (`dispatch.nim:24-31`)
   carrying an optional `outOverride*: string` for `--out`.
3. Register `--out` as a value-taking option in `parseCommand` (extend the
   `case key` block at `dispatch.nim:73-94`, like `--config`).
4. Add `of "bindgen":` to the positionals `case` (`dispatch.nim:101-139`):
   - reject `--template`/`--release`,
   - accept `--config` and `--out`,
   - `Command(kind: ckBindgen, configPath, configExplicit, outOverride)`.
5. Add `of ckBindgen:` to `runCli` (`dispatch.nim:147-196`), mirroring `ckBuild`
   (`dispatch.nim:174-191`): `loadConfig`, resolve `projectDir`, compute
   `outPath = projectDir / (cmd.outOverride or cfg.bindingsOut or default)`, call
   `bindgen.generate(...)`, map `BindgenError` → exit code 2.
6. Update `usage()` (`dispatch.nim:41-52`) with:
   `viewy bindgen [--out <path>] [--config viewy.json]`.
7. `import bindgen` at the top (`dispatch.nim:1-8`).

## 3.3 Optional build hook (seam only in v1)

Add a `--bindgen` flag to `viewy build` that regenerates bindings *before*
`npm run build` (so the frontend compiles against fresh types). Implementation:
in `runCli`'s `ckBuild` arm, if the flag is set, call `bindgen.generate` first.
Keep it **opt-in** (off by default) per roadmap §"CLI integration … behind a
`viewy.json` flag so it stays opt-in". Do **not** wire auto-regen into
`viewy dev`'s file-watch in v1 — leave a `# TODO(bindgen): regen on backend
change` note at the dev watch seam (`cli/src/viewy_cli/dev.nim`) and file a
follow-up bead.

## 3.4 CLI tests

CLI tests live in **`cli/tests/`** (e.g. `cli/tests/test_dispatch.nim`), **not**
the root `tests/`. They are run by a **hardcoded `exec` list** in the
`task test` block of `cli/viewy_cli.nimble` — new test files are NOT
auto-discovered and MUST be added to that list by hand. The pure-Nim bindgen unit
tests (typemap/render/parsedump, Phase 2/5) also belong under `cli/tests/` with
`--path:src`, because `bindgen.nim` lives in `cli/src/viewy_cli/` and would not be
on the path under root `tests/` (which compiles with `-d:viewyBackend=lite`).

Extend `cli/tests/test_dispatch.nim` (where `parseCommand` is already covered):

- `parseCommand(["bindgen"])` → `ckBindgen`, default out.
- `parseCommand(["bindgen", "--out", "x.ts"])` → `outOverride == "x.ts"`.
- `bindgen` rejecting `--template` / `--release` (raises `DispatchError`).
- `runCli(["bindgen"])` against a tiny fixture project → exit 0, file written.
  (Gate the compile-invoking part on `nim` availability, consistent with how the
  build tests gate on toolchain presence.)
- **Add every new `cli/tests/test_bindgen_*.nim` to the `task test` exec list in
  `cli/viewy_cli.nimble`** or they will never run in CI.

## Acceptance

- [ ] `viewy --help` lists `bindgen`.
- [ ] `viewy bindgen` in a project writes `cfg.bindingsOut`.
- [ ] `--out` overrides the config path.
- [ ] A config missing `bindingsOut` still loads and uses the default.
