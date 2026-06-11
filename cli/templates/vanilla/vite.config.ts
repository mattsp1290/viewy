import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true
  },
  plugins: [viteSingleFile()]
});
