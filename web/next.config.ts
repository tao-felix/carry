import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  devIndicators: false,
  // This folder is the project root; stops Next from guessing a parent
  // directory when it finds other lockfiles further up the tree.
  outputFileTracingRoot: path.resolve(__dirname),
};

export default nextConfig;
