# Dummy site

This folder is a fake site repository. Use it to try the module against a local DeployBot. It
matches the `dummy-site` that DeployBot's `tasks/DevFixture.cfc` creates.

The specs don't use it. It is not part of the package.

## Set up

1. In the DeployBot repository, start the dev server and create its dummy site:

   ```powershell
   box server start
   box task run taskFile=tasks/DevFixture target=create
   ```

2. Open `http://127.0.0.1:8080/sites/dummy-site` and choose "Generate / rotate env token".

3. Install this working copy of the module:

   ```bash
   box install <path to this repository> --system
   ```

   Run it again after you change the module.

4. In this folder, save the token:

   ```bash
   box deploybot token set
   ```

## Try it

Run these in this folder:

```bash
box deploybot env check
box deploybot env push --dryRun
```

The dry run shows the target file on the server, `SECRET` changed, and `API_KEY` added. That diff
is against DeployBot's own fixture file. After a real push, the dry run shows "No changes".

A real `box deploybot env push` writes the file. The dummy site is not served, so it has no reinit
or health URL. DeployBot reports both steps as warnings and does not roll back. The command says
"Pushed, with warnings" and that the site was not reinitialized. DeployBot backs up the previous
file in `.data\envs\dummy-site\` first.

## Clean up

```bash
box deploybot token clear
```

Then, in the DeployBot repository:

```powershell
box task run taskFile=tasks/DevFixture target=remove
```
