# Changelog

This file lists the important changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- `env check` and `env push` stop when git tracks the env file. `--force` lets a push go ahead
  anyway. They warn when `.gitignore` does not cover the file, and when the file is in a Dropbox,
  OneDrive, iCloud Drive, or Google Drive folder. `init` reports the same problems.
- On macOS and Linux, the token file is now readable only by its owner (mode 600), and its folder
  is private (mode 700).
- The README uses example addresses only. A section explains how to keep the env file safe, and
  the fallback no longer suggests plain FTP. `SECURITY.md` says how to report a problem.

## [0.1.0] - 2026-10-23

### Added

- `box deploybot init` sets up a site. It writes the `deploybot` block in `box.json`, adds the
  env file to `.gitignore`, creates the env file from `.env.example` with blank values, and offers
  to save the token. It never overwrites an env file.
- `deploybot.site` in `box.json` must follow DeployBot's slug rule: lower-case letters, numbers,
  and dashes, up to 80 characters. A slug with a dot or an underscore stops before any request.
- `box deploybot token set` and `box deploybot token clear` store and remove a site's env token
  in `~/.deploybot/tokens.json` (never the CommandBox config, which ForgeBox can sync).
- `box deploybot env check` compares the key names in `.env.production` with `.env.example`.
  It runs locally and never prints values.
- `box deploybot env push` sends `.env.production` to DeployBot. It shows a dry-run diff of key
  names, asks for confirmation, and prints each deploy step. It supports `--force`, `--yes`, and
  `--dryRun`. It needs a DeployBot with the REST API at `/api/v1`. It says the site was
  reinitialized and passed its health check only when both steps succeeded. Otherwise it warns.
