// Relative asset paths let any server mount the bundle under any prefix.
// `npm run dev` proxies /ws to a viewer started with `dev/chess.sh ui`.
import { defineConfig } from 'vite';
import { svelte, vitePreprocess } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  base: './',
  plugins: [svelte({ preprocess: vitePreprocess() })],
  server: { proxy: { '/ws': { target: 'ws://127.0.0.1:8765', ws: true } } },
  build: { outDir: 'dist', emptyOutDir: true },
});
