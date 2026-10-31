# Release workflow

`VERSION` is the release version and supplies both bundle version fields. Reserve one version per release; fixes to a pending release keep that version. Version 2 was explicitly requested. Local builds and commits do not allocate versions.

Distribution follows Glass and Yina: a ZIP with a stable download filename, a minimal GitHub Pages website, and Sparkle's EdDSA-signed update feed. No Developer ID identity is currently available on this Mac; describe the Gatekeeper setup honestly. Never silently replace a configured signing identity after a failure.

Prepare and validate before publication. Commit independent features separately, naming the release commit `two`. Publication requires user authorization and the shared even-minute rule. Do not overwrite an existing release or tag.

## Commands

- `scripts/check.sh` runs offline policy checks, shell syntax checks, and plist validation. It does not connect or disconnect a VPN.
- `scripts/build.sh development` requires `LIGHT_CODESIGN_IDENTITY`, verifies that exact identity, and signs the final universal app inside-out.
- `scripts/build.sh distribution` deliberately uses ad-hoc signatures, matching the existing apps' non-notarized distribution. This is a separate delivery lane, not a fallback after signing failure.
- `scripts/install.sh [verified-app-path]` installs into `/Applications/Utilities/Light.app`. Without a path it builds the development lane first. It retains no backups; the previous app exists only during the verified replacement transaction and is removed on success.
- `scripts/release.sh prepare` builds the distribution lane, verifies the Keychain public key against the app, signs the ZIP and appcast, and records checksums plus the source commit. It does not publish.
- Commit the reserved version and release files as `two`, then prepare from that exact clean source commit. After authorized push, run `LIGHT_PUBLISH_APPROVED=yes scripts/release.sh publish` at an allowed minute. The script refuses changed sources, modified artifacts, existing releases, and an unpublished source commit.

The public website is `site/`; `.github/workflows/pages.yml` deploys it with GitHub Pages Actions. Set the repository Pages build type to `workflow` before the first deployment.

Both bundle version fields are populated from `VERSION` by the build script. Release `2` uses tag `v2`. Keep the download asset name `Light.zip`; appcast enclosures use the immutable versioned URL. The signed appcast and checksums are attached to the same release. Sparkle keys remain in the login Keychain.

## Verification limits

Check universal architectures, nested signatures, archive extraction, update signatures, and feed URLs before publication. Live connect/disconnect tests require exact approval and the independent two-minute rollback specified in the shared rules. GUI, hotkey delivery, screen permission, and adaptive appearance need live verification; compilation is not evidence of those behaviors.

Ad-hoc distribution retains hardened runtime and adds only the library-validation exception needed to load Sparkle without a Team ID. Development signing does not use that exception. The build and installer execute `Light --self-check` to catch dyld/signing failures before delivery; this check creates no windows and never touches the VPN.
