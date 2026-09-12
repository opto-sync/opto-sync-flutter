# opto-sync-flutter

Flutter for mobile, desktop, and mobile web. No React. UI lives in `lib/src/`.

The app shell's sync ownership is controlled by one fail-closed lifecycle
machine in `lib/src/state/sync_lifecycle.dart`. Its phase/event projection is
checked against the canonical Quint model under `formal/`; native analyzer
rules reject non-exhaustive enum switches and default arms.

## Android release boundary

Android release tasks fail closed unless all five protected signing inputs are
present and the keystore certificate matches a separately approved SHA-256
fingerprint. The manual `Android beta AAB` workflow uses the protected
`mobile-release` environment, validates the formal/source and signing policy,
requires an explicit semantic version plus positive build number, verifies the
bundle signature, and retains the AAB, checksums, manifest, and obfuscation
symbols for 30 days. It does not upload to Google Play.

The current application ID, `dev.codexsweep.opto_sync_opto_sync_flutter`, is a
placeholder and must not be registered or treated as production authority.
Package-name approval, production-key custody, GitHub environment configuration,
Play registration/internal-track rollout, provider read-back, and real-device
acceptance are separate gates. Never create or upload a production signing key
from this repository.
