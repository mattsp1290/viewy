# viewy vanilla template

Vanilla TypeScript frontend template for `viewy init --template vanilla`.
It is vendored with the CLI so init does not fetch project scaffolding from
the network.

## Requirements

- Nim 2.0 or newer
- Node.js 20.19 or newer, or 22.12 or newer
- npm

## Frontend

```bash
npm ci
npm run dev
npm run build
```

Production builds use Vite with `vite-plugin-singlefile` and emit one
self-contained `dist/index.html`. Keep browser assets under `src/assets/`;
files in `public/` are copied as separate files and are not inlined by the
single-file build.

## Backend

```bash
nim c --mm:orc --threads:on src/main.nim
```

When developing this template from a local viewy checkout before the package
is published, compile with an explicit library path:

```bash
nim c --path:/path/to/viewy/src --mm:orc --threads:on src/main.nim
```
