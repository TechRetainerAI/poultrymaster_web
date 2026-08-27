import { defineConfig } from "vitest/config"
import path from "node:path"

// Unit tests for the pure logic that the UI and the API layer share.
//
// Deliberately narrow: this is NOT a browser/component test setup. It covers
// modules that can be reasoned about on their own -- today the payment
// allocation maths in lib/balances -- so widening `include` should be a
// deliberate decision rather than something that happens by accident.
export default defineConfig({
  resolve: { alias: { "@": path.resolve(__dirname) } },
  test: {
    environment: "node",
    include: ["lib/**/*.test.ts"],
  },
})
