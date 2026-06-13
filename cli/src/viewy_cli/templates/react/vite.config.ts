import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true
  },
  plugins: [react(), viteSingleFile()]
});
