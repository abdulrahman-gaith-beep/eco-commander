module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "type-enum": [
      2,
      "always",
      [
        "feat",
        "fix",
        "docs",
        "test",
        "ci",
        "build",
        "chore",
        "refactor",
        "perf",
        "security",
        "style",
        "revert",
        "audit"
      ]
    ]
  }
};
