import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true
  },
  plugins: [svelte(), viteSingleFile()]
});
