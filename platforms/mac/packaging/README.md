# macOS Packaging

完整中文操作手册见 [`../../../docs/macOS打包发布手册.md`](../../../docs/macOS打包发布手册.md)。

本目录目前没有自动打包脚本，正式发布按手册中的命令执行。

## Commercial policy bootstrap

`Resources/Commercial/commercial-policy-bootstrap.json` is signed with the backend's
development/test key and is only valid for Debug and tests. It is not a production
release credential.

Before a Release build, download a fresh envelope from the production commercial
policy endpoint, replace that file without reserializing its payload, and provide
the matching `XX_COMMERCIAL_PRODUCTION_SIGNING_PUBLIC_KEY_<KEY_SUFFIX>` setting.
Both the previous and current key IDs may coexist in `XXCommercialSigningPublicKeys`
during rotation. The generated Release build phase reads that same built Info.plist
key dictionary, selects the envelope's `keyId`, and verifies the production
signature, the 30-day maximum window, and at least 14 days
of validity remaining; packaging fails if any check does not pass.

Planned deliverables:

- `.app` from Xcode build
- signed release build
- notarized release build
- `.dmg` assembly script
