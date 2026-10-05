# ShareLink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execution in this project:** each task is implemented by the Grok Build CLI (`grok-4.7`, high reasoning) from a task prompt, and reviewed by Claude before the next task starts. Implementers record evidence in `docs/PROGRESS.md`.

**Goal:** Build ShareLink, a free open-source iOS/iPadOS app. It connects to SMB shares, exposes them in the Files app through a replicated File Provider extension so Office can open and save documents in place, and accepts server settings from MDM managed app configuration.

**Architecture:** All non-UI logic lives in the local Swift package `Packages/ShareLinkKit`:
- config parsing and storage
- credentials
- the SMB client wrapper over AMSMB2/libsmb2
- the GRDB metadata store
- folder diffing
- the File Provider engine and items
- domain reconciliation
- the app's view model

It is tested on macOS with `swift test`. The XcodeGen project (`project.yml`) defines a thin SwiftUI app target and a thin `NSFileProviderReplicatedExtension` target that both link the package.

**Tech Stack:** Swift 6, SwiftUI, FileProvider, AMSMB2 4.0.3 (LGPL-2.1, dynamic), GRDB.swift 7.11.1 (MIT), Swift Testing, XcodeGen, Docker Samba for integration tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-05-sharelink-design.md`. Read it before any task.

## Global Constraints

- Minimum deployment: iOS/iPadOS 17.0; package also declares macOS 14 for tests.
- Swift language mode 6 (strict concurrency) in package and targets.
- Bundle IDs:
  - App: `com.ajthom90.sharelink`
  - Extension: `com.ajthom90.sharelink.FileProvider`
- App Group: `group.com.ajthom90.sharelink`. It is also used as the Keychain access group.
- Dependencies are exactly: AMSMB2 `exact: "4.0.3"`, GRDB.swift `exact: "7.11.1"`. No other third-party code.
- `import AMSMB2` appears only in `Sources/ShareLinkKit/SMB/AMSMB2Client.swift` and `Sources/ShareLinkKit/SMB/SMBErrorMapper.swift`.
- The repo is PUBLIC:
  - Never commit Team IDs, real hostnames, org names, credentials, `.p8` keys, or `Config/Local.xcconfig`.
  - Examples use `files.example.com`, `EXAMPLE`, and `jdoe`.
  - The Samba test password `ShareLink-Test-1` is the only credential allowed in the repo.
- `ITSAppUsesNonExemptEncryption = NO` in the app and extension Info.plists.
- Passwords never go into logs, UserDefaults, the metadata DB, or diagnostics output.
- The extension must not contain a nested `Frameworks/` folder in the archived app.
- Managed config keys are exactly as in spec §4 (`Host`, `Share`, `Path`, `DisplayName`, `Port`, `Domain`, `Username`, `UsernameLocked`, `RequireEncryption`, `AllowUserServers`, `SupportMessage`, prefix `ShareN.` for N = 2…10).
- Git identity in this repo is already configured; do not change it. Do not push. Commit after each green task.
- Every commit message ends with these two lines:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01ShkPPekg8BqrktHxoabFNB
  ```

## Review Focus

1. **Office/Windows "replace-save" on the server** (temp file renamed over the original, new file ID, same name). The item must keep its identifier and be reported as *updated*, not deleted and re-created. Owner: Task 7 test `replaceSaveKeepsIdentifier`.
2. **Wrong password vs. server down.** libsmb2 maps `STATUS_LOGON_FAILURE` to `ECONNREFUSED`, the same errno as a refused TCP connection. Users must see "sign in again" for bad credentials and "server unreachable" for network failure. Owner: Task 5 tests `logonFailureIsAuth` and `refusedTCPIsUnreachable`, plus integration `wrongPasswordIsAuthenticationFailed`.
3. **Overwriting a larger file with smaller content.** The result must be exactly the new content (truncated), streamed without loading the file into memory. Owner: Task 5 integration test `overwriteTruncates`.
4. **MDM values arriving as strings with stray whitespace, backslashes, or leading/trailing slashes** (Miradore types everything by hand). They must parse to the same config. Owner: Task 2 test `lenientValuesAndPathNormalization`.
5. **Renaming a folder in Files when its children are already known.** Descendants keep their identifiers and get new paths, so a later fetch of a child downloads from the new location. Owner: Task 6 test `renameDirectoryRewritesDescendantPaths` and Task 8 test `renameFolderThenFetchChild`.

---

## File Structure

```
.gitignore                         (exists)
LICENSE                            MIT
README.md
THIRD_PARTY_LICENSES.md
project.yml                        XcodeGen definition
Config/Base.xcconfig               shared build settings, includes Local.xcconfig if present
Config/Local.xcconfig.example      template for DEVELOPMENT_TEAM
.env.example                       App Store Connect API key variable names
TestServer.example.json            template for manual real-server testing
App/ShareLink/                     SwiftUI app target
  ShareLinkApp.swift               @main, AppModel wiring, scene phase, URL handling
  Info.plist, ShareLink.entitlements, PrivacyInfo.xcprivacy
  Assets.xcassets/                 AppIcon, AccentColor
  Platform/FileProviderDomainManager.swift   DomainManaging over NSFileProviderManager
  Platform/ManagedConfigObserver.swift       watches com.apple.configuration.managed
  Views/RootView.swift, WelcomeView.swift, ServerRow.swift, SignInView.swift,
        ServerFormView.swift, ServerDetailView.swift, BrowserView.swift,
        QuickLookView.swift, SettingsView.swift, AcknowledgementsView.swift
Extensions/FileProvider/           File Provider extension target
  FileProviderExtension.swift      NSFileProviderReplicatedExtension → ProviderEngine
  FileProviderEnumerator.swift     NSFileProviderEnumerator → ProviderEngine
  Info.plist, FileProvider.entitlements, PrivacyInfo.xcprivacy
Packages/ShareLinkKit/
  Package.swift
  Sources/ShareLinkKit/
    Support/AppGroup.swift          constants + container URLs
    Support/Log.swift               os.Logger + shared diagnostic log file
    Support/Diagnostics.swift       redacted diagnostics report
    Support/Acknowledgements.swift  bundled licence texts
    Config/LenientValue.swift       tolerant Any → String/Int/Bool
    Config/SMBPath.swift            path normalize/join/parent
    Config/ServerConfig.swift       ServerConfig, ServerSource, ManagedConfiguration
    Config/ManagedConfigParser.swift
    Config/ConfigStore.swift
    Config/ManagedFeedback.swift
    Credentials/CredentialStore.swift  Credential, CredentialStoring, Keychain + InMemory
    SMB/SMBClient.swift             protocol, RemoteEntry, SMBError, SMBClientFactory
    SMB/SMBErrorMapper.swift        POSIXError/AMSMB2 error → SMBError
    SMB/AMSMB2Client.swift          AMSMB2-backed SMBClient + factory
    SMB/ConnectionTester.swift
    Sync/HiddenNames.swift
    Sync/ItemVersion.swift
    Sync/ItemRecord.swift           ItemRecord, ChangeRecord
    Sync/MetadataStore.swift        GRDB store
    Sync/FolderScanner.swift        pure diff
    FileProvider/FileProviderItem.swift
    FileProvider/FileProviderErrors.swift
    FileProvider/ConflictNamer.swift
    FileProvider/ConnectionProvider.swift
    FileProvider/ProviderEngine.swift
    App/DomainReconciler.swift      DomainManaging protocol + reconciler
    App/AppModel.swift              @Observable view model
    Resources/Licenses/*.txt
  Tests/ShareLinkKitTests/          unit tests (+ Fakes/FakeSMBClient.swift, FakeDomainManager.swift)
  Tests/ShareLinkIntegrationTests/  Samba + optional real-server tests
Tests/Samba/                        Dockerfile, smb.conf, docker-compose.yml
MDM/README.md, MDM/sharelink-appconfig.xml, MDM/example-managed-config.plist
docs/PROGRESS.md, docs/TESTING.md, docs/RELEASING.md, docs/privacy.md
scripts/check-secrets.sh, scripts/testflight.sh, scripts/ExportOptions.plist,
scripts/package-third-party-sources.sh, scripts/make-icon.swift
.github/workflows/ci.yml
```

---

### Task 1: Project scaffold, package skeleton, hygiene, CI

**Files:**
- Create: `LICENSE`, `Config/Base.xcconfig`, `Config/Local.xcconfig.example`, `.env.example`, `TestServer.example.json`, `project.yml`
- Create: `Packages/ShareLinkKit/Package.swift`, `Packages/ShareLinkKit/Sources/ShareLinkKit/Support/AppGroup.swift`, `Packages/ShareLinkKit/Tests/ShareLinkKitTests/AppGroupTests.swift`, `Packages/ShareLinkKit/Tests/ShareLinkIntegrationTests/Placeholder.swift`
- Create: `App/ShareLink/ShareLinkApp.swift` (temporary minimal view), `App/ShareLink/Info.plist`, `App/ShareLink/ShareLink.entitlements`, `App/ShareLink/PrivacyInfo.xcprivacy`, `App/ShareLink/Assets.xcassets/{Contents.json,AccentColor.colorset/Contents.json,AppIcon.appiconset/Contents.json,AppIcon.appiconset/AppIcon.png}`
- Create: `Extensions/FileProvider/FileProviderExtension.swift` (stub), `Extensions/FileProvider/FileProviderEnumerator.swift` (stub), `Extensions/FileProvider/Info.plist`, `Extensions/FileProvider/FileProvider.entitlements`, `Extensions/FileProvider/PrivacyInfo.xcprivacy`
- Create: `scripts/check-secrets.sh`, `scripts/make-icon.swift`, `.github/workflows/ci.yml`, `docs/PROGRESS.md`

**Interfaces:**
- Produces: `AppGroup.identifier: String`, `AppGroup.deviceModelKey: String` (= `"deviceModel"`), `AppGroup.containerURL() -> URL`, `AppGroup.domainDirectory(for serverID: String) -> URL`, `AppGroup.defaults() -> UserDefaults`; package product `ShareLinkKit`; XcodeGen targets `ShareLink` and `ShareLinkFileProvider`.

- [ ] **Step 1: Package manifest**

`Packages/ShareLinkKit/Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShareLinkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShareLinkKit", targets: ["ShareLinkKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git", exact: "4.0.3"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "ShareLinkKit",
            dependencies: [
                .product(name: "AMSMB2", package: "AMSMB2"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Resources/Licenses")]
        ),
        .testTarget(name: "ShareLinkKitTests", dependencies: ["ShareLinkKit"]),
        .testTarget(name: "ShareLinkIntegrationTests", dependencies: ["ShareLinkKit"]),
    ]
)
```

Create `Sources/ShareLinkKit/Resources/Licenses/ShareLink-MIT.txt` with the MIT text (Task 13 adds the rest).

- [ ] **Step 2: Failing test for AppGroup**

`Tests/ShareLinkKitTests/AppGroupTests.swift`:

```swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct AppGroupTests {
    @Test func identifierIsStable() {
        #expect(AppGroup.identifier == "group.com.ajthom90.sharelink")
    }

    @Test func domainDirectoryIsUnderContainerAndSanitized() {
        let dir = AppGroup.domainDirectory(for: "managed-1-abc/../x")
        #expect(dir.path.hasPrefix(AppGroup.containerURL().path))
        #expect(!dir.lastPathComponent.contains("/"))
        #expect(dir.deletingLastPathComponent().lastPathComponent == "Domains")
    }
}
```

Run: `cd Packages/ShareLinkKit && swift test --filter AppGroupTests`
Expected: FAIL (cannot find `AppGroup`).

- [ ] **Step 3: Implement AppGroup**

`Sources/ShareLinkKit/Support/AppGroup.swift`:

```swift
import Foundation

public enum AppGroup {
    public static let identifier = "group.com.ajthom90.sharelink"
    public static let deviceModelKey = "deviceModel"

    /// App Group container; falls back to a temp directory when the entitlement is
    /// missing (unit tests on macOS, previews).
    public static func containerURL() -> URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("ShareLinkAppGroup", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static func domainDirectory(for serverID: String) -> URL {
        let safe = serverID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return containerURL()
            .appendingPathComponent("Domains", isDirectory: true)
            .appendingPathComponent(String(safe), isDirectory: true)
    }

    public static func defaults() -> UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
```

`Tests/ShareLinkIntegrationTests/Placeholder.swift` contains one `@Test func placeholder() {}` so the target compiles (Task 5 replaces it).

Run: `cd Packages/ShareLinkKit && swift test --filter AppGroupTests` → PASS.

- [ ] **Step 4: Build settings and templates**

`Config/Base.xcconfig`:

```
MARKETING_VERSION = 1.0.0
CURRENT_PROJECT_VERSION = 1
SWIFT_VERSION = 6.0
IPHONEOS_DEPLOYMENT_TARGET = 17.0
TARGETED_DEVICE_FAMILY = 1,2
CODE_SIGN_STYLE = Automatic
// Developer-specific values (Team ID) live in the git-ignored Local.xcconfig.
#include? "Local.xcconfig"
```

`Config/Local.xcconfig.example`:

```
// Copy to Config/Local.xcconfig (git-ignored) and set your Apple Developer Team ID.
// DEVELOPMENT_TEAM = <your 10-character Team ID>
```

`.env.example`:

```
# Copy to .env (git-ignored). App Store Connect API key for scripts/testflight.sh
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_KEY_PATH=/absolute/path/to/AuthKey_XXXX.p8
BUILD_OFFSET=0
```

`TestServer.example.json`:

```json
{
  "host": "files.example.com",
  "port": 445,
  "share": "Shared",
  "path": "",
  "domain": "EXAMPLE",
  "username": "jdoe",
  "password": "",
  "requireEncryption": false
}
```

`LICENSE`: standard MIT text, `Copyright (c) 2026 Andrew J. Thom and ShareLink contributors`.

- [ ] **Step 5: Targets**

`project.yml`:

```yaml
name: ShareLink
options:
  bundleIdPrefix: com.ajthom90
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
configFiles:
  Debug: Config/Base.xcconfig
  Release: Config/Base.xcconfig
packages:
  ShareLinkKit:
    path: Packages/ShareLinkKit
targets:
  ShareLink:
    type: application
    platform: iOS
    sources:
      - App/ShareLink
    info:
      path: App/ShareLink/Info.plist
    entitlements:
      path: App/ShareLink/ShareLink.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ajthom90.sharelink
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        GENERATE_INFOPLIST_FILE: NO
    dependencies:
      - package: ShareLinkKit
      - target: ShareLinkFileProvider
  ShareLinkFileProvider:
    type: app-extension
    platform: iOS
    sources:
      - Extensions/FileProvider
    info:
      path: Extensions/FileProvider/Info.plist
    entitlements:
      path: Extensions/FileProvider/FileProvider.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ajthom90.sharelink.FileProvider
        APPLICATION_EXTENSION_API_ONLY: YES
        GENERATE_INFOPLIST_FILE: NO
    dependencies:
      - package: ShareLinkKit
    postBuildScripts:
      - name: Strip nested frameworks (AMSMB2 is embedded in the app)
        script: |
          rm -rf "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
        basedOnDependencyAnalysis: false
schemes:
  ShareLink:
    build:
      targets:
        ShareLink: all
        ShareLinkFileProvider: all
    archive:
      config: Release
```

`App/ShareLink/Info.plist` keys:
- `CFBundleDisplayName` = `ShareLink`, `CFBundleShortVersionString` = `$(MARKETING_VERSION)`, `CFBundleVersion` = `$(CURRENT_PROJECT_VERSION)`
- `CFBundleIdentifier` = `$(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleExecutable` = `$(EXECUTABLE_NAME)`, `CFBundlePackageType` = `APPL`, `CFBundleName` = `$(PRODUCT_NAME)`
- `LSRequiresIPhoneOS` = true, `UILaunchScreen` = `{}`, `UIApplicationSceneManifest` = `{UIApplicationSupportsMultipleScenes: true}`
- `UISupportedInterfaceOrientations` (all four on iPad, portrait + both landscapes on iPhone, via the `~ipad` key variant)
- `ITSAppUsesNonExemptEncryption` = false
- `NSLocalNetworkUsageDescription` = "ShareLink connects to file servers on your local network."
- `CFBundleURLTypes` = one entry, `CFBundleURLSchemes` = [`sharelink`]

`Extensions/FileProvider/Info.plist`: same version/identity keys (`CFBundlePackageType` = `XPC!`), `CFBundleDisplayName` = `ShareLink`, `ITSAppUsesNonExemptEncryption` = false, `NSLocalNetworkUsageDescription` (same text), and

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key><string>com.apple.fileprovider-nonui</string>
  <key>NSExtensionPrincipalClass</key><string>$(PRODUCT_MODULE_NAME).FileProviderExtension</string>
  <key>NSExtensionFileProviderDocumentGroup</key><string>group.com.ajthom90.sharelink</string>
  <key>NSExtensionFileProviderSupportsEnumeration</key><true/>
</dict>
```

Both entitlements files:

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.ajthom90.sharelink</string></array>
```

Both `PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, `NSPrivacyTrackingDomains` [], `NSPrivacyCollectedDataTypes` [], `NSPrivacyAccessedAPITypes`:
- `NSPrivacyAccessedAPICategoryUserDefaults` with reasons `CA92.1` and `1C8F.1`
- `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`

Temporary stubs (replaced in Tasks 9 and 11):

```swift
// App/ShareLink/ShareLinkApp.swift
import SwiftUI
import ShareLinkKit

@main
struct ShareLinkApp: App {
    var body: some Scene {
        WindowGroup { Text("ShareLink") }
    }
}
```

```swift
// Extensions/FileProvider/FileProviderExtension.swift
import FileProvider
import ShareLinkKit

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    required init(domain: NSFileProviderDomain) { super.init() }
    func invalidate() {}
    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, NSFileProviderError(.noSuchItem)); return Progress()
    }
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, nil, NSFileProviderError(.noSuchItem)); return Progress()
    }
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return Progress()
    }
    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields, contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem)); return Progress()
    }
    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping ((any Error)?) -> Void) -> Progress {
        completionHandler(NSFileProviderError(.noSuchItem)); return Progress()
    }
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        throw NSFileProviderError(.noSuchItem)
    }
}
```

`Extensions/FileProvider/FileProviderEnumerator.swift`: empty file with `import FileProvider` (filled in Task 9).

- [ ] **Step 6: App icon**

`scripts/make-icon.swift` is a macOS script (`swift scripts/make-icon.swift App/ShareLink/Assets.xcassets/AppIcon.appiconset/AppIcon.png`). It renders a 1024×1024 PNG with:
- a vertical gradient from `#1E6FD9` to `#0B3D91`
- the SF Symbol `folder.fill` (white, 560 pt)
- the SF Symbol `link` (accent `#7FD1FF`, 300 pt) overlapping the folder's lower right

Use `NSImage(systemSymbolName:accessibilityDescription:)` with `NSImage.SymbolConfiguration(pointSize:weight:)`, and draw into an `NSBitmapImageRep` with no alpha in the corners (fully opaque square; iOS applies the mask). Commit the generated PNG.

`AppIcon.appiconset/Contents.json`:

```json
{ "images": [ { "filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" } ],
  "info": { "author": "xcode", "version": 1 } }
```

`AccentColor.colorset`: sRGB `#1E6FD9` (light) and `#5AA2FF` (dark appearance).

- [ ] **Step 7: Secret scanner**

`scripts/check-secrets.sh` (chmod +x):

