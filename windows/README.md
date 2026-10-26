# notchGPT for Windows — preview 1

A Windows desktop port matching the macOS 2.1.0 design: two 76-DIP side extensions, 32-DIP circles, 38-DIP header, 344-DIP dropdown body, continuous rounded surface, the same statistics columns, sixteen half-hour bars, chat cards and slow attention pulses. A 208-DIP black center recreates the physical notch. Windows scales DIPs according to display scaling; fonts and native material rendering follow Windows.

## Run

1. Download the ZIP matching your PC: `windows-x64` for Intel/AMD, `windows-arm64` for Windows on ARM.
2. Extract the **whole ZIP** to a stable folder, for example a folder under your user profile. Open `notchGPT.exe`; do not run it inside the ZIP.
3. Install Codex CLI using its official instructions and sign in there. No sign-in form or new API key is needed in notchGPT.
4. If the CLI is not found, set the user environment variable `CODEX_BIN` to the absolute path of the native **codex.exe**, then restart notchGPT. A `.cmd`, `.bat` or PowerShell wrapper is deliberately not executed through a shell.

The app runs without a console or taskbar button. Use the notification-area icon to reopen it, refresh, open Settings or quit. It stays centered at the top of the primary display. Click the percentage dials, chat icon or Settings icon; Escape and outside clicks close the dropdown. Hover is optional and off by default. Launch at login is opt-in for this portable Windows build and refers to its current executable path; disable it before moving the folder.

Windows 11 22H2 or later supports the native acrylic backdrop; older supported Windows versions use the dark surface fallback. The app and included Electron runtime do not require a separate Node.js or .NET installation. Packages are not Authenticode signed.

## Behavior and privacy

- Official quota windows are read with the existing Codex `app-server` protocol using only initialize and `account/rateLimits/read` calls. No chat turn is started or approved.
- The shared Node metadata helper reads Codex databases with read-only SQLite connections. Pin identities are kept separately from Codex's sidebar. Links open the original host-aware Codex deep link or a validated cloud task path.
- The helper reads existing sign-in information only for the same documented read-only computer-name catalog as the Mac version. It never writes or refreshes sign-in data. Renderer code cannot access Node, filesystem, arbitrary URLs or credentials.
- Preferences, host cache and a percentage-only ledger are stored in `%LOCALAPPDATA%\notchGPT`. No chat titles, messages or authentication tokens are saved by this port. Windows ACLs inherit from the user's local application-data folder.
- Windows local running/input status is the last state in Codex metadata. The macOS advisory writer-lock check is unavailable on Windows; the port does not claim a live process subscription. Remote status has the same saved-state limitation on both platforms.
- Official quota is unavailable when the CLI or sign-in is unavailable. New daily history begins with an honest baseline, rather than importing or inventing Mac history.
- Daily calculations retain the Mac work schedule: Monday–Friday, 09–13 and 14–18, 20 weekly percentage points/day and 10/block. Corrections, reset jitter, gaps and partial observation are handled conservatively. Bars retain observed zero separately from missing data.

## Build and checks

```sh
cd windows
npm ci
npm test
npm run test:desktop
npm run dist
```

`npm run demo` uses only synthetic data, never reads live Codex state, never opens real chat links and never saves preferences. `test:desktop` exercises all five panel states, geometry, scrolling and Escape behavior, and captures synthetic screenshots. Set `NOTCHGPT_TEST_OUTPUT` to choose its output directory. Native Windows CI runs these checks and publishes x64/ARM64 ZIPs with SHA-256 files only after they pass. The live Codex account and actual PC display configuration still need checking on the target machine.

To remove the portable app, first turn off Launch at login, quit using the tray menu, and delete the extracted folder. Delete `%LOCALAPPDATA%\notchGPT` separately if you also want to remove settings and usage history. Codex sign-in is untouched.
