import eslint from "@eslint/js";
import globals from "globals";

export default [{
  files: ["**/*.js"],
  languageOptions: { globals: globals.browser },
  rules: { ...eslint.configs.recommended.rules, "no-empty": ["error", { allowEmptyCatch: true }], "no-unused-vars": ["error", { caughtErrors: "none" }] },
}];