```bash
#!/usr/bin/env bash
# Fails if tracked or about-to-be-committed files contain secrets or org-specific strings.
# Org-specific patterns live in the git-ignored .proprietary-patterns (one ERE per line).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

patterns=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}'
  'teamID</key>[[:space:]]*<string>[A-Z0-9]{10}'
)
if [[ -f .proprietary-patterns ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    patterns+=("$line")
  done < .proprietary-patterns
fi

status=0
while IFS= read -r -d '' file; do
  [[ "$file" == "scripts/check-secrets.sh" ]] && continue
  [[ -f "$file" ]] || continue
  for p in "${patterns[@]}"; do
    if grep -nIiE -- "$p" "$file" >/dev/null 2>&1; then
      echo "check-secrets: pattern matched in $file: $p" >&2
      status=1
    fi
  done
done < <(git ls-files -z --cached --others --exclude-standard)

if git ls-files --cached --others --exclude-standard | grep -E '\.(p8|p12|mobileprovision)$|(^|/)Local\.xcconfig$|\.local\.json$|(^|/)\.env$'; then
  echo "check-secrets: forbidden file is tracked" >&2
  status=1
fi
exit $status
```

Run: `./scripts/check-secrets.sh` → exit 0.

- [ ] **Step 8: CI**

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Secret scan
        run: ./scripts/check-secrets.sh
      - name: Package unit tests
        working-directory: Packages/ShareLinkKit
        run: swift test --filter ShareLinkKitTests
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Build app for simulator
        run: |
          xcodegen generate
          xcodebuild -project ShareLink.xcodeproj -scheme ShareLink \
            -destination 'generic/platform=iOS Simulator' \
            CODE_SIGNING_ALLOWED=NO build
```

`docs/PROGRESS.md`: heading `# ShareLink build progress`, then a table `| Task | Status | Evidence |` with rows for Tasks 1–14, all `pending`.

- [ ] **Step 9: Verify**

Run:
```bash
cd Packages/ShareLinkKit && swift test --filter ShareLinkKitTests && cd ../..
xcodegen generate
xcodebuild -project ShareLink.xcodeproj -scheme ShareLink -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet
./scripts/check-secrets.sh
```
Expected: tests pass, `** BUILD SUCCEEDED **`, scanner exit 0. Then confirm no nested frameworks:
`find ~/Library/Developer/Xcode/DerivedData/ShareLink-*/Build/Products/Debug-iphonesimulator/ShareLink.app/PlugIns -name '*.framework'` prints nothing.

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "Scaffold ShareLink project, package, CI, and secret scanning"
```

---

### Task 2: Config models and managed configuration parser

**Files:**
- Create: `Sources/ShareLinkKit/Config/LenientValue.swift`, `Config/SMBPath.swift`, `Config/ServerConfig.swift`, `Config/ManagedConfigParser.swift`
- Test: `Tests/ShareLinkKitTests/SMBPathTests.swift`, `Tests/ShareLinkKitTests/ManagedConfigParserTests.swift`

**Interfaces:**
- Produces:
  - `SMBPath.normalize(_:) -> String`, `SMBPath.join(_:_:) -> String`, `SMBPath.parent(of:) -> String`, `SMBPath.lastComponent(_:) -> String`
  - `enum ServerSource: Codable, Hashable, Sendable { case managed(slot: Int), user }`
  - `struct ServerConfig: Codable, Hashable, Identifiable, Sendable` with `id, source, displayName, host, port, share, rootPath, domain, username, usernameLocked, requireEncryption`, `isManaged`, `summary`
  - `struct ManagedConfiguration: Codable, Equatable, Sendable { servers, allowUserServers, supportMessage, issues; static let empty }`
  - `enum ManagedConfigParser { static func parse(_ dict: [String: Any]) -> ManagedConfiguration; static let maxShares = 10 }`
  - `ServerConfig.managedID(slot:host:share:rootPath:) -> String`

- [ ] **Step 1: Failing tests**

`Tests/ShareLinkKitTests/SMBPathTests.swift`:

```swift
import Testing
@testable import ShareLinkKit

@Suite struct SMBPathTests {
    @Test(arguments: [
        ("", ""), ("/", ""), ("Finance", "Finance"), ("/Finance/Reports/", "Finance/Reports"),
        ("Finance\\Reports", "Finance/Reports"), ("  //Finance//Reports  ", "Finance/Reports"),
        ("./Finance/./Reports", "Finance/Reports"),
    ])
    func normalize(input: String, expected: String) {
        #expect(SMBPath.normalize(input) == expected)
    }

    @Test func joinParentLast() {
        #expect(SMBPath.join("", "a.docx") == "a.docx")
        #expect(SMBPath.join("Finance", "a.docx") == "Finance/a.docx")
        #expect(SMBPath.join("Finance/", "/Q3/a.docx") == "Finance/Q3/a.docx")
        #expect(SMBPath.parent(of: "Finance/Q3/a.docx") == "Finance/Q3")
        #expect(SMBPath.parent(of: "a.docx") == "")
        #expect(SMBPath.lastComponent("Finance/Q3/a.docx") == "a.docx")
        #expect(SMBPath.lastComponent("") == "")
    }
}
```

`Tests/ShareLinkKitTests/ManagedConfigParserTests.swift`:

```swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ManagedConfigParserTests {
    @Test func singleShareWithDefaults() {
        let cfg = ManagedConfigParser.parse(["Host": "files.example.com", "Share": "Shared"])
        #expect(cfg.servers.count == 1)
        let s = cfg.servers[0]
        #expect(s.host == "files.example.com")
        #expect(s.share == "Shared")
        #expect(s.port == 445)
        #expect(s.rootPath == "")
        #expect(s.displayName == "Shared on files.example.com")
        #expect(s.source == .managed(slot: 1))
        #expect(s.requireEncryption == false)
        #expect(s.usernameLocked == false)
        #expect(cfg.allowUserServers == true)
        #expect(cfg.supportMessage == "")
        #expect(cfg.issues.isEmpty)
    }

    @Test func lenientValuesAndPathNormalization() {
        let cfg = ManagedConfigParser.parse([
            "Host": "  files.example.com ", "Share": " Shared ", "Path": "\\Finance\\Reports\\",
            "Port": "1445", "RequireEncryption": "YES", "UsernameLocked": 1,
            "Username": " jdoe ", "Domain": "EXAMPLE", "DisplayName": " Finance ",
            "AllowUserServers": "false", "SupportMessage": " Use your network password ",
        ])
        let s = cfg.servers[0]
        #expect(s.host == "files.example.com")
        #expect(s.share == "Shared")
        #expect(s.rootPath == "Finance/Reports")
        #expect(s.port == 1445)
        #expect(s.requireEncryption)
        #expect(s.usernameLocked)
        #expect(s.username == "jdoe")
        #expect(s.domain == "EXAMPLE")
        #expect(s.displayName == "Finance")
        #expect(cfg.allowUserServers == false)
        #expect(cfg.supportMessage == "Use your network password")
    }

    @Test func numberedShares() {
        let cfg = ManagedConfigParser.parse([
            "Host": "a.example.com", "Share": "One",
            "Share2.Host": "b.example.com", "Share2.Share": "Two", "Share2.Port": 4450,
            "Share10.Host": "c.example.com", "Share10.Share": "Ten",
            "Share11.Host": "ignored.example.com", "Share11.Share": "Ignored",
        ])
        #expect(cfg.servers.map(\.share) == ["One", "Two", "Ten"])
        #expect(cfg.servers.map(\.source) == [.managed(slot: 1), .managed(slot: 2), .managed(slot: 10)])
        #expect(cfg.servers[1].port == 4450)
    }

    @Test func missingRequiredKeysRecordIssues() {
        let cfg = ManagedConfigParser.parse(["Host": "a.example.com", "Share2.Share": "Two"])
        #expect(cfg.servers.isEmpty)
        #expect(cfg.issues.count == 2)
        #expect(cfg.issues.contains { $0.contains("Share 1") && $0.contains("Share") })
        #expect(cfg.issues.contains { $0.contains("Share 2") && $0.contains("Host") })
    }

    @Test func invalidPortFallsBackWithIssue() {
        let cfg = ManagedConfigParser.parse(["Host": "a.example.com", "Share": "S", "Port": "abc"])
        #expect(cfg.servers[0].port == 445)
        #expect(cfg.issues.count == 1)
    }

    @Test func emptyDictionaryIsEmptyConfig() {
        #expect(ManagedConfigParser.parse([:]) == .empty)
    }

    @Test func managedIDIsDeterministicAndContentSensitive() {
        let a = ServerConfig.managedID(slot: 1, host: "a.example.com", share: "S", rootPath: "")
        let b = ServerConfig.managedID(slot: 1, host: "A.EXAMPLE.COM", share: "S", rootPath: "")
        let c = ServerConfig.managedID(slot: 1, host: "a.example.com", share: "S", rootPath: "x")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hasPrefix("managed-1-"))
        #expect(a.count == "managed-1-".count + 12)
        let parsed = ManagedConfigParser.parse(["Host": "a.example.com", "Share": "S"])
        #expect(parsed.servers[0].id == a)
    }
}
```

Run: `swift test --filter "SMBPathTests|ManagedConfigParserTests"` → FAIL (symbols missing).

- [ ] **Step 2: Implement**

`Config/LenientValue.swift`:

```swift
import Foundation

/// Tolerant conversions for MDM values, which may arrive typed or as strings.
enum LenientValue {
    static func string(_ value: Any?) -> String? {
        let raw: String?
        switch value {
        case let s as String: raw = s
        case let n as NSNumber: raw = n.stringValue
        default: raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// nil = absent; .failure = present but unparseable.
    static func int(_ value: Any?) -> Result<Int, Error>? {
        guard let value else { return nil }
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return .success(n.intValue) }
        if let s = string(value), let i = Int(s) { return .success(i) }
        if string(value) == nil { return nil }
        return .failure(CocoaError(.formatting))
    }

    static func bool(_ value: Any?) -> Bool? {
        if let n = value as? NSNumber { return n.boolValue }
        guard let s = string(value)?.lowercased() else { return nil }
        if ["true", "yes", "1", "on"].contains(s) { return true }
        if ["false", "no", "0", "off"].contains(s) { return false }
        return nil
    }
}
```

`Config/SMBPath.swift`:

```swift
import Foundation

/// Share-relative paths: "/" separators, no leading/trailing slash, "" is the root.
public enum SMBPath {
    public static func normalize(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
            .joined(separator: "/")
    }

    public static func join(_ base: String, _ component: String) -> String {
        let a = normalize(base), b = normalize(component)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + "/" + b
    }

    public static func parent(of path: String) -> String {
        let p = normalize(path)
        guard let idx = p.lastIndex(of: "/") else { return "" }
        return String(p[..<idx])
    }

    public static func lastComponent(_ path: String) -> String {
        let p = normalize(path)
        guard let idx = p.lastIndex(of: "/") else { return p }
        return String(p[p.index(after: idx)...])
    }
}
```

`Config/ServerConfig.swift`:

```swift
import Foundation
import CryptoKit

public enum ServerSource: Codable, Hashable, Sendable {
    case managed(slot: Int)
    case user
}

public struct ServerConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var source: ServerSource
    public var displayName: String
    public var host: String
    public var port: Int
    public var share: String
    public var rootPath: String
    public var domain: String
    public var username: String
    public var usernameLocked: Bool
    public var requireEncryption: Bool

    public init(id: String, source: ServerSource, displayName: String, host: String, port: Int = 445,
                share: String, rootPath: String = "", domain: String = "", username: String = "",
                usernameLocked: Bool = false, requireEncryption: Bool = false) {
        self.id = id; self.source = source; self.displayName = displayName; self.host = host
        self.port = port; self.share = share; self.rootPath = SMBPath.normalize(rootPath)
        self.domain = domain; self.username = username; self.usernameLocked = usernameLocked
        self.requireEncryption = requireEncryption
    }

    public var isManaged: Bool {
        if case .managed = source { return true }
        return false
    }

    /// "host/share/path" for display.
    public var summary: String {
        ([host, share] + (rootPath.isEmpty ? [] : [rootPath])).joined(separator: "/")
    }

    public static func defaultDisplayName(host: String, share: String) -> String {
        "\(share) on \(host)"
    }

    public static func managedID(slot: Int, host: String, share: String, rootPath: String) -> String {
        let key = [host.lowercased(), share.lowercased(), SMBPath.normalize(rootPath).lowercased()].joined(separator: "|")
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return "managed-\(slot)-\(digest.prefix(12))"
    }

    public static func newUserID() -> String { "user-\(UUID().uuidString.lowercased())" }
}

public struct ManagedConfiguration: Codable, Equatable, Sendable {
    public var servers: [ServerConfig]
    public var allowUserServers: Bool
    public var supportMessage: String
    public var issues: [String]

    public init(servers: [ServerConfig] = [], allowUserServers: Bool = true, supportMessage: String = "", issues: [String] = []) {
        self.servers = servers; self.allowUserServers = allowUserServers
        self.supportMessage = supportMessage; self.issues = issues
    }

    public static let empty = ManagedConfiguration()
}
```

`Config/ManagedConfigParser.swift`:

```swift
import Foundation

public enum ManagedConfigParser {
    public static let maxShares = 10
    public static let managedConfigKey = "com.apple.configuration.managed"

    public static func parse(_ dict: [String: Any]) -> ManagedConfiguration {
        var result = ManagedConfiguration.empty
        result.allowUserServers = LenientValue.bool(dict["AllowUserServers"]) ?? true
        result.supportMessage = LenientValue.string(dict["SupportMessage"]) ?? ""

        for slot in 1...maxShares {
            let prefix = slot == 1 ? "" : "Share\(slot)."
            func value(_ key: String) -> Any? { dict[prefix + key] }
            let shareKeys = ["Host", "Share", "Path", "DisplayName", "Port", "Domain", "Username", "UsernameLocked", "RequireEncryption"]
            guard shareKeys.contains(where: { value($0) != nil }) else { continue }

            let host = LenientValue.string(value("Host"))
            let share = LenientValue.string(value("Share"))
            var missing: [String] = []
            if host == nil { missing.append("Host") }
            if share == nil { missing.append("Share") }
            if !missing.isEmpty {
                result.issues.append("Share \(slot): missing \(missing.map { prefix + $0 }.joined(separator: ", "))")
                continue
            }

            var port = 445
            switch LenientValue.int(value("Port")) {
            case .success(let p) where (1...65535).contains(p): port = p
            case .success, .failure:
                result.issues.append("Share \(slot): invalid \(prefix)Port, using 445")
            case nil: break
            }

            let rootPath = SMBPath.normalize(LenientValue.string(value("Path")) ?? "")
            result.servers.append(ServerConfig(
                id: ServerConfig.managedID(slot: slot, host: host!, share: share!, rootPath: rootPath),
                source: .managed(slot: slot),
                displayName: LenientValue.string(value("DisplayName")) ?? ServerConfig.defaultDisplayName(host: host!, share: share!),
                host: host!, port: port, share: share!, rootPath: rootPath,
                domain: LenientValue.string(value("Domain")) ?? "",
                username: LenientValue.string(value("Username")) ?? "",
                usernameLocked: LenientValue.bool(value("UsernameLocked")) ?? false,
                requireEncryption: LenientValue.bool(value("RequireEncryption")) ?? false
            ))
        }
        return result
    }
}
```

- [ ] **Step 3: Verify** — `swift test --filter "SMBPathTests|ManagedConfigParserTests"` → PASS.
- [ ] **Step 4: Commit** — `git commit -am "Add server config models and managed configuration parser"` (use `git add -A` first).

---

### Task 3: ConfigStore, credentials, managed feedback

**Files:**
- Create: `Config/ConfigStore.swift`, `Config/ManagedFeedback.swift`, `Credentials/CredentialStore.swift`
- Test: `Tests/ShareLinkKitTests/ConfigStoreTests.swift`, `Tests/ShareLinkKitTests/CredentialStoreTests.swift`, `Tests/ShareLinkKitTests/ManagedFeedbackTests.swift`

**Interfaces:**
- Consumes: `ServerConfig`, `ManagedConfiguration`, `AppGroup` (Task 1–2)
- Produces:
  - `final class ConfigStore: @unchecked Sendable` — `init(defaults: UserDefaults)`, `static func shared() -> ConfigStore`, `var managed: ManagedConfiguration { get set }`, `var userServers: [ServerConfig] { get set }`, `func allServers() -> [ServerConfig]`, `func server(id: String) -> ServerConfig?`, `func saveUserServer(_:)`, `func removeUserServer(id:)`
  - `struct Credential: Codable, Equatable, Sendable { username, password }`
  - `protocol CredentialStoring: Sendable { credential(for:) throws -> Credential?; setCredential(_:for:) throws; removeCredential(for:) throws }`
  - `struct KeychainCredentialStore: CredentialStoring { init(accessGroup: String? = AppGroup.identifier) }`
  - `final class InMemoryCredentialStore: CredentialStoring`
  - `enum ManagedFeedback { static let key = "com.apple.feedback.managed"; static func write(configuredShares:signedInShares:configErrors:appVersion:to:) }`

- [ ] **Step 1: Failing tests**

```swift
// ConfigStoreTests.swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ConfigStoreTests {
    func makeStore() -> ConfigStore {
        ConfigStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }
    let managedServer = ServerConfig(id: "managed-1-aaaaaaaaaaaa", source: .managed(slot: 1), displayName: "M", host: "m.example.com", share: "S")
    let userServer = ServerConfig(id: "user-1", source: .user, displayName: "U", host: "u.example.com", share: "S")

    @Test func roundTripsManagedAndUser() {
        let store = makeStore()
        store.managed = ManagedConfiguration(servers: [managedServer], allowUserServers: true, supportMessage: "Hi")
        store.saveUserServer(userServer)
        #expect(store.managed.supportMessage == "Hi")
        #expect(store.allServers().map(\.id) == [managedServer.id, userServer.id])
        #expect(store.server(id: "user-1") == userServer)
    }

    @Test func userServersHiddenWhenNotAllowed() {
        let store = makeStore()
        store.saveUserServer(userServer)
        store.managed = ManagedConfiguration(servers: [managedServer], allowUserServers: false)
        #expect(store.allServers().map(\.id) == [managedServer.id])
        #expect(store.server(id: "user-1") == nil)
    }

    @Test func saveReplacesAndRemoveDeletes() {
        let store = makeStore()
        store.saveUserServer(userServer)
        var edited = userServer; edited.displayName = "Edited"
        store.saveUserServer(edited)
        #expect(store.userServers.map(\.displayName) == ["Edited"])
        store.removeUserServer(id: "user-1")
        #expect(store.userServers.isEmpty)
    }
}
```

```swift
// CredentialStoreTests.swift
import Testing
@testable import ShareLinkKit

