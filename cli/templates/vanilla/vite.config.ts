import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
    clearScreen: false
  },
  plugins: [viteSingleFile()]
});
