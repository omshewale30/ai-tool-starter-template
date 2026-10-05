import type { NextConfig } from "next";

// No `rewrites()` for `/api/*` on purpose: rewrites are serialized at `next build`,
// which would bake the backend origin into the image. `src/app/api/[...path]/route.ts`
// forwards those requests and resolves BACKEND_ORIGIN per request instead.
const nextConfig: NextConfig = {
  // Minimal self-contained server for the container image.
  output: "standalone",
  allowedDevOrigins: ["127.0.0.1", "localhost"],
};

export default nextConfig;