@Suite struct CredentialStoreTests {
    @Test func inMemoryRoundTrip() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.credential(for: "a") == nil)
        try store.setCredential(Credential(username: "jdoe", password: "pw"), for: "a")
        #expect(try store.credential(for: "a") == Credential(username: "jdoe", password: "pw"))
        try store.setCredential(Credential(username: "jdoe", password: "pw2"), for: "a")
        #expect(try store.credential(for: "a")?.password == "pw2")
        try store.removeCredential(for: "a")
        #expect(try store.credential(for: "a") == nil)
    }
}
```

```swift
// ManagedFeedbackTests.swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ManagedFeedbackTests {
    @Test func writesExpectedDictionary() {
        let defaults = UserDefaults(suiteName: "fb-\(UUID().uuidString)")!
        ManagedFeedback.write(configuredShares: 2, signedInShares: 1, configErrors: ["Share 2: missing Share2.Host"], appVersion: "1.0.0 (5)", to: defaults)
        let dict = defaults.dictionary(forKey: ManagedFeedback.key)
        #expect(dict?["ConfiguredShares"] as? Int == 2)
        #expect(dict?["SignedInShares"] as? Int == 1)
        #expect(dict?["ConfigErrors"] as? [String] == ["Share 2: missing Share2.Host"])
        #expect(dict?["AppVersion"] as? String == "1.0.0 (5)")
    }
}
```

Run: `swift test --filter "ConfigStoreTests|CredentialStoreTests|ManagedFeedbackTests"` → FAIL.

- [ ] **Step 2: Implement**

```swift
// Config/ConfigStore.swift
import Foundation

/// Normalized configuration shared between the app and the extension via App Group defaults.
public final class ConfigStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private enum Key { static let managed = "managedConfiguration.v1"; static let user = "userServers.v1" }

    public init(defaults: UserDefaults) { self.defaults = defaults }
    public static func shared() -> ConfigStore { ConfigStore(defaults: AppGroup.defaults()) }

    public var managed: ManagedConfiguration {
        get { lock.withLock { decode(ManagedConfiguration.self, Key.managed) ?? .empty } }
        set { lock.withLock { encode(newValue, Key.managed) } }
    }

    public var userServers: [ServerConfig] {
        get { lock.withLock { decode([ServerConfig].self, Key.user) ?? [] } }
        set { lock.withLock { encode(newValue, Key.user) } }
    }

    /// Managed servers first, then user servers when allowed.
    public func allServers() -> [ServerConfig] {
        let m = managed
        return m.servers + (m.allowUserServers ? userServers : [])
    }

    public func server(id: String) -> ServerConfig? { allServers().first { $0.id == id } }

    public func saveUserServer(_ server: ServerConfig) {
        var list = userServers
        if let i = list.firstIndex(where: { $0.id == server.id }) { list[i] = server } else { list.append(server) }
        userServers = list
    }

    public func removeUserServer(id: String) { userServers = userServers.filter { $0.id != id } }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
```

```swift
// Config/ManagedFeedback.swift
import Foundation

public enum ManagedFeedback {
    public static let key = "com.apple.feedback.managed"

    public static func write(configuredShares: Int, signedInShares: Int, configErrors: [String],
                             appVersion: String, to defaults: UserDefaults = .standard) {
        defaults.set([
            "ConfiguredShares": configuredShares,
            "SignedInShares": signedInShares,
            "ConfigErrors": configErrors,
            "AppVersion": appVersion,
        ] as [String: Any], forKey: key)
    }
}
```

```swift
// Credentials/CredentialStore.swift
import Foundation
import Security

public struct Credential: Codable, Equatable, Sendable {
    public var username: String
    public var password: String
    public init(username: String, password: String) { self.username = username; self.password = password }
}

public protocol CredentialStoring: Sendable {
    func credential(for serverID: String) throws -> Credential?
    func setCredential(_ credential: Credential, for serverID: String) throws
    func removeCredential(for serverID: String) throws
}

public struct KeychainError: Error, Equatable { public let status: OSStatus }

public struct KeychainCredentialStore: CredentialStoring {
    public static let service = "com.ajthom90.sharelink"
    private let accessGroup: String?

    public init(accessGroup: String? = AppGroup.identifier) { self.accessGroup = accessGroup }

    private func baseQuery(_ serverID: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: serverID,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public func credential(for serverID: String) throws -> Credential? {
        var q = baseQuery(serverID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    public func setCredential(_ credential: Credential, for serverID: String) throws {
        let data = try JSONEncoder().encode(credential)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(serverID) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            let add = baseQuery(serverID).merging(attrs) { $1 }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func removeCredential(for serverID: String) throws {
        let status = SecItemDelete(baseQuery(serverID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var items: [String: Credential] = [:]
    private let lock = NSLock()
    public init() {}
    public func credential(for serverID: String) throws -> Credential? { lock.withLock { items[serverID] } }
    public func setCredential(_ credential: Credential, for serverID: String) throws { lock.withLock { items[serverID] = credential } }
    public func removeCredential(for serverID: String) throws { lock.withLock { _ = items.removeValue(forKey: serverID) } }
}
```

- [ ] **Step 3: Verify** — `swift test --filter "ConfigStoreTests|CredentialStoreTests|ManagedFeedbackTests"` → PASS.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add config store, credential store, and managed feedback"`

---

### Task 4: SMB client abstraction, error model, fake client

**Files:**
- Create: `Sources/ShareLinkKit/SMB/SMBClient.swift`
- Create: `Tests/ShareLinkKitTests/Fakes/FakeSMBClient.swift`
- Test: `Tests/ShareLinkKitTests/FakeSMBClientTests.swift`

**Interfaces:**
- Produces:

```swift
public struct RemoteEntry: Equatable, Sendable {
    public var name: String
    public var path: String          // relative to the server's rootPath, normalized
    public var isDirectory: Bool
    public var size: Int64
    public var modified: Date
    public var created: Date?
    public var fileID: UInt64        // 0 = unknown
}
public enum SMBError: Error, Equatable, Sendable {
    case authenticationFailed, notFound, alreadyExists, permissionDenied, serverUnreachable,
         encryptionUnsupported, noSpace, notEmpty, fileInUse, cancelled
    case other(String)
    public var userMessage: String { get }
}
public typealias SMBReadProgress = @Sendable (_ bytes: Int64, _ total: Int64) -> Bool   // return false to cancel
public typealias SMBWriteProgress = @Sendable (_ bytes: Int64) -> Bool
public protocol SMBClient: Sendable {
    func connect() async throws
    func disconnect() async
    func list(_ path: String) async throws -> [RemoteEntry]
    func stat(_ path: String) async throws -> RemoteEntry
    func download(_ path: String, to localURL: URL, progress: SMBReadProgress?) async throws
    func upload(from localURL: URL, to path: String, overwrite: Bool, progress: SMBWriteProgress?) async throws
    func createDirectory(_ path: String) async throws
    func move(_ path: String, to newPath: String) async throws
    func remove(_ path: String) async throws        // files or directories (recursive)
}
public protocol SMBClientFactory: Sendable {
    func makeClient(server: ServerConfig, credential: Credential) -> any SMBClient
}
```

- Test-only `FakeSMBClient` (in-memory tree; `actor`) with helpers `seedFile(_ path:, contents: Data, modified: Date, fileID: UInt64)`, `seedDirectory(_ path:)`, `contents(of path:) -> Data?`, `failNext(_ error: SMBError)`, `setModified(_ path:, _ date:)`, `replaceSave(_ path:, contents:, modified:)` (simulates temp+rename: same path, new fileID), `rename(_:to:)` (server-side rename, keeps fileID), counters `connectCount`, `disconnectCount`, `listCount`. Also `struct FakeSMBClientFactory: SMBClientFactory { init(client: FakeSMBClient) }`, which always returns that same fake and records the last `Credential` it was given (`lastCredential`, lock-protected).

- [ ] **Step 1: Write `SMBClient.swift`** exactly as the interface block above, with `userMessage` strings:
  - `authenticationFailed` → "The username or password is incorrect."
  - `notFound` → "The item or share could not be found."
  - `alreadyExists` → "An item with that name already exists."
  - `permissionDenied` → "You don't have permission to do that."
  - `serverUnreachable` → "The server can't be reached. Check your network connection."
  - `encryptionUnsupported` → "The server doesn't support SMB encryption, which is required for this share."
  - `noSpace` → "The server is out of space."
  - `notEmpty` → "The folder isn't empty."
  - `fileInUse` → "The file is in use by someone else. Try again later."
  - `cancelled` → "The operation was cancelled."
  - `other(m)` → `m`

- [ ] **Step 2: Failing tests for the fake** (they pin down fake semantics the engine tests rely on):

```swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct FakeSMBClientTests {
    @Test func listStatUploadDownload() async throws {
        let fake = FakeSMBClient()
        await fake.seedDirectory("Docs")
        await fake.seedFile("Docs/a.docx", contents: Data("A".utf8), modified: Date(timeIntervalSince1970: 100), fileID: 7)
        let list = try await fake.list("Docs")
        #expect(list.map(\.name) == ["a.docx"])
        #expect(list[0].path == "Docs/a.docx")
        #expect(list[0].fileID == 7)
        #expect(try await fake.stat("Docs").isDirectory)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("BB".utf8).write(to: tmp)
        await #expect(throws: SMBError.alreadyExists) { try await fake.upload(from: tmp, to: "Docs/a.docx", overwrite: false, progress: nil) }
        try await fake.upload(from: tmp, to: "Docs/a.docx", overwrite: true, progress: nil)
        #expect(await fake.contents(of: "Docs/a.docx") == Data("BB".utf8))

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await fake.download("Docs/a.docx", to: out, progress: nil)
        #expect(try Data(contentsOf: out) == Data("BB".utf8))
    }

    @Test func errorsAndInjectedFailures() async throws {
        let fake = FakeSMBClient()
        await #expect(throws: SMBError.notFound) { try await fake.stat("missing") }
        await fake.failNext(.authenticationFailed)
        await #expect(throws: SMBError.authenticationFailed) { try await fake.list("") }
        _ = try await fake.list("")   // only the next call fails
    }

    @Test func replaceSaveChangesFileIDKeepsPath() async throws {
        let fake = FakeSMBClient()
        await fake.seedFile("a.docx", contents: Data("1".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        await fake.replaceSave("a.docx", contents: Data("22".utf8), modified: Date(timeIntervalSince1970: 2))
        let e = try await fake.stat("a.docx")
        #expect(e.fileID != 1)
        #expect(e.size == 2)
    }

    @Test func moveAndRemoveDirectoryRecursively() async throws {
        let fake = FakeSMBClient()
        await fake.seedDirectory("A")
        await fake.seedFile("A/x.txt", contents: Data(), modified: .now, fileID: 2)
        try await fake.move("A", to: "B")
        #expect(try await fake.list("B").map(\.path) == ["B/x.txt"])
        try await fake.remove("B")
        await #expect(throws: SMBError.notFound) { try await fake.stat("B/x.txt") }
    }
}
```

- [ ] **Step 3: Implement `FakeSMBClient`** as an `actor` that conforms to `SMBClient`. Nodes are stored as `[String: Node]` keyed by normalized path, where `Node { isDirectory, data, modified, created, fileID }`. Behavior:
  - `list` returns the direct children sorted by name.
  - `upload(overwrite:false)` on an existing path throws `.alreadyExists`.
  - A missing parent throws `.notFound`.
  - `move` re-keys the node and its descendants.
  - `remove` deletes the subtree.
  - `fileID`s auto-increment from 1000.
  - `failNext` errors are consumed by the next protocol call.
  - `connect()` increments `connectCount`.
  - `modified` for uploads uses an injectable `clock: @Sendable () -> Date` (default `Date.init`).

  The root `""` always exists as a directory.

- [ ] **Step 4: Verify** — `swift test --filter FakeSMBClientTests` → PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "Add SMB client protocol, error model, and in-memory fake"`

---

### Task 5: AMSMB2 client, error mapping, Samba integration tests

**Files:**
- Create: `Sources/ShareLinkKit/SMB/SMBErrorMapper.swift`, `SMB/AMSMB2Client.swift`, `SMB/ConnectionTester.swift`
- Create: `Tests/Samba/Dockerfile`, `Tests/Samba/smb.conf`, `Tests/Samba/docker-compose.yml`
- Replace: `Tests/ShareLinkIntegrationTests/Placeholder.swift` → `Tests/ShareLinkIntegrationTests/SambaIntegrationTests.swift`, `Tests/ShareLinkIntegrationTests/RealServerTests.swift`
- Test: `Tests/ShareLinkKitTests/SMBErrorMapperTests.swift`, `Tests/ShareLinkKitTests/ConnectionTesterTests.swift`

**Interfaces:**
- Consumes: `SMBClient`, `SMBError`, `RemoteEntry`, `ServerConfig`, `Credential`, `SMBPath`
- Produces:
  - `enum SMBErrorMapper { static func map(_ error: any Error, duringConnect: Bool) -> SMBError }`
  - `final class AMSMB2Client: SMBClient, @unchecked Sendable { init(server: ServerConfig, credential: Credential, timeout: TimeInterval = 30) }`
  - `struct AMSMB2ClientFactory: SMBClientFactory { init() }`
  - `enum ConnectionTester { static func test(server: ServerConfig, credential: Credential, factory: any SMBClientFactory) async -> SMBError? }` (nil = success; connects, lists root, disconnects)

- [ ] **Step 1: Failing mapper tests**

```swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct SMBErrorMapperTests {
    func posix(_ code: POSIXErrorCode, _ desc: String) -> POSIXError {
        POSIXError(code, userInfo: [NSLocalizedDescriptionKey: desc])
    }
    @Test func logonFailureIsAuth() {
        let e = posix(.ECONNREFUSED, "Error code ECONNREFUSED: Session setup failed with (0xc000006d) STATUS_LOGON_FAILURE.")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .authenticationFailed)
    }
    @Test func refusedTCPIsUnreachable() {
        let e = posix(.ECONNREFUSED, "Error code ECONNREFUSED: Connect failed with errno : Connection refused(61)")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .serverUnreachable)
    }
    @Test func accessDeniedDuringConnectIsAuthAfterIsPermission() {
        let e = posix(.EACCES, "Error code EACCES: Session setup failed with (0xc0000072) STATUS_ACCOUNT_DISABLED")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .authenticationFailed)
        #expect(SMBErrorMapper.map(posix(.EACCES, "STATUS_ACCESS_DENIED"), duringConnect: false) == .permissionDenied)
    }
    @Test func otherCodes() {
        #expect(SMBErrorMapper.map(posix(.ENOENT, "x"), duringConnect: false) == .notFound)
        #expect(SMBErrorMapper.map(posix(.EEXIST, "x"), duringConnect: false) == .alreadyExists)
        #expect(SMBErrorMapper.map(posix(.ENOTEMPTY, "x"), duringConnect: false) == .notEmpty)
        #expect(SMBErrorMapper.map(posix(.ETXTBSY, "x"), duringConnect: false) == .fileInUse)
        #expect(SMBErrorMapper.map(posix(.EDEADLK, "x"), duringConnect: false) == .fileInUse)
        #expect(SMBErrorMapper.map(posix(.ENOSPC, "x"), duringConnect: false) == .noSpace)
        for c in [POSIXErrorCode.ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .ECONNRESET, .ENOTCONN, .EPIPE] {
            #expect(SMBErrorMapper.map(posix(c, "x"), duringConnect: false) == .serverUnreachable)
        }
        #expect(SMBErrorMapper.map(CancellationError(), duringConnect: false) == .cancelled)
        #expect(SMBErrorMapper.map(SMBError.notFound, duringConnect: false) == .notFound)
    }
    @Test func encryptionRequiredButUnsupported() {
        let e = posix(.EINVAL, "Error code EINVAL: Server does not support encryption")
        #expect(SMBErrorMapper.map(e, duringConnect: true) == .encryptionUnsupported)
    }
}
```

`ConnectionTesterTests` uses `FakeSMBClientFactory`: success returns nil and disconnects (the fake records `disconnectCount`); a fake set to `failNext(.authenticationFailed)` returns `.authenticationFailed`.

Run: `swift test --filter "SMBErrorMapperTests|ConnectionTesterTests"` → FAIL.

- [ ] **Step 2: Implement the mapper**

```swift
import Foundation

public enum SMBErrorMapper {
    public static func map(_ error: any Error, duringConnect: Bool) -> SMBError {
        if let e = error as? SMBError { return e }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        let text = (ns.userInfo[NSLocalizedDescriptionKey] as? String ?? ns.localizedDescription).uppercased()
        if text.contains("LOGON_FAILURE") || text.contains("WRONG_PASSWORD") || text.contains("ACCOUNT_DISABLED")
            || text.contains("PASSWORD_EXPIRED") || text.contains("ACCOUNT_RESTRICTION") || text.contains("INVALID_LOGON_HOURS")
            || text.contains("ACCOUNT_LOCKED") {
            return .authenticationFailed
        }
        if text.contains("ENCRYPT") && (text.contains("NOT SUPPORT") || text.contains("DOES NOT SUPPORT")) {
            return .encryptionUnsupported
        }
        guard ns.domain == NSPOSIXErrorDomain, let code = POSIXErrorCode(rawValue: Int32(ns.code)) else {
            return .other(ns.localizedDescription)
        }
        switch code {
        case .ENOENT, .ENOTDIR: return .notFound
        case .EEXIST: return .alreadyExists
        case .EACCES, .EPERM: return duringConnect ? .authenticationFailed : .permissionDenied
        case .ENOTEMPTY: return .notEmpty
        case .ETXTBSY, .EDEADLK, .EBUSY: return .fileInUse
        case .ENOSPC, .EDQUOT: return .noSpace
        case .ECONNREFUSED, .ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .ENETDOWN, .ECONNRESET,
             .ENOTCONN, .EPIPE, .ECONNABORTED, .EHOSTDOWN: return .serverUnreachable
        case .ECANCELED: return .cancelled
        default: return .other(ns.localizedDescription)
        }
    }
}
```

`ConnectionTester`:

```swift
public enum ConnectionTester {
    public static func test(server: ServerConfig, credential: Credential, factory: any SMBClientFactory) async -> SMBError? {
        let client = factory.makeClient(server: server, credential: credential)
        do {
            try await client.connect()
            _ = try await client.list("")
            await client.disconnect()
            return nil
        } catch {
            await client.disconnect()
            return SMBErrorMapper.map(error, duringConnect: true)
        }
    }
}
```

- [ ] **Step 3: Implement `AMSMB2Client`**

```swift
import Foundation
import AMSMB2

public final class AMSMB2Client: SMBClient, @unchecked Sendable {
    private let server: ServerConfig
    private let credential: Credential
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var manager: SMB2Manager?
    static let chunkSize = 2 * 1024 * 1024

    public init(server: ServerConfig, credential: Credential, timeout: TimeInterval = 30) {
        self.server = server; self.credential = credential; self.timeout = timeout
    }

    private func fullPath(_ relative: String) -> String { SMBPath.join(server.rootPath, relative) }

    private func relative(_ full: String) -> String {
        let f = SMBPath.normalize(full), root = SMBPath.normalize(server.rootPath)
        guard !root.isEmpty else { return f }
        if f == root { return "" }
        return f.hasPrefix(root + "/") ? String(f.dropFirst(root.count + 1)) : f
    }

    public func connect() async throws {
        var comps = URLComponents()
        comps.scheme = "smb"; comps.host = server.host; comps.port = server.port
        guard let url = comps.url,
              let m = SMB2Manager(url: url, domain: server.domain,
                                  credential: URLCredential(user: credential.username, password: credential.password, persistence: .forSession))
        else { throw SMBError.other("Invalid server address") }
        m.timeout = timeout
        do {
            try await m.connectShare(name: server.share, encrypted: server.requireEncryption)
            if !server.rootPath.isEmpty { _ = try await m.attributesOfItem(atPath: server.rootPath) }
        } catch {
            throw SMBErrorMapper.map(error, duringConnect: true)
        }
        lock.withLock { manager = m }
    }

    public func disconnect() async {
        let m = lock.withLock { () -> SMB2Manager? in defer { manager = nil }; return manager }
        try? await m?.disconnectShare(gracefully: false)
    }

    private func requireManager() throws -> SMB2Manager {
        guard let m = lock.withLock({ manager }) else { throw SMBError.serverUnreachable }
        return m
    }

    private func run<T>(_ body: (SMB2Manager) async throws -> T) async throws -> T {
        let m = try requireManager()
        do { return try await body(m) } catch { throw SMBErrorMapper.map(error, duringConnect: false) }
    }

    private func entry(_ attrs: [URLResourceKey: any Sendable], fallbackPath: String) -> RemoteEntry {
        let path = (attrs[.pathKey] as? String).map(relative) ?? fallbackPath
        let name = (attrs[.nameKey] as? String) ?? SMBPath.lastComponent(path)
        return RemoteEntry(
            name: name, path: SMBPath.normalize(path),
            isDirectory: (attrs[.isDirectoryKey] as? NSNumber)?.boolValue ?? false,
            size: (attrs[.fileSizeKey] as? NSNumber)?.int64Value ?? 0,
            modified: (attrs[.contentModificationDateKey] as? Date) ?? .distantPast,
            created: attrs[.creationDateKey] as? Date,
            fileID: (attrs[.documentIdentifierKey] as? NSNumber)?.uint64Value ?? 0)
    }

    public func list(_ path: String) async throws -> [RemoteEntry] {
        try await run { m in
            try await m.contentsOfDirectory(atPath: fullPath(path)).map { attrs in
                var e = entry(attrs, fallbackPath: SMBPath.join(path, attrs[.nameKey] as? String ?? ""))
                e.path = SMBPath.join(path, e.name)
                return e
            }
        }
    }

    public func stat(_ path: String) async throws -> RemoteEntry {
        try await run { m in
            var e = entry(try await m.attributesOfItem(atPath: fullPath(path)), fallbackPath: path)
            e.path = SMBPath.normalize(path); e.name = SMBPath.lastComponent(path)
            return e
        }
    }

    public func download(_ path: String, to localURL: URL, progress: SMBReadProgress?) async throws {
        try await run { m in
            try await m.downloadItem(atPath: fullPath(path), to: localURL) { bytes, total in
                progress?(bytes, total) ?? true
            }
        }
    }

    public func upload(from localURL: URL, to path: String, overwrite: Bool, progress: SMBWriteProgress?) async throws {
        try await run { m in
            let target = fullPath(path)
            guard overwrite else {
                try await m.uploadItem(at: localURL, toPath: target) { progress?($0) ?? true }
                return
            }
            // In-place overwrite (keeps server ACLs): chunked writes at increasing offsets.
            // append(offset:) truncates the remote file to `offset` before writing.
            let handle = try FileHandle(forReadingFrom: localURL)
            defer { try? handle.close() }
            var offset: Int64 = 0
            var wroteAny = false
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
                if chunk.isEmpty { break }
                try await m.append(data: chunk, toPath: target, offset: offset, progress: nil)
                offset += Int64(chunk.count); wroteAny = true
                if progress?(offset) == false { throw SMBError.cancelled }
            }
            if !wroteAny {
                do { try await m.truncateFile(atPath: target, atOffset: 0) }
                catch { try await m.write(data: Data(), toPath: target, progress: nil) }
            }
        }
    }

    public func createDirectory(_ path: String) async throws {
        try await run { m in try await m.createDirectory(atPath: fullPath(path)) }
    }

    public func move(_ path: String, to newPath: String) async throws {
        try await run { m in try await m.moveItem(atPath: fullPath(path), toPath: fullPath(newPath)) }
    }

    public func remove(_ path: String) async throws {
        try await run { m in
            let target = fullPath(path)
            let attrs = try await m.attributesOfItem(atPath: target)
            if (attrs[.isDirectoryKey] as? NSNumber)?.boolValue == true {
                try await m.removeDirectory(atPath: target, recursive: true)
            } else {
                try await m.removeFile(atPath: target)
            }
        }
    }
}

public struct AMSMB2ClientFactory: SMBClientFactory {
    public init() {}
    public func makeClient(server: ServerConfig, credential: Credential) -> any SMBClient {
        AMSMB2Client(server: server, credential: credential)
    }
}
```

If any AMSMB2 call signature differs at 4.0.3 (check `.build/checkouts/AMSMB2/AMSMB2/AMSMB2.swift`), adapt the call but keep the behavior above.

- [ ] **Step 4: Samba container**

`Tests/Samba/Dockerfile`:

```dockerfile
FROM alpine:3.22
RUN apk add --no-cache samba samba-common-tools
RUN adduser -D -H -s /sbin/nologin testuser \
 && (echo 'ShareLink-Test-1'; echo 'ShareLink-Test-1') | smbpasswd -s -a testuser \
 && mkdir -p /shares/signed /shares/encrypted && chown -R testuser /shares
COPY smb.conf /etc/samba/smb.conf
EXPOSE 445
CMD ["smbd", "--foreground", "--no-process-group", "--debug-stdout"]
```

`Tests/Samba/smb.conf`:

```ini
[global]
  server role = standalone server
  server min protocol = SMB2_10
  server signing = mandatory
  map to guest = never
  load printers = no
  disable spoolss = yes
  log level = 1
[signed]
  path = /shares/signed
  read only = no
  valid users = testuser
[encrypted]
  path = /shares/encrypted
  read only = no
  valid users = testuser
  server smb encrypt = required
```

`Tests/Samba/docker-compose.yml`:

```yaml
services:
  samba:
    build: .
    ports: ["1445:445"]
```

- [ ] **Step 5: Integration tests**

`SambaIntegrationTests.swift` (Swift Testing). The suite is `.enabled(if: SambaEnv.isReachable)`. `SambaEnv.isReachable` attempts a TCP connection to `127.0.0.1:1445` with a 1 s timeout, using `socket`/`connect` or `NWConnection`. Each test uses a unique folder `it-<UUID>` in the share and deletes it at the end.

```swift
import Testing
import Foundation
@testable import ShareLinkKit

enum SambaEnv {
    static let credential = Credential(username: "testuser", password: "ShareLink-Test-1")
    static func server(share: String = "signed", encrypted: Bool = false, root: String = "") -> ServerConfig {
        ServerConfig(id: "it", source: .user, displayName: "IT", host: "127.0.0.1", port: 1445,
                     share: share, rootPath: root, requireEncryption: encrypted)
    }
    static var isReachable: Bool { /* TCP probe 127.0.0.1:1445, 1s timeout */ }
}

@Suite(.enabled(if: SambaEnv.isReachable), .serialized) struct SambaIntegrationTests {
    func connected(_ server: ServerConfig = SambaEnv.server()) async throws -> AMSMB2Client {
        let c = AMSMB2Client(server: server, credential: SambaEnv.credential)
        try await c.connect(); return c
    }
    func tempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var data = Data(count: bytes); for i in 0..<min(bytes, 4096) { data[i] = UInt8(i % 251) }
        try data.write(to: url); return url
    }

    @Test func crudRoundTripWithSpecialNames() async throws {
        let c = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await c.createDirectory(dir)
        let name = "Q3 Report #1 – café.docx"
        let src = try tempFile(bytes: 10_000)
        try await c.upload(from: src, to: "\(dir)/\(name)", overwrite: false, progress: nil)
        let listed = try await c.list(dir)
        #expect(listed.map(\.name) == [name])
        #expect(listed[0].size == 10_000)
        #expect(listed[0].path == "\(dir)/\(name)")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await c.download("\(dir)/\(name)", to: out, progress: nil)
        #expect(try Data(contentsOf: out) == Data(contentsOf: src))
        try await c.move("\(dir)/\(name)", to: "\(dir)/renamed.docx")
        #expect(try await c.stat("\(dir)/renamed.docx").size == 10_000)
        await #expect(throws: SMBError.alreadyExists) {
            try await c.upload(from: src, to: "\(dir)/renamed.docx", overwrite: false, progress: nil)
        }
        try await c.remove(dir)
        await #expect(throws: SMBError.notFound) { try await c.stat(dir) }
        await c.disconnect()
    }

    @Test func overwriteTruncates() async throws {
        let c = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await c.createDirectory(dir)
        try await c.upload(from: try tempFile(bytes: 3_000_000), to: "\(dir)/f.bin", overwrite: false, progress: nil)
        let small = try tempFile(bytes: 1_024)
        try await c.upload(from: small, to: "\(dir)/f.bin", overwrite: true, progress: nil)
        #expect(try await c.stat("\(dir)/f.bin").size == 1_024)
        let empty = try tempFile(bytes: 0)
        try await c.upload(from: empty, to: "\(dir)/f.bin", overwrite: true, progress: nil)
        #expect(try await c.stat("\(dir)/f.bin").size == 0)
        try await c.remove(dir); await c.disconnect()
    }

    @Test func largeFileStreams() async throws {
        let c = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await c.createDirectory(dir)
        let src = try tempFile(bytes: 50 * 1024 * 1024)
        try await c.upload(from: src, to: "\(dir)/big.bin", overwrite: false, progress: nil)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await c.download("\(dir)/big.bin", to: out, progress: nil)
        #expect((try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.intValue == 50 * 1024 * 1024)
        try await c.remove(dir); await c.disconnect()
    }

    @Test func rootPathScopesPaths() async throws {
        let base = try await connected(); let dir = "it-\(UUID().uuidString)"
        try await base.createDirectory(dir); try await base.createDirectory("\(dir)/inner")
        let scoped = try await connected(SambaEnv.server(root: dir))
        #expect(try await scoped.list("").map(\.path) == ["inner"])
        try await base.remove(dir); await scoped.disconnect(); await base.disconnect()
    }

    @Test func wrongPasswordIsAuthenticationFailed() async {
        let c = AMSMB2Client(server: SambaEnv.server(), credential: Credential(username: "testuser", password: "wrong"))
        await #expect(throws: SMBError.authenticationFailed) { try await c.connect() }
    }

    @Test func encryptedShareWorksWithEncryption() async throws {
        let c = try await connected(SambaEnv.server(share: "encrypted", encrypted: true))
        _ = try await c.list(""); await c.disconnect()
    }

    @Test func concurrentOperationsOnOneClient() async throws {
        let c = try await connected()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { _ = try await c.list("") } }
            try await group.waitForAll()
        }
        await c.disconnect()
    }

    @Test func unreachablePortIsServerUnreachable() async {
        var s = SambaEnv.server(); s.port = 1446
        let c = AMSMB2Client(server: s, credential: SambaEnv.credential, timeout: 3)
        await #expect(throws: SMBError.serverUnreachable) { try await c.connect() }
    }
}
```

`RealServerTests.swift` is enabled only when env `SHARELINK_TEST_SERVER_JSON` points to a readable file in `TestServer.example.json` format. It is read-only: connect, list root, stat the first entry, disconnect, and print the entry count only (never names).

- [ ] **Step 6: Verify**

```bash
cd Packages/ShareLinkKit && swift test --filter "SMBErrorMapperTests|ConnectionTesterTests"
docker compose -f ../../Tests/Samba/docker-compose.yml up -d --build
swift test --filter SambaIntegrationTests
docker compose -f ../../Tests/Samba/docker-compose.yml down
```

Expected: all pass. If `wrongPasswordIsAuthenticationFailed` or `unreachablePortIsServerUnreachable` fails, print the raw error's `localizedDescription` and extend `SMBErrorMapper`'s substring checks. Do NOT weaken the test. Record the raw strings in PROGRESS.md.

- [ ] **Step 7: Commit** — `git add -A && git commit -m "Add AMSMB2 client, error mapping, and Samba integration tests"`

---

### Task 6: Versions, hidden names, item records, metadata store

**Files:**
- Create: `Sync/ItemVersion.swift`, `Sync/HiddenNames.swift`, `Sync/ItemRecord.swift`, `Sync/MetadataStore.swift`
- Test: `Tests/ShareLinkKitTests/ItemVersionTests.swift`, `Tests/ShareLinkKitTests/HiddenNamesTests.swift`, `Tests/ShareLinkKitTests/MetadataStoreTests.swift`

**Interfaces:**
- Consumes: `RemoteEntry`, `SMBPath`
- Produces:

```swift
public enum ItemVersion {
    public static func content(size: Int64, modified: Date, isDirectory: Bool) -> Data  // "<size>-<ns since 1970>", dirs size 0
    public static func metadata(content: Data, name: String) -> Data                       // content + "-" + name
}
public enum HiddenNames { public static func isHidden(_ name: String) -> Bool }
public struct ItemRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "items"
    public static let rootIdentifier = "NSFileProviderRootContainerItemIdentifier"   // == NSFileProviderItemIdentifier.rootContainer.rawValue
    public var identifier: String
    public var parentIdentifier: String
    public var relativePath: String
    public var name: String
    public var isDirectory: Bool
    public var size: Int64
    public var modified: Date
    public var created: Date?
    public var fileID: Int64          // UInt64 bit pattern
    public var lastScanned: Date?     // folders only; nil = never enumerated
    public var contentVersion: Data { get }
    public var metadataVersion: Data { get }
    public static func from(_ entry: RemoteEntry, identifier: String, parentIdentifier: String) -> ItemRecord
}
public enum ChangeKind: String, Codable, Sendable { case update, delete }
public struct ChangeRecord: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "changes"
    public var seq: Int64?
    public var identifier: String
    public var parentIdentifier: String
    public var kind: ChangeKind
}
public struct FolderDiff: Equatable, Sendable {
    public var folderIdentifier: String
    public var inserts: [ItemRecord]
    public var updates: [ItemRecord]          // includes renames (same identifier, new name/path)
    public var deletes: [String]              // identifiers of direct children that disappeared
    public var renamedDirectories: [DirectoryRename]  // for descendant path rewrite
    public var isEmpty: Bool { get }
}
public struct DirectoryRename: Equatable, Sendable { public var oldPath: String; public var newPath: String }
public final class MetadataStore: Sendable {
    public init(directory: URL) throws          // creates dir + metadata.sqlite, migrates, ensures root row
    public static func inMemory() throws -> MetadataStore
    public func item(_ identifier: String) throws -> ItemRecord?
    public func item(atPath path: String) throws -> ItemRecord?
    public func children(of parent: String) throws -> [ItemRecord]                       // all, name order (NOCASE)
    public func children(of parent: String, offset: Int, limit: Int) throws -> [ItemRecord]
    public func nonRootItems(offset: Int, limit: Int) throws -> [ItemRecord]
    public func apply(_ diff: FolderDiff, scannedAt: Date) throws                        // one transaction
    public func recordLocalUpsert(_ record: ItemRecord) throws                          // insert-or-replace + update change
    public func recordLocalMove(identifier: String, newParent: String, newName: String, newPath: String) throws
    public func recordLocalDelete(identifier: String) throws                            // subtree + delete changes
    public func currentAnchor() throws -> Int64                                          // max seq or 0
    public func oldestRetainedSeq() throws -> Int64?                                     // min seq or nil
    public func changes(after seq: Int64, limit: Int) throws -> [ChangeRecord]
    public func pruneChanges(keepLast: Int) throws
    public func foldersNeedingScan(olderThan cutoff: Date, limit: Int) throws -> [ItemRecord]  // dirs with lastScanned != nil && < cutoff, most recent first
}
```

- [ ] **Step 1: Failing tests**

```swift
// ItemVersionTests.swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ItemVersionTests {
    @Test func contentVersionFormat() {
        let d = Date(timeIntervalSince1970: 1.5)
        #expect(String(decoding: ItemVersion.content(size: 10, modified: d, isDirectory: false), as: UTF8.self) == "10-1500000000")
        #expect(String(decoding: ItemVersion.content(size: 10, modified: d, isDirectory: true), as: UTF8.self) == "0-1500000000")
        let m = ItemVersion.metadata(content: Data("10-1".utf8), name: "a.docx")
        #expect(String(decoding: m, as: UTF8.self) == "10-1-a.docx")
    }
}
```

```swift
// HiddenNamesTests.swift
import Testing
@testable import ShareLinkKit

