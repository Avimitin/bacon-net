import { defineConfig } from "vite";

export default defineConfig({
  base: "/webui/",
  esbuild: {
    // no @vitejs/plugin-react here: force the automatic JSX runtime so no
    // module emits classic `React.createElement` calls (React is never
    // imported into scope).
    jsx: "automatic",
  },
  server: {
    proxy: {
      "/manage": "http://localhost:8000",
      "/config": "http://localhost:8000",
      "/account": "http://localhost:8000",
    },
  },
});
