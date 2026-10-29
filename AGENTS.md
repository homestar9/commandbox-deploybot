# commandbox-deploybot

CommandBox module (CFML) that adds `box deploybot *` commands. It is a client for the owner's
own DeployBot server. User docs: README.md.

## Test

- `box install` once to get TestBox (into `testbox/`, git-ignored).
- `box run-script test` runs every spec in `tests/specs/` and loads this working copy as the module.
- One spec: `box task run taskFile=tests/Run.cfc :bundles=tests.specs.EnvFileSpec`
- Specs never reach a network or touch the real CommandBox config. They stub `DeploybotClient`
  and the config service.

## Layout and rules

- `commands/deploybot/**/*.cfc` handle only arguments and prompts. The logic is in `models/`.
- Models never call `error()`. They `throw( type = "Deploybot.*" )`, and the command's `guard()`
  turns that into a command error. This keeps models testable without running a command.
- All HTTP goes through `DeploybotClient`. All token storage goes through `TokenStore`. All git
  calls go through `GitInspector`. Specs stub those three (`stubGit()` in `BaseSpec`). Only
  `GitInspectorSpec` runs real git.
- Never print or log a value from the env file or the token. Print key names only. Add a spec
  when you add output.
- The server contract (URL, headers, JSON response, status codes) is documented in
  `models/DeploybotClient.cfc` and `models/EnvPusher.cfc`. Change both sides together.
- Every method has a docblock. Use member functions and `keyExists()`.
- Add each user-visible change under `## [Unreleased]` in `CHANGELOG.md` (Keep a Changelog sections).
- User-facing text (messages, README, CHANGELOG, doc comments) uses short, plain sentences.
- `testbox/` is a vendored dependency. Don't edit or search it.
- `release.json` lets this module publish itself with commandbox-release (`box release publish`).
  The release runs `run-script test` first (`testCommand`), so keep the tests green.