@Suite struct HiddenNamesTests {
    @Test(arguments: [".DS_Store", "Thumbs.db", "thumbs.db", "desktop.ini", "~$Report.docx", ".hidden", "$RECYCLE.BIN", "System Volume Information"])
    func hidden(name: String) { #expect(HiddenNames.isHidden(name)) }

    @Test(arguments: ["Report.docx", "~Report.docx", "a.b", "Desktop"])
    func visible(name: String) { #expect(!HiddenNames.isHidden(name)) }
}
```

```swift
// MetadataStoreTests.swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct MetadataStoreTests {
    let root = ItemRecord.rootIdentifier
    func rec(_ id: String, parent: String, path: String, dir: Bool = false, size: Int64 = 1, fileID: Int64 = 0) -> ItemRecord {
        ItemRecord(identifier: id, parentIdentifier: parent, relativePath: path, name: SMBPath.lastComponent(path),
                   isDirectory: dir, size: size, modified: Date(timeIntervalSince1970: 10), created: nil, fileID: fileID, lastScanned: nil)
    }

    @Test func rootExistsAndAnchorStartsAtZero() throws {
        let s = try MetadataStore.inMemory()
        #expect(try s.item(root)?.relativePath == "")
        #expect(try s.currentAnchor() == 0)
        #expect(try s.oldestRetainedSeq() == nil)
    }

    @Test func applyDiffRecordsChangesInOrder() throws {
        let s = try MetadataStore.inMemory()
        let a = rec("A", parent: root, path: "a.docx"), d = rec("D", parent: root, path: "Docs", dir: true)
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [a, d], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        #expect(try s.children(of: root).map(\.identifier) == ["A", "D"])   // "a.docx" < "Docs" NOCASE
        #expect(try s.item(root)?.lastScanned != nil)
        let ch = try s.changes(after: 0, limit: 10)
        #expect(ch.map(\.identifier) == ["A", "D"])
        #expect(ch.allSatisfy { $0.kind == .update && $0.parentIdentifier == root })
        #expect(try s.currentAnchor() == 2)
    }

    @Test func deleteRemovesSubtreeAndRecordsEachDeletion() throws {
        let s = try MetadataStore.inMemory()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [rec("D", parent: root, path: "Docs", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "D", inserts: [rec("X", parent: "D", path: "Docs/x.txt")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        let before = try s.currentAnchor()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [], updates: [], deletes: ["D"], renamedDirectories: []), scannedAt: .now)
        #expect(try s.item("D") == nil)
        #expect(try s.item("X") == nil)
        #expect(Set(try s.changes(after: before, limit: 10).map(\.identifier)) == ["D", "X"])
        #expect(try s.changes(after: before, limit: 10).allSatisfy { $0.kind == .delete })
    }

    @Test func renameDirectoryRewritesDescendantPaths() throws {
        let s = try MetadataStore.inMemory()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [rec("D", parent: root, path: "Docs", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "D", inserts: [rec("S", parent: "D", path: "Docs/Sub", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.apply(FolderDiff(folderIdentifier: "S", inserts: [rec("X", parent: "S", path: "Docs/Sub/x.txt")], updates: [], deletes: [], renamedDirectories: []), scannedAt: .now)
        try s.recordLocalMove(identifier: "D", newParent: root, newName: "Papers", newPath: "Papers")
        #expect(try s.item("D")?.relativePath == "Papers")
        #expect(try s.item("S")?.relativePath == "Papers/Sub")
        #expect(try s.item("X")?.relativePath == "Papers/Sub/x.txt")
        #expect(try s.item(atPath: "Papers/Sub/x.txt")?.identifier == "X")
    }

    @Test func pruneKeepsNewest() throws {
        let s = try MetadataStore.inMemory()
        for i in 0..<10 { try s.recordLocalUpsert(rec("I\(i)", parent: root, path: "f\(i)")) }
        try s.pruneChanges(keepLast: 3)
        #expect(try s.oldestRetainedSeq() == 8)
        #expect(try s.currentAnchor() == 10)
    }

    @Test func foldersNeedingScan() throws {
        let s = try MetadataStore.inMemory()
        try s.apply(FolderDiff(folderIdentifier: root, inserts: [rec("D", parent: root, path: "Docs", dir: true)], updates: [], deletes: [], renamedDirectories: []), scannedAt: Date(timeIntervalSince1970: 100))
        #expect(try s.foldersNeedingScan(olderThan: Date(timeIntervalSince1970: 200), limit: 10).map(\.identifier) == [root])  // D never scanned
        #expect(try s.foldersNeedingScan(olderThan: Date(timeIntervalSince1970: 50), limit: 10).isEmpty)
    }

    @Test func persistsAcrossReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { let s = try MetadataStore(directory: dir); try s.recordLocalUpsert(rec("A", parent: root, path: "a")) }
        let s2 = try MetadataStore(directory: dir)
        #expect(try s2.item("A") != nil)
        #expect(try s2.currentAnchor() == 1)
    }
}
```

Run: `swift test --filter "ItemVersionTests|HiddenNamesTests|MetadataStoreTests"` → FAIL.

- [ ] **Step 2: Implement**

`ItemVersion`: `"\(isDirectory ? 0 : size)-\(Int64((modified.timeIntervalSince1970 * 1_000_000_000).rounded()))"` as UTF-8; metadata = content bytes + `"-\(name)"`.

`HiddenNames.isHidden`: true when `name.hasPrefix(".")`, `name.hasPrefix("~$")`, or `name.lowercased()` is in `["thumbs.db", "desktop.ini", "$recycle.bin", "system volume information"]`.

`ItemRecord.from(entry, identifier:, parentIdentifier:)` copies the fields (`fileID: Int64(bitPattern: entry.fileID)`, `lastScanned: nil`). `contentVersion` and `metadataVersion` are computed with `ItemVersion`.

`MetadataStore`:
- wraps a GRDB `DatabaseQueue`
- file: `directory/metadata.sqlite`
- `inMemory()` uses `DatabaseQueue()`

Migration `v1`:

```sql
CREATE TABLE items (
  identifier TEXT PRIMARY KEY NOT NULL,
  parentIdentifier TEXT NOT NULL,
  relativePath TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  isDirectory BOOLEAN NOT NULL,
  size INTEGER NOT NULL,
  modified DATETIME NOT NULL,
  created DATETIME,
  fileID INTEGER NOT NULL,
  lastScanned DATETIME
);
CREATE INDEX items_parent ON items(parentIdentifier);
CREATE TABLE changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  identifier TEXT NOT NULL,
  parentIdentifier TEXT NOT NULL,
  kind TEXT NOT NULL
);
```

(Use GRDB's `DatabaseMigrator` with `t.column(...)` API or raw `db.execute(sql:)`.) After migrating, insert the root row if it's missing: identifier `ItemRecord.rootIdentifier`, parent = itself, path `""`, name `""`, `isDirectory` true, size 0, modified `Date(timeIntervalSince1970: 0)`, fileID 0.

Rules for `apply(diff, scannedAt:)`, all in one `write` transaction:
1. For each `renamedDirectories` entry, rewrite descendants with `UPDATE items SET relativePath = :new || substr(relativePath, length(:old) + 1) WHERE relativePath LIKE :old || '/%'` (escape `%`/`_` in `old` with `ESCAPE '\'`).
2. Upsert `updates`, then insert `inserts`. Preserve an existing row's `lastScanned` on update.
3. For each id in `deletes`, collect the subtree (recursive CTE over `parentIdentifier`), delete those rows, and append one `delete` change per removed id. The change's `parentIdentifier` is the row's parent.
4. Append one `update` change per insert and per update.
5. Set `lastScanned = scannedAt` on the folder row.

Then:
- `recordLocalMove` does the descendant rewrite (only when the item is a directory), updates the row, and appends an `update` change.
- `recordLocalDelete` is the subtree delete from rule 3.
- `foldersNeedingScan` returns directories (root included) where `lastScanned IS NOT NULL AND lastScanned < cutoff`, ordered by `lastScanned DESC`, limited to `limit`. The `foldersNeedingScan` test above inserts `D` without `lastScanned`, so only the root qualifies.

- [ ] **Step 3: Verify** — `swift test --filter "ItemVersionTests|HiddenNamesTests|MetadataStoreTests"` → PASS.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add item versioning, hidden-name filter, and GRDB metadata store"`

---

### Task 7: Folder scanner (diffing a listing against known children)

**Files:**
- Create: `Sync/FolderScanner.swift`
- Test: `Tests/ShareLinkKitTests/FolderScannerTests.swift`

**Interfaces:**
- Consumes: `ItemRecord`, `RemoteEntry`, `FolderDiff`, `DirectoryRename`, `HiddenNames`
- Produces: `enum FolderScanner { static func diff(folder: ItemRecord, existing: [ItemRecord], listing: [RemoteEntry], makeIdentifier: () -> String = { UUID().uuidString }) -> FolderDiff }`

Rules:
1. Drop listing entries where `HiddenNames.isHidden(name)`.
2. Match by exact `name`. If matched and any of `size`, `modified`, `isDirectory`, `fileID` differs, it's an update with the same identifier and new fields; `lastScanned` is preserved. If nothing differs, there's no change.
3. Unmatched listing entry: if an unmatched existing child has the same non-zero `fileID` and the same `isDirectory`, it's a rename. That's an update with the existing identifier and new name/path; if it's a directory, also add a `DirectoryRename(oldPath, newPath)`. Otherwise it's an insert with `makeIdentifier()` and `parentIdentifier = folder.identifier`.
4. Remaining unmatched existing children are deletes.
5. Paths are `SMBPath.join(folder.relativePath, entry.name)`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct FolderScannerTests {
    let folder = ItemRecord(identifier: "F", parentIdentifier: ItemRecord.rootIdentifier, relativePath: "Docs", name: "Docs",
                            isDirectory: true, size: 0, modified: .distantPast, created: nil, fileID: 1, lastScanned: nil)
    func entry(_ name: String, size: Int64 = 1, t: TimeInterval = 10, id: UInt64 = 0, dir: Bool = false) -> RemoteEntry {
        RemoteEntry(name: name, path: "Docs/\(name)", isDirectory: dir, size: size, modified: Date(timeIntervalSince1970: t), created: nil, fileID: id)
    }
    func record(_ id: String, _ e: RemoteEntry) -> ItemRecord { ItemRecord.from(e, identifier: id, parentIdentifier: "F") }
    func ids() -> () -> String { var n = 0; return { n += 1; return "new\(n)" } }

    @Test func insertsNewSkippingHidden() {
        let d = FolderScanner.diff(folder: folder, existing: [], listing: [entry("a.docx"), entry("~$a.docx"), entry(".DS_Store")], makeIdentifier: ids())
        #expect(d.inserts.map(\.identifier) == ["new1"])
        #expect(d.inserts[0].relativePath == "Docs/a.docx")
        #expect(d.inserts[0].parentIdentifier == "F")
        #expect(d.updates.isEmpty && d.deletes.isEmpty)
    }

    @Test func unchangedProducesEmptyDiff() {
        let e = entry("a.docx", id: 5)
        let d = FolderScanner.diff(folder: folder, existing: [record("A", e)], listing: [e])
        #expect(d.isEmpty)
    }

    @Test func modifiedKeepsIdentifier() {
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("a.docx", size: 1, t: 10, id: 5))],
                                   listing: [entry("a.docx", size: 2, t: 20, id: 5)])
        #expect(d.updates.map(\.identifier) == ["A"])
        #expect(d.updates[0].size == 2)
    }

    @Test func replaceSaveKeepsIdentifier() {
        // Windows/Office: temp file renamed over original -> same name, new fileID, new mtime.
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("a.docx", size: 1, t: 10, id: 5))],
                                   listing: [entry("a.docx", size: 3, t: 30, id: 99)])
        #expect(d.updates.map(\.identifier) == ["A"])
        #expect(d.updates[0].fileID == 99)
        #expect(d.inserts.isEmpty && d.deletes.isEmpty)
    }

    @Test func serverRenameDetectedByFileID() {
        let d = FolderScanner.diff(folder: folder, existing: [record("S", entry("Old", id: 7, dir: true))],
                                   listing: [entry("New", id: 7, dir: true)])
        #expect(d.updates.map(\.identifier) == ["S"])
        #expect(d.updates[0].relativePath == "Docs/New")
        #expect(d.renamedDirectories == [DirectoryRename(oldPath: "Docs/Old", newPath: "Docs/New")])
        #expect(d.inserts.isEmpty && d.deletes.isEmpty)
    }

    @Test func zeroFileIDRenameIsDeletePlusInsert() {
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("old.txt", id: 0))],
                                   listing: [entry("new.txt", id: 0)], makeIdentifier: ids())
        #expect(d.deletes == ["A"])
        #expect(d.inserts.map(\.identifier) == ["new1"])
    }

    @Test func removedChildIsDeleted() {
        let d = FolderScanner.diff(folder: folder, existing: [record("A", entry("a.docx"))], listing: [])
        #expect(d.deletes == ["A"])
    }
}
```

Run: `swift test --filter FolderScannerTests` → FAIL. Implement per the rules above. Run again → PASS.

- [ ] **Step 2: Commit** — `git add -A && git commit -m "Add folder scanner diffing with replace-save and rename detection"`

---

### Task 8: File Provider items, errors, connection provider, provider engine

**Files:**
- Create: `FileProvider/FileProviderItem.swift`, `FileProvider/FileProviderErrors.swift`, `FileProvider/ConflictNamer.swift`, `FileProvider/ConnectionProvider.swift`, `FileProvider/ProviderEngine.swift`
- Test: `Tests/ShareLinkKitTests/FileProviderItemTests.swift`, `Tests/ShareLinkKitTests/ConflictNamerTests.swift`, `Tests/ShareLinkKitTests/ProviderEngineTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–7.
- Produces:

