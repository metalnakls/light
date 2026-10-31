# Release workflow

`VERSION` is the release version and supplies both bundle version fields. Reserve one version per release; fixes to a pending release keep that version. Version 2 was explicitly requested. Local builds and commits do not allocate versions.

Distribution follows Glass and Yina: a ZIP with a stable download filename, a minimal GitHub Pages website, and Sparkle's EdDSA-signed update feed. No Developer ID identity is currently available on this Mac; describe the Gatekeeper setup honestly. Never silently replace a configured signing identity after a failure.

Prepare and validate before publication. Commit independent features separately, naming the release commit `two`. Publication requires user authorization and the shared even-minute rule. Do not overwrite an existing release or tag.
