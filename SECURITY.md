# Security and privacy

notchGPT is a local, unsandboxed macOS app. Review the source and build scripts before running it. It launches an existing Codex CLI, which uses that CLI's existing credentials and configuration. The app itself does not need an API key, directly read authentication files, capture the screen, inspect conversations, or request Accessibility access.

The repository contains source code, scripts, documentation, and a synthetic UI preview. It must never contain an auth store, bearer token, API key, account identifier, personal filesystem path, live status file or daily ledger, browser state, or raw account response. Build and distribution directories are ignored by Git; a release package should contain only the newly built app bundle.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** option when it is enabled. If private reporting is not available, open an issue asking for a private reporting channel **without including exploit details or sensitive information**. Do not post credentials, screenshots of private content, or full account diagnostics.

## Maintainer release checks

1. Run `bash scripts/test.sh` and `bash scripts/package.sh` from a clean checkout.
2. Inspect staged files and the entire Git history for secrets and private data.
3. Confirm the archive contains only the app and no AppleDouble files, diagnostic state, or credentials.
4. Verify the bundle signature and inspect the binary for personal build paths.
5. Publish the checksum with the release. Ad-hoc signing is not Developer ID signing or notarization; document that limitation accurately.
