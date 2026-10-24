# Security policy

## Report a problem

Please report a security problem privately. Don't open a public issue.

1. Open the repository's **Security** tab on GitHub.
2. Choose **Report a vulnerability**.
3. Say what you found, how to reproduce it, and what an attacker could do with it.

The maintainer will answer as soon as possible. When a fix is ready, it ships in a new version,
and the release notes credit you unless you ask them not to.

## Supported versions

Only the newest version gets security fixes. Update with:

```bash
box update commandbox-deploybot --system
```

## What this module protects

- It never prints or logs a value from the env file or a token. It prints key names only.
- It sends the token only in the `Authorization` header, and only over HTTPS. Plain HTTP works
  only for `localhost` and `127.0.0.1`.
- It does not follow redirects, so the token never goes to another address.
- It stores tokens outside every repository and outside the CommandBox config, which ForgeBox can
  sync.
- It stops a push when git tracks the env file, and warns when `.gitignore` does not cover it.

The README section "Keep the env file safe" lists what you can do on your side.
