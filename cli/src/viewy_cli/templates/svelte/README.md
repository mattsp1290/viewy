# viewy svelte template

Svelte TypeScript frontend template for `viewy init --template svelte`.
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

Production builds emit a Vite `dist/` tree and embed it in the Nim binary as a
generated asset table. The current lite backend loads those assets through a
loopback fallback until native scheme backends land.

## Build

```bash
viewy build --release
```

`viewy build` runs the Vite build, generates `src/viewy_assets.nim`, compiles
the Nim backend with embedded assets, and writes the binary under `build/`.
