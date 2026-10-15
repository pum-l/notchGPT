# Contributing

Keep the widget small: readable white text, a dark-glass notch extension, and a click menu. New features should preserve accurate quota reporting and keep account data local.

## Before submitting a pull request

```sh
bash scripts/test.sh
bash scripts/package.sh
```

Test the following manually when UI, polling, or lifecycle behavior changes:

- Run `build/notchGPT.app/Contents/MacOS/notchGPT --test-hover` on a notched Mac to verify ten animation cycles and intermediate screen-space readout anchoring.
- The panel touches the left notch edge and uses the built-in display when external monitors are the main screen.
- Switching Spaces, full-screen apps, screen configuration changes, and wake do not move the widget to the wrong monitor.
- Startup reads usage; the minute timer and Refresh Now update the timestamp.
- Disconnection or invalid data clears the percentage instead of presenting an old number as fresh.
- Daily spending counts only 09–13 and 14–18, survives a restart, rolls over at local midnight, and hides on weekends; partial baselines are explained in the menu.
- The labels align on the left and both percentages share the same right edge.
- Quit closes the widget and its child; login startup and removal work with the scripts.

Do not add credentials, user-specific paths, real account responses, or live screenshots to fixtures. Use synthetic data. Pure quota tests do not require an OpenAI account; CI must not make authenticated usage calls.

The project uses Swift 5 language compatibility mode with AppKit and macOS 13 as the deployment target. Avoid third-party dependencies unless their benefit clearly warrants the added maintenance.
