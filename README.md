# opto-sync-flutter

Flutter for mobile, desktop, and mobile web. No React. UI lives in `lib/src/`.

The app shell's sync ownership is controlled by one fail-closed lifecycle
machine in `lib/src/state/sync_lifecycle.dart`. Its phase/event projection is
checked against the canonical Quint model under `formal/`; native analyzer
rules reject non-exhaustive enum switches and default arms.
