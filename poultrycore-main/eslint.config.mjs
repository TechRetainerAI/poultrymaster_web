// ESLint, for ONE job: the Rules of Hooks.
//
// WHY THIS FILE EXISTS
// --------------------
// TopNavigation called two hooks BELOW its farm-type early returns, so it
// rendered six hooks on a Poultry company and four on a Water one. activeFarmType
// comes from a persisted store, so the first paint fell through to the Poultry
// path and rehydration then returned early -- and every Water page that rendered
// DashboardHeader died with "Rendered fewer hooks than expected".
//
// Nothing caught it. `npm run lint` is `next build`, and next.config.mjs sets
// typescript.ignoreBuildErrors, so the build has never had an opinion about
// anything. This file gives it one.
//
// DELIBERATELY NARROW
// -------------------
// Two rules, not a style regime. A config that reformats 700 files is a config
// somebody turns off in a week, and the point here is that the hook rule STAYS
// on. Style, imports, unused vars and the React Compiler rules are all left
// alone on purpose -- add them later as a separate decision, with the diff that
// implies.
//
//   react-hooks/rules-of-hooks   ERROR. This is a correctness rule: code that
//                                breaks it crashes at runtime, as it just did.
//   react-hooks/exhaustive-deps  WARN. Genuinely advisory -- some deps are
//                                omitted on purpose, and the codebase already
//                                carries eslint-disable comments for it, which
//                                only make sense if the rule is switched on.
//
// Run: npm run lint:hooks        (errors only: npm run lint:hooks -- --quiet)

import reactHooks from "eslint-plugin-react-hooks"
import nextPlugin from "@next/eslint-plugin-next"
import tsParser from "@typescript-eslint/parser"

export default [
  {
    ignores: [
      ".next/**",            // build output, and .next/standalone is a full copy
      "out/**",
      "dist/**",
      "build/**",
      "coverage/**",
      "farm-registry-portal/**",  // its own Vite app with its own toolchain
      "deploy/**",                // a deployment copy of the app
      "public/**",
      "**/*.config.*",
      "server*.js",
      "capture-screenshots.js",
    ],
  },
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      // The TS parser only -- no type-aware linting. Neither rule here needs
      // type information, and turning it on would mean a project-wide
      // typecheck on every lint run for no extra findings.
      parser: tsParser,
      ecmaVersion: "latest",
      sourceType: "module",
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    // @next/next is REGISTERED but every one of its rules is left OFF.
    //
    // Three components already carry `eslint-disable-next-line
    // @next/next/no-img-element` from whenever this project last had a Next
    // lint setup. ESLint errors on a disable comment naming a rule it has never
    // heard of, so without the plugin those four comments would fail the lint
    // run -- for a rule nobody is running. Registering it makes them resolve
    // and costs nothing.
    plugins: { "react-hooks": reactHooks, "@next/next": nextPlugin },
    rules: {
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
    },
  },
]
