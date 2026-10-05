# ShareLink build progress

| Task | Status | Evidence |
| --- | --- | --- |
| 1. Project scaffold, package skeleton, hygiene, CI | done | `swift test --filter ShareLinkKitTests`: 2 tests passed. Simulator `xcodebuild` (`CODE_SIGNING_ALLOWED=NO`, `-derivedDataPath build/DerivedData`) exit 0. PlugIns contains no `.framework`; `ShareLink.app/Frameworks` contains `AMSMB2.framework`. Extension post-build strip was sufficient (no project-definition change). `check-secrets.sh` exit 0. |
| 2. Config models and managed configuration parser | pending | |
| 3. ConfigStore, credentials, managed feedback | pending | |
| 4. SMB client abstraction, error model, fake client | pending | |
| 5. AMSMB2 client, error mapping, Samba integration tests | pending | |
| 6. Versions, hidden names, item records, metadata store | pending | |
| 7. Folder scanner | pending | |
| 8. File Provider items, errors, connection provider, provider engine | pending | |
| 9. File Provider extension wiring | pending | |
| 10. Domain reconciliation and the app model | pending | |
| 11. SwiftUI app — servers, sign-in, server forms, detail | pending | |
| 12. Browser, Quick Look, settings, diagnostics, acknowledgements | pending | |
| 13. Documentation, MDM artifacts, licensing | pending | |
| 14. TestFlight pipeline | pending | |

Task 1 notes: both Info.plists also include `CFBundleDevelopmentRegion` and `CFBundleInfoDictionaryVersion`. `Packages/ShareLinkKit/Package.resolved` is committed (AMSMB2 4.0.3, GRDB.swift 7.11.1).
