# Security and privacy

notchGPT is a local, unsandboxed macOS app. Review the source and build scripts before running it. It launches the existing Codex CLI for quota and cloud task reads. It does not require an API key, screen capture, Accessibility access, or new account permissions.

The recent-chat helper reads local title/turn metadata through read-only SQLite connections, saved remote summaries and existing writer locks without writing them. It does not read chat message bodies or tool arguments/outputs. Remote task status is the last state saved by Codex, not a live host subscription. Background polling never resumes a thread, starts a turn or approves a request. Explicit card clicks open the selected task with its original host identity; cloud URLs are restricted to HTTPS task paths on chatgpt.com.

For remote computer names, the helper reads the existing file-backed Codex ChatGPT access token and account ID from `CODEX_HOME/auth.json`. It sends only a GET to `https://chatgpt.com/backend-api/codex/remote/control/environments`, rejects redirects and does not refresh, modify, log or copy authentication data. Only host IDs/names, timestamps and a SHA-256 account binding are cached in `remote-hosts.json` with mode 0600. Caches are isolated by account; failed lookups retain the last names for the same account and use bounded retry delays. A missing session or unavailable catalog yields a distinguishable host-ID fallback. The catalog is an internal Codex route and can change. No diagnostics should include raw catalog responses or sign-in files.

Unread status is read from Codex’s identity-scoped saved read state and per-thread read metadata. The helper derives the existing identity binding from ID/access-token claims in memory without logging, persisting or sending those claims. Ambiguous retired execution-host keys are not merged. It does not mark a chat read or create a notification.

Pinned chat IDs, kinds and host IDs are saved only in this app’s preferences. Pin/unpin does not alter Codex’s sidebar or read receipts. Chat titles, status and recency stay in memory. Saved Codex app state can contain other sensitive fields; only selected metadata is extracted, and no raw state is logged or copied into this repository. UI preferences are stored locally; login changes affect only this app’s LaunchAgent.

The repository contains source code, scripts, documentation, and a synthetic UI preview. It must never contain an auth store, bearer token, API key, account identifier, personal filesystem path, live status file or daily ledger, browser state, or raw account response. Build and distribution directories are ignored by Git; a release package should contain only the newly built app bundle.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** option when it is enabled. If private reporting is not available, open an issue asking for a private reporting channel **without including exploit details or sensitive information**. Do not post credentials, screenshots of private content, or full account diagnostics.

## Maintainer release checks

1. Run `bash scripts/test.sh` and `bash scripts/package.sh` from a clean checkout.
2. Inspect staged files and the entire Git history for secrets and private data.
3. Confirm the archive contains only the app and no AppleDouble files, diagnostic state, or credentials.
4. Verify the bundle signature and inspect the binary for personal build paths.
5. Publish the checksum with the release. Ad-hoc signing is not Developer ID signing or notarization; document that limitation accurately.

## Windows port

The Windows port packages Electron with a sandboxed, isolated renderer, disabled Node integration, restrictive Content Security Policy, denied permission prompts and navigation, validated main-frame IPC and a fixed set of local UI resources served through a secure custom protocol. Titles are inserted as text, never HTML. The main process only opens validated identities from the latest fetched chat list. Shell execution is disabled; Codex must resolve to an absolute native executable. External sign-in and metadata handling use the same read-only helper and account-scoped host cache described above. Windows files inherit the per-user local application-data directory ACL. Demo and desktop-test modes use synthetic data and suppress live reads, real navigation and persistence. See `windows/README.md` for the Windows metadata freshness and portable startup limitations.