```swift
public final class FileProviderItem: NSObject, NSFileProviderItem, @unchecked Sendable {
    public init(record: ItemRecord, rootDisplayName: String)
    public let record: ItemRecord
    // NSFileProviderItem: itemIdentifier, parentItemIdentifier, filename, contentType, capabilities,
    // documentSize, contentModificationDate, creationDate, itemVersion
}
public enum FileProviderErrors { public static func nsError(for error: any Error) -> NSError }
public enum ConflictNamer { public static func name(for filename: String, device: String, date: Date, timeZone: TimeZone = .current) -> String }
public actor ConnectionProvider {
    public init(server: ServerConfig, credentials: any CredentialStoring, factory: any SMBClientFactory)
    public func withClient<T: Sendable>(_ body: @Sendable (any SMBClient) async throws -> T) async throws -> T   // connects lazily; on .serverUnreachable resets and retries once
    public func reset() async
}
public struct ChangeBatch: Sendable {
    public var updated: [FileProviderItem]
    public var deleted: [NSFileProviderItemIdentifier]
    public var anchor: NSFileProviderSyncAnchor
    public var moreComing: Bool
}
public actor ProviderEngine {
    public static let pageSize = 200
    public static let changeBatchSize = 500
    public static let rescanInterval: TimeInterval = 15
    public static let maxFoldersPerRescan = 50
    public static let changesRetained = 5000
    public init(server: ServerConfig, store: MetadataStore, connection: ConnectionProvider,
                deviceName: String, now: @escaping @Sendable () -> Date = { Date() },
                signalWorkingSet: @escaping @Sendable () -> Void = {})
    public func item(for identifier: NSFileProviderItemIdentifier) async throws -> FileProviderItem
    public func enumerateItems(in container: NSFileProviderItemIdentifier, page: Data?) async throws -> (items: [FileProviderItem], nextPage: Data?)
    public func changes(in container: NSFileProviderItemIdentifier, since anchor: NSFileProviderSyncAnchor) async throws -> ChangeBatch
    public func currentAnchor() async throws -> NSFileProviderSyncAnchor
    public func fetchContents(for identifier: NSFileProviderItemIdentifier, into directory: URL, progress: Progress) async throws -> (URL, FileProviderItem)
    public func createItem(template: NSFileProviderItem, fields: NSFileProviderItemFields, contents: URL?, mayAlreadyExist: Bool, progress: Progress) async throws -> FileProviderItem
    public func modifyItem(_ item: NSFileProviderItem, baseVersion: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents: URL?, progress: Progress) async throws -> FileProviderItem
    public func deleteItem(_ identifier: NSFileProviderItemIdentifier) async throws
}
```

Behavior (from spec §5):
- **`item(for:)`:** `.rootContainer` maps to the root row. Other identifiers are looked up in the store; unknown ones throw `NSFileProviderError(.noSuchItem)`. No SMB call is made.
- **Page tokens:** `Data(String(offset).utf8)`. A nil page, or one equal to `NSFileProviderPage.initialPageSortedByName` / `initialPageSortedByDate` raw data, means offset 0. The extension converts the page before calling the engine.
- **`enumerateItems` for a folder:**
  - At offset 0 it lists over SMB and diffs with `FolderScanner` against `store.children(of:)`.
  - It runs `store.apply` with `scannedAt: now()`, and calls `signalWorkingSet()` if the diff wasn't empty and the folder had been scanned before.
  - It then returns `store.children(of:offset:limit:pageSize)`. `nextPage` is set when a full page was returned.
- **`.workingSet`:** pages over `store.nonRootItems` without any SMB calls. `.trashContainer` throws `NSFileProviderError(.noSuchItem)`.
- **`changes(in:since:)`:**
  1. Decode the anchor as an Int64 string. If `anchor < (oldestRetainedSeq ?? anchor+1) - 1` and changes were pruned, throw `NSFileProviderError(.syncAnchorExpired)`. Precisely: expired when `oldest != nil && anchor + 1 < oldest!`.
  2. Rescan: for `.workingSet`, use `foldersNeedingScan(olderThan: now() - rescanInterval, limit: maxFoldersPerRescan)`. For a specific folder, rescan just that folder. Each folder is listed and diffed. A `.notFound` while listing a non-root folder deletes that folder via `recordLocalDelete`.
  3. Fetch `changes(after: anchor, limit: changeBatchSize)` and dedupe by identifier, keeping the last kind. An `update` whose row no longer exists is skipped. For a specific container, keep only changes whose `parentIdentifier` is the container.
  4. The new anchor is the last change's seq, or the unchanged anchor if there are none. `moreComing` is true when the batch was full.
  5. Call `pruneChanges(keepLast: changesRetained)` at the end.
- **`currentAnchor`:** `NSFileProviderSyncAnchor(Data(String(store.currentAnchor()).utf8))`.
- **`fetchContents`:**
  1. `stat` the record's path.
  2. Download to `directory/<UUID>-<name>`, updating `progress.totalUnitCount` and `completedUnitCount` and returning `!progress.isCancelled`.
  3. `recordLocalUpsert` the stat'ed record if its version changed.
  4. Return the URL and the item.
- **`createItem`:**
  1. The parent comes from `template.parentItemIdentifier`; a `.rootContainer` parent maps to `ItemRecord.rootIdentifier`.
  2. The path is the parent path joined with `template.filename`.
  3. A folder template (`contentType == .folder`) calls `createDirectory`. Anything else uploads `contents` (or an empty temp file when nil) with `overwrite: false`.
  4. On `.alreadyExists` with `mayAlreadyExist`, stat and return the existing item (inserting or upserting the record). Without `mayAlreadyExist`, throw.
  5. On success, stat, `recordLocalUpsert` with a new UUID identifier, and return.
- **`modifyItem`:**
  1. If `changedFields` contains `.filename` or `.parentItemIdentifier`, `move` to the new path, then `recordLocalMove`.
  2. If `changedFields` contains `.contents` and `contents != nil`, `stat` the server path:
     - If the server's `contentVersion` ≠ `baseVersion.contentVersion` (conflict), upload to `ConflictNamer.name(...)` in the same folder with `overwrite: false`, `recordLocalUpsert` that conflict record with a new identifier, call `signalWorkingSet()`, and return the original item refreshed from the server.
     - Otherwise upload with `overwrite: true`, stat, `recordLocalUpsert` with the same identifier, and return.
  3. Other fields (dates, tags) are ignored; return the current item.
- **`deleteItem`:** `remove(path)` then `recordLocalDelete`. A `.notFound` from the server is treated as success.
- **Errors:** every SMB failure reaches the caller as `SMBError`. The extension converts it with `FileProviderErrors.nsError`.

`FileProviderErrors.nsError` mapping:

| Error | NSError |
|---|---|
| `.authenticationFailed` | `NSFileProviderError(.notAuthenticated)` |
| `.serverUnreachable` | `NSFileProviderError(.serverUnreachable)` |
| `.notFound` | `NSFileProviderError(.noSuchItem)` |
| `.alreadyExists` | `NSFileProviderError(.filenameCollision)` |
| `.noSpace` | `NSFileProviderError(.insufficientQuota)` |
| `.permissionDenied` | `CocoaError(.fileWriteNoPermission)` |
| `.fileInUse` | `NSFileProviderError(.cannotSynchronize)` |
| `.cancelled` | `CocoaError(.userCancelled)` |
| `.encryptionUnsupported` | `NSFileProviderError(.serverUnreachable)` |
| `.notEmpty`, `.other` | `CocoaError(.fileWriteUnknown)` with the message in `NSLocalizedDescriptionKey` |

An `NSError` that's already in `NSFileProviderErrorDomain` passes through unchanged.

`FileProviderItem`:
- **Identity:** root record → `.rootContainer`, filename `rootDisplayName`. Parent identifier is `.rootContainer` when `parentIdentifier == ItemRecord.rootIdentifier`.
- **`contentType`:** `.folder` for directories, otherwise `UTType(filenameExtension: ext) ?? .data`.
- **`documentSize`:** nil for directories.
- **Capabilities:**
  - Root: `[.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems]`
  - Directories: `[.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsReparenting, .allowsDeleting]`
  - Files: `[.allowsReading, .allowsWriting, .allowsRenaming, .allowsReparenting, .allowsDeleting]`
- **`itemVersion`:** `NSFileProviderItemVersion(contentVersion: record.contentVersion, metadataVersion: record.metadataVersion)`.

`ConflictNamer.name("Report.docx", device: "iPad", date)` → `"Report (Conflict iPad 2026-10-05 1432).docx"`. It uses `DateFormatter` with `en_US_POSIX` locale and format `yyyy-MM-dd HHmm` in the given time zone. Names without an extension have no trailing dot.

`ConnectionProvider.withClient`:
1. If there's no client, load the credential (`nil` → throw `SMBError.authenticationFailed`), make a client, and connect.
2. Run `body`. If it throws `SMBError.serverUnreachable`, `reset()`, reconnect once, and retry `body` once.
3. On `.authenticationFailed`, reset and rethrow.

- [ ] **Step 1: Failing tests**

