# viewy react template

React TypeScript frontend template for `viewy init --template react`.
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
```

Production builds use Vite with `vite-plugin-singlefile` and emit one
self-contained `dist/index.html`. Keep browser assets under `src/assets/`;
files in `public/` are copied as separate files and are not inlined by the
single-file build.

## Build

```bash
viewy build --release
```

`viewy build` runs the Vite build, generates `src/viewy_assets.nim`, compiles
the Nim backend with embedded assets, and writes the binary under `build/`.
