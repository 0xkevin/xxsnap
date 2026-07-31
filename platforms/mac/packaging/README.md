# macOS Packaging

## Commercial policy bootstrap

`Resources/Commercial/commercial-policy-bootstrap.json` is signed with the backend's
development/test key and is only valid for Debug and tests. It is not a production
release credential.

Before a Release build, download a fresh envelope from the production commercial
policy endpoint, replace that file without reserializing its payload, and provide
`XX_COMMERCIAL_PRODUCTION_SIGNING_PUBLIC_KEY`. The generated Release build phase
verifies the production signature, the 30-day maximum window, and at least 14 days
of validity remaining; packaging fails if any check does not pass.

Planned deliverables:

- `.app` from Xcode build
- signed release build
- notarized release build
- `.dmg` assembly script