```swift
// ConflictNamerTests.swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct ConflictNamerTests {
    @Test func names() {
        let date = ISO8601DateFormatter().date(from: "2026-10-05T14:32:00Z")!
        let utc = TimeZone(identifier: "UTC")!
        #expect(ConflictNamer.name(for: "Report.docx", device: "iPad", date: date, timeZone: utc) == "Report (Conflict iPad 2026-10-05 1432).docx")
        #expect(ConflictNamer.name(for: "Notes", device: "iPhone", date: date, timeZone: utc) == "Notes (Conflict iPhone 2026-10-05 1432)")
        #expect(ConflictNamer.name(for: "a.b.xlsx", device: "iPad", date: date, timeZone: utc) == "a.b (Conflict iPad 2026-10-05 1432).xlsx")
    }
}
```

```swift
// FileProviderItemTests.swift
import Testing
import Foundation
import FileProvider
import UniformTypeIdentifiers
@testable import ShareLinkKit

@Suite struct FileProviderItemTests {
    @Test func rootFileAndFolderMapping() throws {
        let store = try MetadataStore.inMemory()
        let root = try #require(try store.item(ItemRecord.rootIdentifier))
        let rootItem = FileProviderItem(record: root, rootDisplayName: "Finance")
        #expect(rootItem.itemIdentifier == .rootContainer)
        #expect(rootItem.filename == "Finance")
        #expect(!rootItem.capabilities.contains(.allowsDeleting))

        let file = ItemRecord(identifier: "A", parentIdentifier: ItemRecord.rootIdentifier, relativePath: "a.docx", name: "a.docx",
                              isDirectory: false, size: 42, modified: Date(timeIntervalSince1970: 1), created: nil, fileID: 1, lastScanned: nil)
        let item = FileProviderItem(record: file, rootDisplayName: "Finance")
        #expect(item.parentItemIdentifier == .rootContainer)
        #expect(item.contentType == UTType(filenameExtension: "docx"))
        #expect(item.documentSize == 42)
        #expect(item.capabilities.contains(.allowsWriting))
        #expect(item.itemVersion.contentVersion == file.contentVersion)
    }

    @Test func errorMapping() {
        #expect((FileProviderErrors.nsError(for: SMBError.authenticationFailed) as NSError).code == NSFileProviderError.notAuthenticated.rawValue)
        #expect(FileProviderErrors.nsError(for: SMBError.authenticationFailed).domain == NSFileProviderErrorDomain)
        #expect(FileProviderErrors.nsError(for: SMBError.alreadyExists).code == NSFileProviderError.filenameCollision.rawValue)
        #expect(FileProviderErrors.nsError(for: SMBError.notFound).code == NSFileProviderError.noSuchItem.rawValue)
        #expect(FileProviderErrors.nsError(for: SMBError.permissionDenied).domain == NSCocoaErrorDomain)
    }
}
```

```swift
// ProviderEngineTests.swift
import Testing
import Foundation
import FileProvider
import UniformTypeIdentifiers
@testable import ShareLinkKit

/// Minimal template used for createItem.
final class Template: NSObject, NSFileProviderItem {
    let itemIdentifier = NSFileProviderItemIdentifier("template")
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    init(parent: NSFileProviderItemIdentifier, name: String, type: UTType) { parentItemIdentifier = parent; filename = name; contentType = type }
}

@Suite struct ProviderEngineTests {
    struct Harness {
        let fake: FakeSMBClient
        let engine: ProviderEngine
        let store: MetadataStore
        let signals: SignalCounter
    }
    final class SignalCounter: @unchecked Sendable { var count = 0; let lock = NSLock(); func hit() { lock.withLock { count += 1 } } }
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_000); let lock = NSLock()
        func advance(_ s: TimeInterval) { lock.withLock { now += s } }; func get() -> Date { lock.withLock { now } } }

    func makeHarness(clock: Clock = Clock(), credential: Credential? = Credential(username: "jdoe", password: "pw")) throws -> Harness {
        let fake = FakeSMBClient()
        let creds = InMemoryCredentialStore()
        let server = ServerConfig(id: "s", source: .user, displayName: "Finance", host: "h", share: "S")
        if let credential { try creds.setCredential(credential, for: "s") }
        let store = try MetadataStore.inMemory()
        let signals = SignalCounter()
        let engine = ProviderEngine(server: server, store: store,
                                    connection: ConnectionProvider(server: server, credentials: creds, factory: FakeSMBClientFactory(client: fake)),
                                    deviceName: "iPad", now: { clock.get() }, signalWorkingSet: { signals.hit() })
        return Harness(fake: fake, engine: engine, store: store, signals: signals)
    }
    func tmp(_ s: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try Data(s.utf8).write(to: u); return u
    }

    @Test func enumerateRootListsServerAndHidesJunk() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("A".utf8), modified: .now, fileID: 1)
        await h.fake.seedFile("~$a.docx", contents: Data(), modified: .now, fileID: 2)
        await h.fake.seedDirectory("Docs")
        let (items, next) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        #expect(items.map(\.filename) == ["a.docx", "Docs"])
        #expect(next == nil)
    }

    @Test func pagination() async throws {
        let h = try makeHarness()
        for i in 0..<(ProviderEngine.pageSize + 5) { await h.fake.seedFile(String(format: "f%04d.txt", i), contents: Data(), modified: .now, fileID: UInt64(i + 1)) }
        let (first, next) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        #expect(first.count == ProviderEngine.pageSize)
        let (second, end) = try await h.engine.enumerateItems(in: .rootContainer, page: try #require(next))
        #expect(second.count == 5)
        #expect(end == nil)
        #expect(await h.fake.listCount == 1)   // later pages come from the DB
    }

    @Test func missingCredentialIsNotAuthenticated() async throws {
        let h = try makeHarness(credential: nil)
        await #expect(throws: SMBError.authenticationFailed) { _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil) }
    }

    @Test func changesDetectRemoteEditsAfterRescanInterval() async throws {
        let clock = Clock(); let h = try makeHarness(clock: clock)
        await h.fake.seedFile("a.docx", contents: Data("A".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let anchor = try await h.engine.currentAnchor()
        await h.fake.replaceSave("a.docx", contents: Data("AB".utf8), modified: Date(timeIntervalSince1970: 2))
        let early = try await h.engine.changes(in: .workingSet, since: anchor)
        #expect(early.updated.isEmpty)                    // not stale yet
        clock.advance(ProviderEngine.rescanInterval + 1)
        let batch = try await h.engine.changes(in: .workingSet, since: anchor)
        #expect(batch.updated.map(\.filename) == ["a.docx"])
        #expect(batch.updated[0].documentSize == 2)
        #expect(batch.deleted.isEmpty)
        let again = try await h.engine.changes(in: .workingSet, since: batch.anchor)
        #expect(again.updated.isEmpty && again.deleted.isEmpty)
    }

    @Test func remoteDeleteReported() async throws {
        let clock = Clock(); let h = try makeHarness(clock: clock)
        await h.fake.seedFile("a.docx", contents: Data(), modified: .now, fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let anchor = try await h.engine.currentAnchor()
        try await h.fake.remove("a.docx")
        clock.advance(ProviderEngine.rescanInterval + 1)
        let batch = try await h.engine.changes(in: .workingSet, since: anchor)
        #expect(batch.deleted == [items[0].itemIdentifier])
    }

    @Test func expiredAnchor() async throws {
        let h = try makeHarness()
        for i in 0..<(ProviderEngine.changesRetained + 10) {
            try h.store.recordLocalUpsert(ItemRecord(identifier: "I\(i)", parentIdentifier: ItemRecord.rootIdentifier, relativePath: "f\(i)", name: "f\(i)",
                                                    isDirectory: false, size: 0, modified: .now, created: nil, fileID: 0, lastScanned: nil))
        }
        _ = try await h.engine.changes(in: .workingSet, since: NSFileProviderSyncAnchor(Data("\(ProviderEngine.changesRetained + 9)".utf8)))   // triggers prune
        await #expect(throws: NSFileProviderError.self) {
            _ = try await h.engine.changes(in: .workingSet, since: NSFileProviderSyncAnchor(Data("1".utf8)))
        }
    }

    @Test func fetchContentsDownloads() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("hello".utf8), modified: .now, fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (url, item) = try await h.engine.fetchContents(for: items[0].itemIdentifier, into: dir, progress: Progress())
        #expect(try Data(contentsOf: url) == Data("hello".utf8))
        #expect(item.filename == "a.docx")
    }

    @Test func createFileAndFolder() async throws {
        let h = try makeHarness()
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let folder = try await h.engine.createItem(template: Template(parent: .rootContainer, name: "New", type: .folder), fields: [], contents: nil, mayAlreadyExist: false, progress: Progress())
        let file = try await h.engine.createItem(template: Template(parent: folder.itemIdentifier, name: "b.txt", type: .plainText), fields: [.contents], contents: try tmp("B"), mayAlreadyExist: false, progress: Progress())
        #expect(await h.fake.contents(of: "New/b.txt") == Data("B".utf8))
        #expect(file.parentItemIdentifier == folder.itemIdentifier)
        await #expect(throws: SMBError.alreadyExists) {
            _ = try await h.engine.createItem(template: Template(parent: .rootContainer, name: "New", type: .folder), fields: [], contents: nil, mayAlreadyExist: false, progress: Progress())
        }
        let existing = try await h.engine.createItem(template: Template(parent: .rootContainer, name: "New", type: .folder), fields: [], contents: nil, mayAlreadyExist: true, progress: Progress())
        #expect(existing.itemIdentifier == folder.itemIdentifier)
    }

    @Test func modifyContentsOverwritesInPlace() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("old".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let updated = try await h.engine.modifyItem(items[0], baseVersion: items[0].itemVersion, changedFields: [.contents], contents: try tmp("new!"), progress: Progress())
        #expect(await h.fake.contents(of: "a.docx") == Data("new!".utf8))
        #expect(updated.itemIdentifier == items[0].itemIdentifier)
        #expect(updated.documentSize == 4)
    }

    @Test func modifyWithStaleBaseCreatesConflictCopy() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data("v1".utf8), modified: Date(timeIntervalSince1970: 1), fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        await h.fake.replaceSave("a.docx", contents: Data("server".utf8), modified: Date(timeIntervalSince1970: 5))
        let result = try await h.engine.modifyItem(items[0], baseVersion: items[0].itemVersion, changedFields: [.contents], contents: try tmp("local"), progress: Progress())
        #expect(await h.fake.contents(of: "a.docx") == Data("server".utf8))           // server copy untouched
        let names = try await h.fake.list("").map(\.name)
        #expect(names.contains { $0.hasPrefix("a (Conflict iPad ") && $0.hasSuffix(").docx") })
        #expect(result.documentSize == 6)
        #expect(h.signals.count >= 1)
    }

    @Test func renameFolderThenFetchChild() async throws {
        let h = try makeHarness()
        await h.fake.seedDirectory("Docs")
        await h.fake.seedFile("Docs/x.txt", contents: Data("x".utf8), modified: .now, fileID: 2)
        let (rootItems, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        let docs = rootItems[0]
        let (children, _) = try await h.engine.enumerateItems(in: docs.itemIdentifier, page: nil)
        let renamedTemplate = Template(parent: .rootContainer, name: "Papers", type: .folder)
        let renamed = try await h.engine.modifyItem(ItemWithIdentifier(docs.itemIdentifier, template: renamedTemplate), baseVersion: docs.itemVersion,
                                                    changedFields: [.filename], contents: nil, progress: Progress())
        #expect(renamed.itemIdentifier == docs.itemIdentifier)
        #expect(renamed.filename == "Papers")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (url, child) = try await h.engine.fetchContents(for: children[0].itemIdentifier, into: dir, progress: Progress())
        #expect(child.itemIdentifier == children[0].itemIdentifier)
        #expect(try Data(contentsOf: url) == Data("x".utf8))
    }

    @Test func deleteRemovesAndToleratesMissing() async throws {
        let h = try makeHarness()
        await h.fake.seedFile("a.docx", contents: Data(), modified: .now, fileID: 1)
        let (items, _) = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        try await h.fake.remove("a.docx")
        try await h.engine.deleteItem(items[0].itemIdentifier)
        await #expect(throws: (any Error).self) { _ = try await h.engine.item(for: items[0].itemIdentifier) }
    }

    @Test func reconnectsOnceAfterDroppedConnection() async throws {
        let h = try makeHarness()
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        await h.fake.failNext(.serverUnreachable)
        _ = try await h.engine.enumerateItems(in: .rootContainer, page: nil)
        #expect(await h.fake.connectCount == 2)
    }
}

/// An item that reuses an identifier with new name/parent (how the system describes a rename).
final class ItemWithIdentifier: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    init(_ id: NSFileProviderItemIdentifier, template: Template) {
        itemIdentifier = id; parentItemIdentifier = template.parentItemIdentifier; filename = template.filename; contentType = template.contentType
    }
}
```

`FakeSMBClientFactory(client:)` must return the same fake each time; the fake's `connect()` increments `connectCount`. A disconnect followed by `connect()` must work.

Run: `swift test --filter "ConflictNamerTests|FileProviderItemTests|ProviderEngineTests"` → FAIL.

- [ ] **Step 2: Implement** the five files per the behavior list above. Keep `ProviderEngine` free of extension-only APIs; it receives directories, `Progress`, and the signal closure from the caller.
- [ ] **Step 3: Verify** — `swift test` (all unit tests; integration suites skip without Docker) → PASS.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add File Provider item model, error mapping, and provider engine"`

---

### Task 9: File Provider extension wiring

**Files:**
- Modify: `Extensions/FileProvider/FileProviderExtension.swift`, `Extensions/FileProvider/FileProviderEnumerator.swift`
- Create: `Sources/ShareLinkKit/Support/Log.swift` (needed here; Task 12 extends it)

**Interfaces:**
- Consumes: `ProviderEngine`, `ConnectionProvider`, `MetadataStore`, `ConfigStore.shared()`, `KeychainCredentialStore`, `AMSMB2ClientFactory`, `FileProviderErrors`, `AppGroup.domainDirectory(for:)`
- Produces: `Log` with `static let app`, `static let provider`, `static let smb` (`os.Logger`, subsystem `com.ajthom90.sharelink`), plus `DiagnosticLog.append(_ line: String)`. `DiagnosticLog` appends to `AppGroup.containerURL()/diagnostics.log` and keeps the last 500 lines (trimmed when the file exceeds 256 KB). `DiagnosticLog.tail(_ n: Int) -> [String]`.

- [ ] **Step 1: Implement `Log.swift`**:
  - `Log.app`, `Log.provider`, and `Log.smb` are `Logger(subsystem: "com.ajthom90.sharelink", category: ...)`.
  - `DiagnosticLog` is an `enum` with static functions. It writes `ISO8601 timestamp + " " + line + "\n"` with `FileHandle` (seek to end), guarded by an `NSLock`.
  - Callers must never pass secrets. Messages contain only error types and counts, never usernames, paths, or hostnames.
- [ ] **Step 2: Implement the extension**:

```swift
import FileProvider
import ShareLinkKit

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let engine: ProviderEngine?

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let serverID = domain.identifier.rawValue
        if let server = ConfigStore.shared().server(id: serverID),
           let store = try? MetadataStore(directory: AppGroup.domainDirectory(for: serverID)) {
            let connection = ConnectionProvider(server: server, credentials: KeychainCredentialStore(), factory: AMSMB2ClientFactory())
            let manager = NSFileProviderManager(for: domain)
            // UIDevice is main-actor-only; the app stores the model name in App Group defaults.
            let deviceName = AppGroup.defaults().string(forKey: AppGroup.deviceModelKey) ?? "iOS"
            engine = ProviderEngine(server: server, store: store, connection: connection,
                                    deviceName: deviceName,
                                    signalWorkingSet: { manager?.signalEnumerator(for: .workingSet) { _ in } })
        } else {
            engine = nil
            DiagnosticLog.append("provider: no configuration for domain")
        }
        super.init()
    }

    func invalidate() {}
    // ... each protocol method:
    //   guard let engine else { completion(..., NSFileProviderError(.notAuthenticated)) ; return Progress() }
    //   let progress = Progress(totalUnitCount: 100)
    //   let task = Task { do { let r = try await engine.X(...); completion(r...) } catch { completion(..., FileProviderErrors.nsError(for: error)) } }
    //   progress.cancellationHandler = { task.cancel() }
    //   return progress
}
```

Wire each method exactly:
- **`item(for:)`** → `engine.item(for:)`.
- **`fetchContents`** → `engine.fetchContents(for:into:progress:)`, where `into` is `try NSFileProviderManager(for: domain)!.temporaryDirectoryURL()`.
- **`createItem`** → `engine.createItem(template:fields:contents:mayAlreadyExist: options.contains(.mayAlreadyExist), progress:)`. Completion is `(item, [], false, nil)`.
- **`modifyItem`** → `engine.modifyItem(...)`. Completion is `(item, [], false, nil)`.
- **`deleteItem`** → `engine.deleteItem(identifier)`. Completion is `(nil)`.
- **`enumerator(for:)`** → `FileProviderEnumerator(container:engine:)`. Throws `NSFileProviderError(.notAuthenticated)` when `engine == nil`.

Swift 6: completion handlers are not `Sendable`. Wrap them as `nonisolated(unsafe) let completion = completionHandler` before capturing in the `Task`.

`FileProviderEnumerator`:

```swift
import FileProvider
import ShareLinkKit

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private let engine: ProviderEngine
    init(container: NSFileProviderItemIdentifier, engine: ProviderEngine) { self.container = container; self.engine = engine }
    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        nonisolated(unsafe) let observer = observer
        let raw = page.rawValue
        let isInitial = raw == NSFileProviderPage.initialPageSortedByName as Data || raw == NSFileProviderPage.initialPageSortedByDate as Data
        Task {
            do {
                let (items, next) = try await engine.enumerateItems(in: container, page: isInitial ? nil : raw)
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: next.map { NSFileProviderPage($0) })
            } catch { observer.finishEnumeratingWithError(FileProviderErrors.nsError(for: error)) }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        nonisolated(unsafe) let observer = observer
        Task {
            do {
                let batch = try await engine.changes(in: container, since: anchor)
                if !batch.updated.isEmpty { observer.didUpdate(batch.updated) }
                if !batch.deleted.isEmpty { observer.didDeleteItems(withIdentifiers: batch.deleted) }
                observer.finishEnumeratingChanges(upTo: batch.anchor, moreComing: batch.moreComing)
            } catch { observer.finishEnumeratingWithError(FileProviderErrors.nsError(for: error)) }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        nonisolated(unsafe) let completion = completionHandler
        Task { completion(try? await engine.currentAnchor()) }
    }
}
```

- [ ] **Step 3: Verify**

