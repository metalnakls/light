# Light

Read `/Users/wsb/.codex/AGENTS.md` at task start when present.

## Delivery

Keep one feature or fix per commit. Use short lowercase commit names; the version 2 release commit is `two`. Preserve unrelated work. Follow the shared even-minute rule for commits, pushes, and releases, using Europe/Moscow time. Ask for exact branch names before creating branches. Push only with explicit authorization; show each proposed PR and obtain approval immediately before posting it.

## Product

Light controls an existing macOS VPN profile; it does not install profiles or handle credentials. Never change this machine's network while developing without the exact approval and verified two-minute rollback required by the shared rules. Offline tests must not start or stop a VPN.

The dot hides only after macOS reports disconnection. Clicking it requests disconnection; right-click and reopening the app expose settings. Keep failure red, with a distinct shape, and keep the indicator free of shadows. Screen sampling is opt-in and stays in memory.

## Releases

Keep one version for the entire pending release. Update checks and automatic downloads default to enabled; preserve the user's later preference. Keep signing keys in Keychain, never in the repository.
