# commandbox-deploybot

`commandbox-deploybot` adds `box deploybot` commands to
[CommandBox](https://www.ortussolutions.com/products/commandbox). It is a client for a DeployBot
server that you run yourself. It pushes a site's production `.env` file to that server.

Each ColdBox site keeps its production `.env` on the server, one level above the webroot. You
keep a working copy named `.env.production` at the root of the site's repository. Git ignores
that file. This module sends it to DeployBot. DeployBot then:

1. validates the file,
2. backs up the current `.env`,
3. writes the new file,
4. restricts access to it (ACLs),
5. reinitializes the site, and
6. checks that the site is healthy.

If a step fails, DeployBot rolls back to the backup.

The module never prints your file's values or your token. It prints key names, step summaries,
and the deploy record URL.

## Install

Install it globally, so every site repository can use it:

```bash
box install commandbox-deploybot --system
```

Update it later with:

```bash
box update commandbox-deploybot --system
```

## Set up a site

1. Add a `deploybot` block to the site's `box.json`. It holds no secrets, so commit it:

   ```json
   "deploybot": {
       "url": "https://deploybot.angrysam.com",
       "site": "angrysam-web",
       "envFile": ".env.production"
   }
   ```

   - `url` is your DeployBot server. It must use `https`. Plain `http` works only for
     `localhost` and `127.0.0.1`, for local testing.
   - `site` is the site's slug in DeployBot.
   - `envFile` is optional. It defaults to `.env.production`.

2. Add `.env.production` to the site's `.gitignore`.

3. Save the site's env token. Open the site's page in DeployBot and choose
   "Generate / rotate env token". Then run this command in the site's repository and paste the
   token when asked. The typed characters are hidden:

   ```bash
   box deploybot token set
   ```

4. Edit `.env.production`. Start from `.env.example`.

5. Check the file on your computer:

   ```bash
   box deploybot env check
   ```

6. Push it:

   ```bash
   box deploybot env push
   ```

Run the `box` commands from the site's repository or one of its folders.

## Commands

### `box deploybot token set`

Reads the `deploybot` block from `box.json`, asks for the env token, and saves it. Run it again
to replace the token after you rotate it in DeployBot.

### `box deploybot token clear`

Removes the saved token for this site.

### `box deploybot env check`

Compares the key names in the env file with `.env.example`. It runs on your computer only. It
makes no network request and never prints a value.

- Keys in `.env.example` that are missing from the env file are errors. The command exits with
  code 1.
- Keys in the env file that are not in `.env.example` are listed for information.
- Keys with a blank value are warnings. A value is blank when it is empty, `""`, `''`, or only
  a comment, such as `KEY= # todo`.

The command reads lines like `KEY=value` and `export KEY=value`. It skips lines that start with
`#`. A byte order mark and Windows line endings are fine.

### `box deploybot env push [--force] [--yes] [--dryRun]`

1. Runs the local check. Missing keys stop the push unless you use `--force`.
2. Asks DeployBot for a dry run and prints the key names that would be added, removed, or
   changed. It also prints the keys DeployBot reports as missing or extra.
3. Stops there with `--dryRun`. It also stops when nothing would change.
4. Asks you to confirm. `--yes` skips the question.
5. Pushes for real. It prints each step (id, status, summary), whether DeployBot rolled back,
   and the URL of the deploy record.

The command exits with an error if any step fails or the server answers with an error.

| Flag | Meaning |
|---|---|
| `--force` | Push even if keys from `.env.example` are missing. |
| `--yes` | Skip the confirmation question. |
| `--dryRun` | Show the diff from the server and stop. Nothing changes on the server. |

The file can be at most 64 KB. The module sends the file's bytes unchanged.

## When a release adds new keys

Push the env first, then release. Extra keys are harmless to the old code, but new code that
needs a key it does not have will fail.

1. Add the new keys to `.env.example` and `.env.production`.
2. `box deploybot env check`
3. `box deploybot env push`
4. Release the code.

## If DeployBot is not available

Copy the file to `<site>\.env`, one level above the webroot, with FTP. Then reinitialize the
site with `?fwreinit=<password>`. This skips the validation, backup, and health check.

## Where the token is saved

Tokens are saved in `~/.deploybot/tokens.json` (on Windows, `%USERPROFILE%\.deploybot\tokens.json`).
That file is not in any repository, not in Dropbox, and readable only by your Windows account
and Administrators. Each entry's key is built from the DeployBot host and the site slug, so two
DeployBot servers that use the same slug do not share a token.

They are deliberately **not** in the CommandBox user config (`~/.CommandBox/CommandBox.json`).
CommandBox's config auto-sync, on by default for ForgeBox Pro accounts, uploads that whole file to
ForgeBox, and it can't exclude a key.

Back up the token file if you like, but you never have to: a lost token is replaced by choosing
"Generate / rotate env token" in DeployBot and running `box deploybot token set` again.

## Errors

| Message | What to do |
|---|---|
| The token is wrong, or the site slug is not known (HTTP 401) | Check `deploybot.site` in `box.json`. Then run `box deploybot token set`. |
| Another deploy is running (HTTP 409) | Wait for it to finish and run the push again. |
| The env file is too large (HTTP 413) | Keep the file under 64 KB. |
| Keys are missing (HTTP 422) | Add the keys, or use `--force`. |
| DeployBot did not find the env API (HTTP 404) | Usually `DEPLOYBOT_ADMIN_ALLOWLIST`: the env API only answers allowlisted addresses, so add this computer's public address. Otherwise check `deploybot.url`. |
| Only HTTPS is accepted (HTTP 403) | Use an `https://` `deploybot.url`. |
| Rate limited (HTTP 429) | Wait. Failed tokens count toward the same lock as failed dashboard sign-ins (20 in 15 minutes), so a wrong token can also lock you out of signing in for a while. |
| The site failed its health check or did not reinitialize (HTTP 502) | DeployBot rolls back. Read the steps and the record URL. |
| DeployBot did not answer in 120 seconds | The push may still be running. Check the DeployBot deploy log before you try again. |
| TLS connection failed | Check the certificate and `deploybot.url`. |

## Develop

```bash
box install
box run-script test
```

Run one spec:

```bash
box task run taskFile=tests/Run.cfc :bundles=tests.specs.EnvFileSpec
```

The specs stub the HTTP client and the CommandBox config service. They never reach a network.

To try the commands against a local DeployBot, use the dummy site in `tests/fixtures/dummy-site`.
Its README has the steps.

To publish this module, use [commandbox-release](https://github.com/homestar9/commandbox-release).
`release.json` holds its settings.

## License

Apache 2.0. See `LICENSE`.