```bash
xcodegen generate
xcodebuild -project ShareLink.xcodeproj -scheme ShareLink -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet
cd Packages/ShareLinkKit && swift test --filter ShareLinkKitTests
```
Expected: `** BUILD SUCCEEDED **` with no Swift 6 concurrency errors; unit tests pass.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "Wire File Provider extension to provider engine"`

---

### Task 10: Domain reconciliation and the app model

**Files:**
- Create: `Sources/ShareLinkKit/App/DomainReconciler.swift`, `Sources/ShareLinkKit/App/AppModel.swift`
- Create: `Tests/ShareLinkKitTests/Fakes/FakeDomainManager.swift`
- Create: `App/ShareLink/Platform/FileProviderDomainManager.swift`, `App/ShareLink/Platform/ManagedConfigObserver.swift`
- Test: `Tests/ShareLinkKitTests/DomainReconcilerTests.swift`, `Tests/ShareLinkKitTests/AppModelTests.swift`

**Interfaces:**
- Produces:

```swift
public struct DomainInfo: Equatable, Sendable { public var id: String; public var displayName: String }
public protocol DomainManaging: Sendable {
    func domains() async throws -> [DomainInfo]
    func addOrUpdate(id: String, displayName: String) async throws
    func remove(id: String) async throws
    func signalWorkingSet(id: String) async
    func evictAll(id: String) async
    func userVisibleRootURL(id: String) async -> URL?
}
public struct ReconcileResult: Equatable, Sendable { public var added: [String]; public var removed: [String]; public var renamed: [String] }
public struct DomainReconciler: Sendable {
    public init(manager: any DomainManaging, credentials: any CredentialStoring,
                removeLocalData: @escaping @Sendable (String) -> Void = { try? FileManager.default.removeItem(at: AppGroup.domainDirectory(for: $0)) })
    public func reconcile(servers: [ServerConfig]) async throws -> ReconcileResult
}
public enum ServerStatus: Equatable, Sendable { case needsSignIn, signedIn, error(String) }
@MainActor @Observable public final class AppModel {
    public private(set) var servers: [ServerConfig]
    public private(set) var allowUserServers: Bool
    public private(set) var supportMessage: String
    public private(set) var configIssues: [String]
    public private(set) var statuses: [String: ServerStatus]
    public var signInRequest: ServerConfig?
    public init(configStore: ConfigStore, credentials: any CredentialStoring, domains: any DomainManaging,
                clientFactory: any SMBClientFactory, feedbackDefaults: UserDefaults = .standard, appVersion: String = "")
    public func start(managedConfig: [String: Any]) async
    public func applyManagedConfiguration(_ dict: [String: Any]) async
    public func signIn(serverID: String, username: String, password: String) async throws   // throws SMBError
    public func signOut(serverID: String) async
    public func saveUserServer(_ server: ServerConfig, username: String, password: String?) async throws
    public func removeUserServer(id: String) async
    public func testConnection(_ server: ServerConfig, username: String, password: String) async -> SMBError?
    public func savedUsername(for serverID: String) -> String?
    public func makeBrowserClient(for serverID: String) -> (any SMBClient)?
    public func handle(url: URL)                     // sharelink://signin?domain=<id> → signInRequest
    public func appDidBecomeActive() async            // signal working sets for signed-in servers
    public func openInFilesURL(for serverID: String) async -> URL?   // file URL → "shareddocuments://" URL
    public func status(for serverID: String) -> ServerStatus
}
```

Reconciler rules:
- Domains whose id isn't in `servers` are removed: `manager.remove`, `credentials.removeCredential`, `removeLocalData`.
- Servers without a domain are added.
- Domains whose display name differs are re-added with `addOrUpdate`, which counts as `renamed`.

AppModel rules:
- **`start(managedConfig:)`:**
  1. Parse with `ManagedConfigParser` and save `configStore.managed`.
  2. If `allowUserServers == false`, also delete the user servers (`configStore.userServers = []`).
  3. Refresh the published properties and reconcile.
  4. Compute statuses: `signedIn` if a credential exists, else `needsSignIn`.
  5. Write `ManagedFeedback`.
  6. If `signInRequest == nil`, set it to the first *managed* server with `needsSignIn`.
- **`applyManagedConfiguration`:** same as `start`, but only when the parsed result differs from the stored one.
- **`signIn`:**
  1. Build `Credential(username:password:)` and run `ConnectionTester`.
  2. On error, set the status to `.error(error.userMessage)` and throw it. Exception: auth failure keeps `.needsSignIn` and throws `.authenticationFailed`.
  3. On success, save the credential, set `.signedIn`, `signalWorkingSet`, clear `signInRequest` when it matches, and rewrite the feedback.
- **`signOut`:** removes the credential, calls `evictAll`, sets `.needsSignIn`, and rewrites the feedback.
- **`saveUserServer`:**
  1. Throw `SMBError.other("Adding servers is disabled by your organization.")` when not allowed.
  2. Validate that host and share are non-empty; otherwise throw `SMBError.other("Server and share are required.")`.
  3. With a password, test first (same as sign-in), then save.
  4. Save the config, reconcile, and update statuses.
- **`removeUserServer`:** only for `.user` sources. Removes from the store, reconciles (which deletes credentials and data), and drops the status.
- **`savedUsername`:** the credential's username, otherwise the server's configured `username`.
- **`makeBrowserClient`:** returns `clientFactory.makeClient` when a credential exists.

- [ ] **Step 1: Failing tests**

```swift
// Fakes/FakeDomainManager.swift
import Foundation
@testable import ShareLinkKit

actor FakeDomainManager: DomainManaging {
    var current: [String: String] = [:]
    var signaled: [String] = []
    var evicted: [String] = []
    func domains() async throws -> [DomainInfo] { current.map { DomainInfo(id: $0.key, displayName: $0.value) }.sorted { $0.id < $1.id } }
    func addOrUpdate(id: String, displayName: String) async throws { current[id] = displayName }
    func remove(id: String) async throws { current[id] = nil }
    func signalWorkingSet(id: String) async { signaled.append(id) }
    func evictAll(id: String) async { evicted.append(id) }
    func userVisibleRootURL(id: String) async -> URL? { URL(fileURLWithPath: "/private/var/mobile/Library/CloudStorage/\(id)") }
}
```

```swift
// DomainReconcilerTests.swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct DomainReconcilerTests {
    @Test func addsRemovesRenames() async throws {
        let mgr = FakeDomainManager()
        try await mgr.addOrUpdate(id: "gone", displayName: "Old")
        try await mgr.addOrUpdate(id: "keep", displayName: "Before")
        let creds = InMemoryCredentialStore()
        try creds.setCredential(Credential(username: "u", password: "p"), for: "gone")
        let removedData = LockedBox<[String]>([])
        let r = DomainReconciler(manager: mgr, credentials: creds, removeLocalData: { id in removedData.mutate { $0.append(id) } })
        let servers = [
            ServerConfig(id: "keep", source: .user, displayName: "After", host: "h", share: "s"),
            ServerConfig(id: "new", source: .user, displayName: "New", host: "h", share: "s"),
        ]
        let result = try await r.reconcile(servers: servers)
        #expect(result == ReconcileResult(added: ["new"], removed: ["gone"], renamed: ["keep"]))
        #expect(try await mgr.domains().map(\.id) == ["keep", "new"])
        #expect(try creds.credential(for: "gone") == nil)
        #expect(removedData.value == ["gone"])
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private var v: T; private let l = NSLock()
    init(_ v: T) { self.v = v }
    var value: T { l.withLock { v } }
    func mutate(_ f: (inout T) -> Void) { l.withLock { f(&v) } }
}
```

```swift
// AppModelTests.swift
import Testing
import Foundation
@testable import ShareLinkKit

@MainActor @Suite struct AppModelTests {
    func make() -> (AppModel, FakeDomainManager, InMemoryCredentialStore, FakeSMBClient, UserDefaults) {
        let fake = FakeSMBClient()
        let creds = InMemoryCredentialStore()
        let mgr = FakeDomainManager()
        let fb = UserDefaults(suiteName: "fb-\(UUID().uuidString)")!
        let model = AppModel(configStore: ConfigStore(defaults: UserDefaults(suiteName: "cs-\(UUID().uuidString)")!),
                             credentials: creds, domains: mgr, clientFactory: FakeSMBClientFactory(client: fake),
                             feedbackDefaults: fb, appVersion: "1.0.0 (1)")
        return (model, mgr, creds, fake, fb)
    }
    let managed: [String: Any] = ["Host": "files.example.com", "Share": "Shared", "Username": "jdoe", "SupportMessage": "Use your network password"]

    @Test func startWithManagedConfigRequestsSignIn() async throws {
        let (model, mgr, _, _, fb) = make()
        await model.start(managedConfig: managed)
        #expect(model.servers.count == 1)
        #expect(model.signInRequest?.id == model.servers[0].id)
        #expect(model.status(for: model.servers[0].id) == .needsSignIn)
        #expect(model.savedUsername(for: model.servers[0].id) == "jdoe")
        #expect(try await mgr.domains().count == 1)
        #expect((fb.dictionary(forKey: ManagedFeedback.key)?["ConfiguredShares"] as? Int) == 1)
    }

    @Test func signInSuccessAndFailure() async throws {
        let (model, mgr, creds, fake, fb) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        await fake.failNext(.authenticationFailed)
        await #expect(throws: SMBError.authenticationFailed) { try await model.signIn(serverID: id, username: "jdoe", password: "bad") }
        #expect(model.status(for: id) == .needsSignIn)
        try await model.signIn(serverID: id, username: "jdoe", password: "good")
        #expect(model.status(for: id) == .signedIn)
        #expect(try creds.credential(for: id)?.password == "good")
        #expect(model.signInRequest == nil)
        #expect(await mgr.signaled.contains(id))
        #expect((fb.dictionary(forKey: ManagedFeedback.key)?["SignedInShares"] as? Int) == 1)
    }

    @Test func signOutEvicts() async throws {
        let (model, mgr, creds, _, _) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        try await model.signIn(serverID: id, username: "jdoe", password: "pw")
        await model.signOut(serverID: id)
        #expect(try creds.credential(for: id) == nil)
        #expect(await mgr.evicted == [id])
        #expect(model.status(for: id) == .needsSignIn)
    }

    @Test func managedRemovalRemovesDomain() async throws {
        let (model, mgr, _, _, _) = make()
        await model.start(managedConfig: managed)
        await model.applyManagedConfiguration([:])
        #expect(model.servers.isEmpty)
        #expect(try await mgr.domains().isEmpty)
    }

    @Test func userServersBlockedWhenDisallowed() async throws {
        let (model, _, _, _, _) = make()
        await model.start(managedConfig: managed.merging(["AllowUserServers": false]) { $1 })
        let s = ServerConfig(id: ServerConfig.newUserID(), source: .user, displayName: "Mine", host: "nas.example.com", share: "Home")
        await #expect(throws: SMBError.self) { try await model.saveUserServer(s, username: "me", password: nil) }
    }

    @Test func addAndRemoveUserServer() async throws {
        let (model, mgr, _, _, _) = make()
        await model.start(managedConfig: [:])
        let s = ServerConfig(id: ServerConfig.newUserID(), source: .user, displayName: "Mine", host: "nas.example.com", share: "Home")
        try await model.saveUserServer(s, username: "me", password: "pw")
        #expect(model.status(for: s.id) == .signedIn)
        #expect(try await mgr.domains().map(\.id) == [s.id])
        await model.removeUserServer(id: s.id)
        #expect(model.servers.isEmpty)
        #expect(try await mgr.domains().isEmpty)
    }

    @Test func deepLinkSelectsServer() async throws {
        let (model, _, _, _, _) = make()
        await model.start(managedConfig: managed)
        let id = model.servers[0].id
        model.signInRequest = nil
        model.handle(url: URL(string: "sharelink://signin?domain=\(id)")!)
        #expect(model.signInRequest?.id == id)
    }

    @Test func openInFilesURLUsesSharedDocumentsScheme() async throws {
        let (model, _, _, _, _) = make()
        await model.start(managedConfig: managed)
        let url = await model.openInFilesURL(for: model.servers[0].id)
        #expect(url?.scheme == "shareddocuments")
    }
}
```

Run: `swift test --filter "DomainReconcilerTests|AppModelTests"` → FAIL. Implement. Run → PASS.

- [ ] **Step 2: App-side adapters**

`App/ShareLink/Platform/FileProviderDomainManager.swift`:

```swift
import FileProvider
import ShareLinkKit

struct FileProviderDomainManager: DomainManaging {
    func domains() async throws -> [DomainInfo] {
        try await NSFileProviderManager.domains().map { DomainInfo(id: $0.identifier.rawValue, displayName: $0.displayName) }
    }
    func addOrUpdate(id: String, displayName: String) async throws {
        try await NSFileProviderManager.add(NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: displayName))
    }
    func remove(id: String) async throws {
        let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: "")
        try await NSFileProviderManager.remove(domain, mode: .removeAll)
    }
    private func manager(_ id: String) async -> NSFileProviderManager? {
        guard let d = try? await NSFileProviderManager.domains().first(where: { $0.identifier.rawValue == id }) else { return nil }
        return NSFileProviderManager(for: d)
    }
    func signalWorkingSet(id: String) async { try? await manager(id)?.signalEnumerator(for: .workingSet) }
    func evictAll(id: String) async { try? await manager(id)?.evictItem(identifier: .rootContainer) }
    func userVisibleRootURL(id: String) async -> URL? { try? await manager(id)?.getUserVisibleURL(for: .rootContainer) }
}
```

If `NSFileProviderManager.remove(_:mode:)` is not available on iOS 17, fall back to `remove(_:)` with `if #available`. Check the SDK headers.

`App/ShareLink/Platform/ManagedConfigObserver.swift` watches `UserDefaults.didChangeNotification` on `.standard`. When it fires, it reads `UserDefaults.standard.dictionary(forKey: ManagedConfigParser.managedConfigKey) ?? [:]` and calls `await model.applyManagedConfiguration(dict)` on the main actor.

- [ ] **Step 3: Verify** — `swift test --filter ShareLinkKitTests` passes; `xcodegen generate && xcodebuild ... build` succeeds.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add domain reconciliation and app model"`

---

### Task 11: SwiftUI app — servers, sign-in, server forms, detail

**Files:**
- Modify: `App/ShareLink/ShareLinkApp.swift`
- Create: `App/ShareLink/Views/RootView.swift`, `WelcomeView.swift`, `ServerRow.swift`, `SignInView.swift`, `ServerFormView.swift`, `ServerDetailView.swift`

**Interfaces:**
- Consumes: `AppModel` and everything it exposes (Task 10), `FileProviderDomainManager`, `ManagedConfigObserver`, `KeychainCredentialStore`, `AMSMB2ClientFactory`, `ConfigStore.shared()`

UI requirements:
- **`ShareLinkApp`:**
  - Creates one `AppModel` with real dependencies; `appVersion` = `"\(CFBundleShortVersionString) (\(CFBundleVersion))"`.
  - In `.task`, calls `start(managedConfig:)` with the managed dictionary and starts `ManagedConfigObserver`.
  - On `scenePhase == .active`, calls `appDidBecomeActive()`.
  - `.onOpenURL` calls `model.handle(url:)`.
  - At launch, writes `UIDevice.current.model` to `AppGroup.defaults()` under `AppGroup.deviceModelKey`. The extension reads it for conflict-copy names.
  - Puts the model in the environment (`.environment(model)`).
- **`RootView`:**
  - `NavigationSplitView`. The sidebar is a `List(selection:)` of servers: managed first, under a "Managed by your organization" section header, then user servers under "My Servers".
  - Toolbar "+" button (`Label("Add Server", systemImage: "plus")`) only when `allowUserServers`. A gear button opens `SettingsView` in a sheet (Task 12; use an empty placeholder view named `SettingsView` until then).
  - Detail column: `ServerDetailView` for the selection, otherwise `WelcomeView`.
  - Sheet bound to `model.signInRequest` shows `SignInView`. If `configIssues` is non-empty, an inline warning section at the bottom of the sidebar lists them.
- **`WelcomeView`:**
  - No servers: `ContentUnavailableView` titled "Welcome to ShareLink" with system image `externaldrive.connected.to.line.below`. The description reads "Connect to SMB file shares and open documents from the Files app." There's an "Add Server" button when allowed. When not allowed, the text reads "Your organization hasn't configured any shares yet."
  - Servers exist but none is selected: "Select a server".
- **`ServerRow`:**
  - Icon `server.rack`, display name, and `summary` in secondary text.
  - A lock icon (`lock.fill`, accessibility label "Managed") for managed servers.
  - A status dot: green signed in, orange needs sign-in, red error. Each dot has an accessibility label.
- **`SignInView`** (`NavigationStack` + `Form`):
  - Header: display name and summary (read-only).
  - Optional `supportMessage` footer.
  - Username `TextField`: `.textContentType(.username)`, autocapitalization off, autocorrection disabled, disabled when `usernameLocked`. Pre-filled from `savedUsername`.
  - A domain hint line when `server.domain` is non-empty: "Domain: EXAMPLE".
  - `SecureField` password with `.textContentType(.password)`.
  - "Sign In" button with a `ProgressView` while working, disabled when fields are empty. On error it shows `error.userMessage` in red under the form.
  - Cancel button; Return submits.
- **`ServerFormView`** (add/edit user servers):
  - Fields: display name, host (`.keyboardType(.URL)`), port (number pad, default 445), share, path, domain, username, password (optional in edit), and a "Require encryption" toggle.
  - "Test Connection" button showing ✓ or the error message.
  - Save calls `saveUserServer`; display name defaults to `ServerConfig.defaultDisplayName` when blank.
- **`ServerDetailView`:**
  - `Form` sections. Status: label plus "Last error" when `.error`. Connection details: host, share, path, domain, port, and Encryption Required / Not Required.
  - Actions:
    - "Open in Files" (opens `openInFilesURL` with `openURL`)
    - "Browse" (`NavigationLink` to `BrowserView` — Task 12; placeholder view until then)
    - "Sign In" / "Sign Out" (with a confirmation dialog)
    - "Edit" and "Remove Server" (destructive, with confirmation) for user servers only
  - Managed servers show the footer "This server is managed by your organization."
- All text uses system fonts. No fixed frame sizes except icons. Every icon-only button has an accessibility label.

- [ ] **Step 1: Implement the views** per the requirements above.
- [ ] **Step 2: Add SwiftUI previews** for `WelcomeView`, `ServerRow`, and `SignInView`. They use an `AppModel` built with `InMemoryCredentialStore`, a preview `DomainManaging` stub inside the app target, and `AMSMB2ClientFactory`.
- [ ] **Step 3: Verify**

```bash
xcodegen generate
xcodebuild -project ShareLink.xcodeproj -scheme ShareLink -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet
```
Then run on a simulator:
```bash
xcrun simctl boot "iPad Pro 13-inch (M5)" 2>/dev/null || true   # any available iPad; list with: xcrun simctl list devices available
xcodebuild -project ShareLink.xcodeproj -scheme ShareLink -destination 'platform=iOS Simulator,name=<that iPad>' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/ShareLink.app
xcrun simctl launch booted com.ajthom90.sharelink
xcrun simctl io booted screenshot build/welcome.png
```
Expected: the build succeeds and the screenshot shows the welcome screen. Note it in PROGRESS.md; do not commit the screenshot.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add SwiftUI server list, sign-in, server form, and detail views"`

---

### Task 12: Browser, Quick Look, settings, diagnostics, acknowledgements

**Files:**
- Create: `App/ShareLink/Views/BrowserView.swift`, `QuickLookView.swift`, `SettingsView.swift`, `AcknowledgementsView.swift`
- Create: `Sources/ShareLinkKit/Support/Diagnostics.swift`, `Sources/ShareLinkKit/Support/Acknowledgements.swift`
- Test: `Tests/ShareLinkKitTests/DiagnosticsTests.swift`, `Tests/ShareLinkKitTests/AcknowledgementsTests.swift`

