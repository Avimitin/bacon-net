import { defineConfig } from "vite";

export default defineConfig({
  base: "/webui/",
  server: {
    proxy: {
      "/manage": "http://localhost:8000",
      "/config": "http://localhost:8000",
    },
  },
});