**Interfaces:**
- Produces:
  - `enum Diagnostics { static func report(servers: [ServerConfig], statuses: [String: ServerStatus], issues: [String], appVersion: String, logTail: [String]) -> String }`
  - `struct Acknowledgement: Identifiable, Sendable { id: String; name: String; license: String; text: String }`
  - `enum Acknowledgements { static func all() -> [Acknowledgement] }`, which reads `Bundle.module` `Licenses/*.txt`
  - `@MainActor @Observable final class BrowserModel` (in `Sources/ShareLinkKit/App/BrowserModel.swift`) with `init(client: any SMBClient, path: String)`, `entries: [RemoteEntry]`, `error: SMBError?`, `isLoading`, `func load() async`, and `func download(_ entry: RemoteEntry) async throws -> URL` (into a temp dir, keeping the original filename)

- [ ] **Step 1: Failing tests**

```swift
// DiagnosticsTests.swift
import Testing
@testable import ShareLinkKit

@Suite struct DiagnosticsTests {
    @Test func redactsSecretsAndHosts() {
        let s = ServerConfig(id: "managed-1-abc", source: .managed(slot: 1), displayName: "Finance", host: "files.example.com",
                             share: "Shared", rootPath: "Finance/Reports", domain: "EXAMPLE", username: "jdoe")
        let text = Diagnostics.report(servers: [s], statuses: [s.id: .signedIn], issues: ["Share 2: missing Share2.Host"],
                                      appVersion: "1.0.0 (3)", logTail: ["provider: enumerate ok"])
        #expect(text.contains("1.0.0 (3)"))
        #expect(text.contains("managed slot 1"))
        #expect(text.contains("signed in"))
        #expect(text.contains("Share 2: missing Share2.Host"))
        #expect(text.contains("provider: enumerate ok"))
        #expect(!text.contains("jdoe"))
        #expect(text.contains("j***"))
        #expect(!text.contains("files.example.com"))
        #expect(text.contains("f***.com"))
    }
}
```

```swift
// AcknowledgementsTests.swift
import Testing
@testable import ShareLinkKit

@Suite struct AcknowledgementsTests {
    @Test func bundledLicensesPresent() {
        let names = Acknowledgements.all().map(\.name)
        #expect(names.contains("ShareLink"))
        #expect(names.contains("libsmb2"))
        #expect(names.contains("AMSMB2"))
        #expect(names.contains("GRDB.swift"))
        let libsmb2 = Acknowledgements.all().first { $0.name == "libsmb2" }!
        #expect(libsmb2.text.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
        #expect(libsmb2.text.contains("RSA Data Security, Inc. MD4 Message-Digest Algorithm"))
    }
}
```

The `Acknowledgements` test depends on Task 13's license files. Create them now as part of this task:
- `Resources/Licenses/libsmb2.txt`:
  - an intro naming libsmb2 and linking to its source
  - the copyright line from libsmb2's `COPYING`
  - the statement that it's LGPL-2.1-or-later
  - a "Source code" paragraph pointing to `https://github.com/ajthom90/ShareLink/releases`
  - the RFC 4634/2104 notice: "Portions derived from IETF RFC 4634 and RFC 2104 reference code. Copyright (c) The IETF Trust and the persons identified as the document authors. All rights reserved."
  - the RSA line: "derived from the RSA Data Security, Inc. MD4 Message-Digest Algorithm"
  - the full LGPL-2.1 text, copied from `.build/checkouts/AMSMB2/Dependencies/libsmb2/LICENCE-LGPL-2.1.txt`
- `AMSMB2.txt`: AMSMB2's `LICENSE` file content plus its copyright line.
- `GRDB.swift.txt`: GRDB's `LICENSE`.
- `ShareLink-MIT.txt`: already exists.

`Acknowledgements.all()` maps file stems to names: `ShareLink-MIT` → "ShareLink", `libsmb2`, `AMSMB2`, and `GRDB.swift`. The license labels are "MIT", "LGPL-2.1-or-later", "LGPL-2.1", and "MIT". Order: ShareLink first, then alphabetical.

Diagnostics redaction:
- **Usernames:** first character + `***`.
- **Hosts:** first character + `***` + the last label (`.com`); IP addresses become `x.x.x.<last octet>`.
- **Paths and share names:** omitted.
- **Each server line:** `- <displayName> (managed slot N | user): <status>, encryption <required|optional>, user <redacted>, host <redacted>`.

- [ ] **Step 2: Implement**
  - `Diagnostics` and `Acknowledgements` in the package, plus `BrowserModel` with a unit test using `FakeSMBClient`: `load` lists and filters hidden names, folders first then alphabetical; `download` writes the file.
  - **`BrowserView`:**
    - A `List` of entries with a folder or document icon, size (`ByteCountFormatter`), and modified date (`.formatted(date: .abbreviated, time: .shortened)`).
    - Tapping a folder pushes another `BrowserView`; tapping a file downloads it and presents `QuickLookView`.
    - Swipe action and context menu: "Share…", using `ShareLink(item: url)` after download.
    - Pull to refresh, a loading state, and an error state (`ContentUnavailableView` with `error.userMessage` and a Retry button).
    - The client comes from `model.makeBrowserClient`, and is connected on first appearance.
  - **`QuickLookView`:** a `UIViewControllerRepresentable` wrapping `QLPreviewController` for one URL.
  - **`SettingsView`:**
    - Sections: About (version; "Source Code" link to `https://github.com/ajthom90/ShareLink`; "Report an Issue" link to `/issues`) and Support ("Copy Diagnostics", which copies `Diagnostics.report(...)` with `DiagnosticLog.tail(200)` to `UIPasteboard.general` and shows a confirmation).
    - A NavigationLink to "Acknowledgements".
    - Footer: "ShareLink is free and open source under the MIT License. It includes libsmb2 and AMSMB2 under the GNU LGPL 2.1."
  - **`AcknowledgementsView`:** a list of names with license labels, each pushing a scrollable monospaced text view.
- [ ] **Step 3: Verify** — `swift test --filter ShareLinkKitTests` passes; the simulator build succeeds.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add file browser, Quick Look, settings, diagnostics, and acknowledgements"`

---

### Task 13: Documentation, MDM artifacts, licensing

**Files:**
- Create: `README.md`, `THIRD_PARTY_LICENSES.md`, `MDM/README.md`, `MDM/sharelink-appconfig.xml`, `MDM/example-managed-config.plist`, `docs/TESTING.md`, `docs/privacy.md`, `scripts/package-third-party-sources.sh`
- Test: `Tests/ShareLinkKitTests/MDMArtifactsTests.swift`

**Interfaces:**
- Consumes: the managed config keys (Task 2) and `ManagedConfigParser`.

- [ ] **Step 1: Failing test.** The example plist must parse cleanly with the real parser, and every key in the AppConfig XML must be a key the parser knows.

```swift
import Testing
import Foundation
@testable import ShareLinkKit

@Suite struct MDMArtifactsTests {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()   // Tests/ShareLinkKitTests/X.swift -> repo root

    @Test func examplePlistParses() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("MDM/example-managed-config.plist"))
        let dict = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let cfg = ManagedConfigParser.parse(dict)
        #expect(cfg.issues.isEmpty)
        #expect(cfg.servers.count == 2)
        #expect(cfg.servers.allSatisfy { $0.host.hasSuffix("example.com") })
    }

    @Test func appConfigKeysAreKnown() throws {
        let xml = try String(contentsOf: repoRoot.appendingPathComponent("MDM/sharelink-appconfig.xml"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"keyName="([^"]+)""#)
        let keys = Set(regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).map { String(xml[Range($0.range(at: 1), in: xml)!]) })
        let base = ["Host", "Share", "Path", "DisplayName", "Port", "Domain", "Username", "UsernameLocked", "RequireEncryption"]
        let known = Set(["AllowUserServers", "SupportMessage"] + base + base.map { "Share2.\($0)" })
        #expect(!keys.isEmpty)
        #expect(keys.isSubset(of: known))
    }
}
```

- [ ] **Step 2: Write the artifacts**
  - **`MDM/example-managed-config.plist`:** a plist dictionary with share 1 (`Host` `files.example.com`, `Share` `Departments`, `Path` `Finance`, `DisplayName` `Finance`, `Domain` `EXAMPLE`, `Username` `jdoe`) and share 2 (`Share2.Host` `archive.example.com`, `Share2.Share` `Archive`, `Share2.RequireEncryption` true), plus `AllowUserServers` false and `SupportMessage`.
  - **`MDM/sharelink-appconfig.xml`:** AppConfig Specification format (`<managedAppConfiguration>`, `<version>1</version>`, `<bundleId>com.ajthom90.sharelink</bundleId>`).
    - A `<dict>` with typed entries for all share-1 keys, the two global keys, and the `Share2.*` keys (string/integer/boolean with defaults: Port 445, booleans false, AllowUserServers true).
    - A `<presentation defaultLocale="en-US">` with field groups "Share 1", "Share 2", and "Options", giving each field a label and description.
  - **`MDM/README.md`:**
    - A key reference table, the same as spec §4.
    - The numbered-share explanation (`Share2.` … `Share10.`).
    - Miradore steps:
      1. Management → Applications → add ShareLink from the App Store (VPP/Apps and Books) as a managed app.
      2. Under the app's deployment, open Managed app configuration and use **Add new** for each key/value.
      3. For `Username`, use Miradore's user variable for the user name. Check Miradore's variable list in the console for the exact token.
      4. Deploy.
    - "What users see" steps.
    - Feedback keys reported back (`ConfiguredShares`, `SignedInShares`, `ConfigErrors`, `AppVersion`).
    - A generic section for other MDMs (upload `sharelink-appconfig.xml`).
  - **`README.md`:**
    - What ShareLink does, with a feature list and screenshots placeholder text *removed*: no placeholder sections; describe features only.
    - Requirements (iOS 17).
    - "For IT admins" (link MDM/README.md); "Using with Microsoft Office" (Files → Browse → ShareLink location; Word/Excel/PowerPoint Open → Browse).
    - "Building from source":
      1. `brew install xcodegen`
      2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set the Team ID
      3. `xcodegen generate`
      4. open the project
      5. The App Group `group.com.ajthom90.sharelink` must be changed to your own if you fork.
    - "Running tests" (`swift test`, Docker Samba).
    - "Licensing": MIT for ShareLink; LGPL-2.1 for libsmb2/AMSMB2, which are dynamically linked as `AMSMB2.framework`. To use a modified libsmb2, rebuild ShareLink from this source against your modified AMSMB2/libsmb2 (point the package dependency at your fork) and install it on your device. Link THIRD_PARTY_LICENSES.md.
    - Privacy: no data collected (link docs/privacy.md).
  - **`THIRD_PARTY_LICENSES.md`:** human-readable notices for libsmb2 (LGPL-2.1-or-later, with the copyright, RFC 4634/2104 notice, and RSA MD4 attribution), AMSMB2 (LGPL-2.1), and GRDB.swift (MIT). Include the full license texts or links to the bundled files in `Packages/ShareLinkKit/Sources/ShareLinkKit/Resources/Licenses/`. Add a "Corresponding source" section: each GitHub Release attaches `third-party-sources-<version>.tar.gz`.
  - **`docs/privacy.md`:** ShareLink collects no data. Credentials stay in the device Keychain, and connections go only to servers you or your organization configure. No analytics, no third-party SDKs that collect data. Contact via GitHub Issues.
  - **`docs/TESTING.md`:** how to run unit tests, Samba integration (`docker compose -f Tests/Samba/docker-compose.yml up -d --build`), and the real-server read-only test via `SHARELINK_TEST_SERVER_JSON=$PWD/TestServer.local.json`. Includes the **manual Office acceptance checklist**:
    1. MDM config applied, or user server added.
    2. Sign in.
    3. Files → Browse shows the ShareLink location with the display name.
    4. Open `.docx` in Word from Files; edit; wait for AutoSave; verify the server's file mtime and contents from a desktop.
    5. Same for `.xlsx` (Excel) and `.pptx` (PowerPoint).
    6. Create a new document in Word and save to the ShareLink location.
    7. Rename and delete in Files.
    8. Edit the same file on a desktop while open on the iPad → a conflict copy appears.
    9. Wrong password → Files prompts to open ShareLink.
    10. Airplane mode → "server unreachable".
    11. Remove the share from MDM → the location disappears.
  - **`scripts/package-third-party-sources.sh <outdir>`:** reads the AMSMB2 and GRDB versions from `Packages/ShareLinkKit/Package.resolved` (run `swift package resolve` first if it's missing). It runs `git clone --depth 1 --branch <version> --recurse-submodules --shallow-submodules` for each into a temp dir, removes `.git` dirs, and writes `<outdir>/third-party-sources-<ShareLink MARKETING_VERSION>.tar.gz`.
  - Make sure `Packages/ShareLinkKit/Package.resolved` is committed (remove any ignore rule for it).
- [ ] **Step 3: Verify** — `swift test --filter "MDMArtifactsTests|AcknowledgementsTests"` → PASS; `plutil -lint MDM/example-managed-config.plist` OK; `xmllint --noout MDM/sharelink-appconfig.xml` OK; `./scripts/package-third-party-sources.sh build/` produces a tarball containing `AMSMB2/Dependencies/libsmb2/lib/libsmb2.c`; `./scripts/check-secrets.sh` exit 0.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add documentation, MDM configuration artifacts, and license notices"`

---

### Task 14: TestFlight pipeline

**Files:**
- Create: `scripts/testflight.sh`, `scripts/ExportOptions.plist`, `docs/RELEASING.md`
- Modify: `docs/PROGRESS.md`

**Interfaces:**
- Consumes: `Config/Local.xcconfig` (git-ignored, must set `DEVELOPMENT_TEAM`), `.env` (git-ignored), `scripts/check-secrets.sh`, `scripts/package-third-party-sources.sh`

- [ ] **Step 1: `scripts/ExportOptions.plist`** (no team ID; the script injects it into a temp copy):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><false/>
</dict>
</plist>
```

- [ ] **Step 2: `scripts/testflight.sh`** (chmod +x) with flags `--dry-run` and `--internal-only`:

```bash
#!/usr/bin/env bash
# Archive ShareLink and upload it to App Store Connect / TestFlight.
#   --dry-run        archive + export locally (destination=export) without uploading
#   --internal-only  mark the build for internal TestFlight testing only
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DRY_RUN=0; INTERNAL_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --internal-only) INTERNAL_ONLY=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

[[ -f Config/Local.xcconfig ]] || { echo "Missing Config/Local.xcconfig (copy from Config/Local.xcconfig.example)" >&2; exit 1; }
TEAM_ID=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]{10}).*/\1/p' Config/Local.xcconfig | head -1)
[[ -n "$TEAM_ID" ]] || { echo "DEVELOPMENT_TEAM not set in Config/Local.xcconfig" >&2; exit 1; }

AUTH_ARGS=()
if [[ -f .env ]]; then set -a; . ./.env; set +a; fi
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
elif [[ $DRY_RUN -eq 0 ]]; then
  echo "Set ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH in .env (or sign in to Xcode and accept interactive auth)" >&2
fi

./scripts/check-secrets.sh
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean; commit first" >&2; exit 1; }

xcodegen generate
BUILD_NUMBER=$(( $(git rev-list --count HEAD) + ${BUILD_OFFSET:-0} ))
VERSION=$(sed -nE 's/^MARKETING_VERSION[[:space:]]*=[[:space:]]*(.*)$/\1/p' Config/Base.xcconfig)
ARCHIVE="build/ShareLink-$VERSION-$BUILD_NUMBER.xcarchive"
rm -rf "$ARCHIVE" build/export

xcodebuild -project ShareLink.xcodeproj -scheme ShareLink -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates "${AUTH_ARGS[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

APP="$ARCHIVE/Products/Applications/ShareLink.app"
if find "$APP/PlugIns" -name '*.framework' -maxdepth 3 | grep -q .; then
  echo "ERROR: nested frameworks inside the extension; App Store will reject this build" >&2; exit 1
fi
[[ -d "$APP/Frameworks/AMSMB2.framework" ]] || { echo "ERROR: AMSMB2.framework not embedded (LGPL dynamic-link requirement)" >&2; exit 1; }

OPTS=build/ExportOptions.plist
cp scripts/ExportOptions.plist "$OPTS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTS"
[[ $INTERNAL_ONLY -eq 1 ]] && /usr/libexec/PlistBuddy -c "Set :testFlightInternalTestingOnly true" "$OPTS"
[[ $DRY_RUN -eq 1 ]] && /usr/libexec/PlistBuddy -c "Set :destination export" "$OPTS"

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTS" \
  -exportPath build/export -allowProvisioningUpdates "${AUTH_ARGS[@]}"

if [[ $DRY_RUN -eq 0 ]]; then
  TAG="v$VERSION-$BUILD_NUMBER"
  git tag -a "$TAG" -m "TestFlight build $VERSION ($BUILD_NUMBER)"
  ./scripts/package-third-party-sources.sh build/
  echo "Uploaded $VERSION ($BUILD_NUMBER). Next: git push origin $TAG && gh release create $TAG build/third-party-sources-$VERSION.tar.gz --prerelease --notes 'TestFlight build'"
else
  echo "Dry run complete: build/export"
fi
```

- [ ] **Step 3: `docs/RELEASING.md`:**
  - **One-time setup:**
    1. Apple Developer account.
    2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set the Team ID.
    3. In App Store Connect, create the app record: name "ShareLink" (or an available variant), bundle ID `com.ajthom90.sharelink`, SKU `sharelink-ios`. The bundle ID and App Group are registered automatically on the first archive via `-allowProvisioningUpdates`; if not, register them in the developer portal: App ID `com.ajthom90.sharelink` + `.FileProvider`, both with App Groups capability → `group.com.ajthom90.sharelink`.
    4. Create an App Store Connect API key (Users and Access → Integrations → Team Keys, App Manager role), save the `.p8` outside the repo, and fill `.env`.
    5. In TestFlight, create an internal group and add testers.
  - **Each build:** `./scripts/testflight.sh --internal-only`, then push the tag and create the GitHub prerelease with the third-party source tarball (the LGPL corresponding-source requirement).
  - **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` is set, so no questionnaire.
  - **Moving to App Store:** privacy policy URL (GitHub Pages `docs/privacy.md` or the raw GitHub URL), support URL (GitHub Issues), screenshots (iPhone 6.9", iPad 13"), App Privacy "Data Not Collected", Standard EULA (see spec §2.1), and price Free.
- [ ] **Step 4: Verify**:
  - `bash -n scripts/testflight.sh` → no syntax errors.
  - `./scripts/check-secrets.sh` → exit 0.
  - With `Config/Local.xcconfig` present locally (the reviewer provides it), run `./scripts/testflight.sh --dry-run` → archive succeeds, both checks pass, export completes.
  - If `Config/Local.xcconfig` is absent, the script must exit 1 with the "Missing Config/Local.xcconfig" message.
- [ ] **Step 5: Update `docs/PROGRESS.md`** with all task statuses, then commit — `git add -A && git commit -m "Add TestFlight archive/upload pipeline and release docs"`

---

## Self-Review Notes

- **Spec coverage:**
  - §2 dependencies → Task 1
  - §2.1 licence compliance → Tasks 12, 13, 14 (dynamic framework check, notices, source tarball)
  - §3 units → Tasks 2–10
  - §4 MDM → Tasks 2, 3, 10, 13
  - §5 File Provider → Tasks 6–9
  - §6 UI → Tasks 11–12
  - §7 security/privacy → Tasks 1, 3, 12, 13
  - §8 hygiene → Task 1
  - §9 testing → Tasks 5, 13
  - §10 TestFlight → Task 14
- **Deliberate deviation from spec §6:** iPhone uses `NavigationSplitView`, which collapses to a stack on compact width. This gives the same behavior as a separate `NavigationStack` path with less code.
