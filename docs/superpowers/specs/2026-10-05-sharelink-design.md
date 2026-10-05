# ShareLink — Design Spec

Date: 2026-10-05
Status: Approved design, pending written-spec review

## 1. Purpose

ShareLink is a free, open-source (MIT) iOS/iPadOS app that connects devices to SMB
file shares and exposes them in the Files app so Microsoft Office (Word, Excel,
PowerPoint) and other apps can open, edit, and save documents directly on the
server.

It is built for organizations that manage iPhones and iPads with an MDM (the
first deployment uses Miradore). Admins push the server, share, and path through
managed app configuration; users only sign in with their own credentials.
Individuals without MDM can add servers manually.

### Success criteria

1. A user on an MDM-configured device opens ShareLink, enters only their
   password (username pre-filled), and the share appears in the Files sidebar.
2. From Word/Excel/PowerPoint on iPhone or iPad, the user browses to the share
   via Files, opens a document, edits it, and the changes are saved to the
   server (including AutoSave).
3. Works against Windows Server with default security (SMB signing required)
   and against Samba; optional SMB3 encryption.
4. Distributed through internal TestFlight first, then free on the App Store.
5. No proprietary information (server names, domains, org names, Team ID,
   credentials) is ever committed to the public repository.

### Non-goals (v1)

- Kerberos / SSO, certificates, or smart-card authentication.
- "Keep offline" pinning or background sync of whole folders.
- SMB1, NetBIOS browsing, or Bonjour/network discovery.
- Server-side search; Files search covers enumerated items only.
- macOS / Mac Catalyst target.

## 2. Platform & dependencies

| Item | Choice |
|---|---|
| Minimum OS | iOS / iPadOS 17.0 |
| UI | SwiftUI |
| Language | Swift 6 (strict concurrency) |
| SMB | [AMSMB2](https://github.com/amosavian/AMSMB2) (LGPL-2.1) with bundled libsmb2 (LGPL-2.1-or-later), via SwiftPM, linked **dynamically** (AMSMB2's product is `type: .dynamic`) |
| Metadata DB | [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT) — SQLite in the App Group container |
| Project generation | XcodeGen (`project.yml`); the `.xcodeproj` is not committed |
| License | ShareLink's own code: MIT. Third-party: see §2.1 |

### 2.1 License compliance (LGPL-2.1)

Audit findings (from the AMSMB2 source at the pinned version):

- **AMSMB2** — the repo's `LICENSE` file is LGPL-2.1. Its README describes
  the Swift code as MIT but says the combined project "becomes LGPL v2.1" and
  must be linked dynamically for the App Store. It is treated as LGPL.
- **libsmb2** `lib/` + `include/` — LGPL-2.1-or-later. The `examples/`
  directory (BSD-2) is not compiled.
- Bundled crypto in libsmb2: `aes_reference.c` and `md5.c` are public domain;
  `sha1.c`, `sha224-256.c`, `sha384-512.c`, `usha.c`, `hmac.c`, and
  `hmac-md5.c` come from RFC 4634 / RFC 2104 (IETF, BSD-style, notice
  required); `md4c.c` is RSA Data Security MD4 (requires the attribution "derived
  from the RSA Data Security, Inc. MD4 Message-Digest Algorithm").
- No GPL-only (non-"Lesser") files are compiled.
- GRDB.swift — MIT.

How ShareLink satisfies LGPL-2.1 §6 (the "work that uses the Library"):

1. **Dynamic linking**: AMSMB2 and libsmb2 ship as a separate
   `AMSMB2.framework` (SwiftPM `type: .dynamic`) shared by the app and the
   extension. They are not statically merged into ShareLink's binary.
2. **Modification and relinking**: ShareLink's complete source, the build
   instructions (`README.md`), and the exact dependency versions
   (`Package.resolved` committed) are public on GitHub. Anyone can rebuild
   ShareLink against a modified libsmb2/AMSMB2 and install it on their own
   device. ShareLink's MIT license permits modification and reverse
   engineering.
3. **Source availability**: each TestFlight/App Store release has a GitHub
   Release whose assets include the exact AMSMB2 + libsmb2 source tarball
   used for that build (`scripts/package-third-party-sources.sh`). The source
   therefore stays available even if upstream repositories change.
4. **Notices**:
   - `THIRD_PARTY_LICENSES.md` in the repo, and an in-app Settings →
     Acknowledgements screen.
   - Both include the full LGPL-2.1 text, the libsmb2/AMSMB2 copyright
     notices, the RFC 4634 / RFC 2104 notices, and the RSA MD4 attribution.
   - Both state that the libraries are LGPL and link to the source.
   - The licence files are bundled as resources and read at runtime, so they
     always match what ships.
5. **App Store EULA**: ShareLink uses Apple's Standard EULA. It prohibits
   reverse engineering and modification "except … to the extent as may be
   permitted by the licensing terms governing use of any open-sourced
   components included with the Licensed Application", so the LGPL terms
   continue to govern libsmb2/AMSMB2. This is the same route AMSMB2's authors
   document for App Store use ("link dynamically").

Residual risk: the FSF has argued that App Store terms conflict with GPL-family
"no further restrictions" clauses. LGPL apps with dynamic linking and public
source are common on the App Store, and the EULA carve-out above applies, but
this is not legal advice. If Apple or a copyright holder ever raises it, the
fallback is to ask the libsmb2 author for an App Store exception or to swap the
`SMBClient` implementation (the protocol boundary in §3.1 isolates it).

SMB protocol: dialect negotiation up to SMB 3.1.1. libsmb2 enables signing when
the server requires it. `RequireEncryption` turns on SMB3 encryption (seal)
and fails the connection if the server can't encrypt.

## 3. Architecture

```
┌──────────────────────────┐        ┌──────────────────────────────┐
│ ShareLink (app)          │        │ ShareLinkFileProvider (appex)│
│  SwiftUI UI              │        │  NSFileProviderReplicated-   │
│  ManagedConfigObserver   │        │  Extension                   │
│  DomainReconciler        │        │  Enumerators / ItemMapper    │
└──────────┬───────────────┘        └──────────────┬───────────────┘
           │            links                      │ links
           ▼                                       ▼
┌───────────────────────────────────────────────────────────────────┐
│ ShareLinkKit (Swift package, extension-safe APIs only)             │
│  SMBClient protocol + AMSMB2SMBClient   ServerConfig models        │
│  ManagedConfigParser   ConfigStore (App Group defaults)            │
│  CredentialStore (Keychain, shared access group)                   │
│  MetadataStore (GRDB)   ItemVersioning   Logging (no secrets)      │
└───────────────────────────────────────────────────────────────────┘
       shared App Group: group.com.ajthom90.sharelink
```

Targets:

| Target | Type | Bundle ID |
|---|---|---|
| `ShareLink` | iOS app | `com.ajthom90.sharelink` |
| `ShareLinkFileProvider` | File Provider extension | `com.ajthom90.sharelink.FileProvider` |
| `ShareLinkKit` | Local Swift package (`Packages/ShareLinkKit`), linked into app + extension | — |
| `ShareLinkKitTests` | Package unit tests (`swift test`, macOS) | — |
| `ShareLinkIntegrationTests` | Package tests against Docker Samba (`swift test`, macOS) | — |

ShareLinkKit holds all non-UI logic, including the File Provider engine and
item types (the FileProvider framework also exists on macOS), so it is tested
on macOS without a simulator. AMSMB2 stays a separate dynamic framework
embedded once in the app; the extension links it from the app's `Frameworks`
directory and must not contain its own copy (checked at archive time).

Shared entitlements: App Group `group.com.ajthom90.sharelink`; keychain access
group using the App Group identifier so no Team ID appears in source.

### 3.1 Units and responsibilities

- **`SMBClient` (protocol)** — `connect`, `disconnect`, `list(path)`,
  `stat(path)`, `download(path, to: URL, progress)`, `upload(from: URL, to:
  path, progress)`, `createDirectory`, `move(from:to:)`, `remove(path,
  recursive)`. Returns `RemoteEntry { name, path, isDirectory, size,
  modified, created, fileID }`. Errors map to `SMBError { .authenticationFailed,
  .notFound, .alreadyExists, .permissionDenied, .serverUnreachable,
  .encryptionUnsupported, .noSpace, .other(String) }`. The fake used by unit
  tests implements the same protocol in memory.
- **`AMSMB2SMBClient`** — the only file importing AMSMB2. Owns one
  `SMB2Manager` per domain, reconnects once on a dropped connection, and maps
  errno/NTSTATUS errors to `SMBError`.
- **`ServerConfig`** — `id`, `source (.managed(slot) | .user)`, `displayName`,
  `host`, `port`, `share`, `rootPath`, `domain`, `username`,
  `usernameLocked`, `requireEncryption`. Managed IDs are deterministic:
  `managed-<slot>-<sha256(host|share|rootPath) prefix>` so a re-pushed
  identical config keeps the same Files location and cache.
- **`ManagedConfigParser`** — pure function `[String: Any] →
  ManagedConfiguration { servers, allowUserServers, supportMessage, issues }`.
- **`ConfigStore`** — persists normalized server list + global settings in App
  Group `UserDefaults` for the extension to read.
- **`CredentialStore`** — Keychain `kSecClassGenericPassword` (service
  `com.ajthom90.sharelink`, account = server ID) holding JSON
  `{username, password}`; `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; shared access
  group. Passwords never written to logs, defaults, or the metadata DB.
- **`DomainReconciler`** (app) — makes `NSFileProviderManager` domains match
  `ConfigStore`: adds missing domains, removes domains whose server is gone
  (plus their credentials and metadata DB), updates display names.
- **`MetadataStore`** — per-domain SQLite (described in §5).
- **File Provider extension** — `FileProviderExtension`, `ItemEnumerator`,
  `WorkingSetEnumerator`, `FileProviderItem`. Contains no SMB-specific logic
  beyond calling `SMBClient`.

## 4. Managed configuration (MDM)

Delivered via `com.apple.configuration.managed` in the app's
`UserDefaults.standard`. Miradore supports only flat key/value pairs, so all
keys are flat.

- **Share 1** uses unprefixed keys. **Shares 2–10** use the prefix `ShareN.`
  (e.g. `Share2.Host`).
- Values are parsed leniently: strings `"445"`, `"true"`/`"yes"`/`"1"` are
  accepted for integers and booleans.

| Key | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `Host` | string | yes | — | DNS name or IP of the SMB server |
| `Share` | string | yes | — | Share name |
| `Path` | string | no | `""` | Subfolder within the share used as the root |
| `DisplayName` | string | no | `"<Share> on <Host>"` | Name in ShareLink and the Files sidebar |
| `Port` | int | no | 445 | TCP port |
| `Domain` | string | no | `""` | AD domain (NetBIOS or DNS form) |
| `Username` | string | no | `""` | Pre-fills sign-in; use a Miradore user variable |
| `UsernameLocked` | bool | no | false | Username field is read-only |
| `RequireEncryption` | bool | no | false | Require SMB3 encryption |
| `AllowUserServers` | bool | global | true | false hides "Add Server" and removes user-added servers |
| `SupportMessage` | string | global | `""` | Shown on the sign-in screen |

Behavior:

- The app observes `UserDefaults.didChangeNotification`. On launch and on
  change it re-parses, writes `ConfigStore`, and runs `DomainReconciler`.
- A share entry missing `Host` or `Share` is skipped and recorded as an issue.
- Managed servers can't be edited or deleted in the UI (lock badge).
- Removing a managed share removes its domain, cache, metadata DB, and
  credentials.
- **Feedback**: the app writes `com.apple.feedback.managed` with
  `ConfiguredShares` (int), `SignedInShares` (int), `ConfigErrors` (string
  array), and `AppVersion`.
- The repo ships `MDM/sharelink-appconfig.xml` (AppConfig spec format),
  `MDM/example-managed-config.plist`, and `MDM/README.md` with Miradore
  step-by-step instructions using placeholder values (`files.example.com`).

## 5. File Provider design

`NSFileProviderReplicatedExtension`, one `NSFileProviderDomain` per server
config. The domain identifier is the `ServerConfig.id`.

### 5.1 Identifiers and metadata store

The extension assigns item identifiers as opaque UUIDs; the root is
`.rootContainer`. The per-domain SQLite DB (App Group
`Domains/<id>/metadata.sqlite`) holds:

- `items(identifier PK, parentIdentifier, relativePath UNIQUE, name,
  isDirectory, size, modified, fileID, contentVersion, metadataVersion,
  lastSeenGeneration)`
- `changes(seq INTEGER PK AUTOINCREMENT, identifier, kind ['update'|'delete'])`
- `enumeratedFolders(identifier PK, lastScanned)`

Identifiers stay stable when a folder is renamed: a rename updates the
`relativePath` of the item and the path prefix of its descendants. Server-side
replace-saves at the same path (Office/Windows "save as temp then rename")
keep the identifier because matching is by name within the parent. A
server-side rename is detected when a removed and an added child share the
same non-zero `fileID`; otherwise it shows as delete + create.

### 5.2 Versions

- `contentVersion` = `"<size>-<modified as ns since epoch>"` (UTF-8 data).
- `metadataVersion` = `contentVersion + "-" + name`.

Directories use their modified time with size 0.

### 5.3 Enumeration and change detection

SMB has no change notifications, so changes are found by polling:

1. `enumerateItems` for a container lists the folder over SMB, upserts the
   rows, records the folder in `enumeratedFolders`, and pages results (200
   items per page).
2. `enumerateChanges(from: anchor)` (container and working set): rescans each
   enumerated folder whose `lastScanned` is older than 15 s (capped at the 50
   most recently used folders per call). It diffs against the DB, appends
   `changes` rows, then returns all changes with `seq > anchor`. The new sync
   anchor is the max `seq`.
3. `currentSyncAnchor` = the current max `seq`.
4. If an anchor is older than the oldest retained change (the table is pruned
   to 5,000 rows), return `NSFileProviderError(.syncAnchorExpired)`.
5. After its own successful writes, and after a rescan that found changes, the
   extension calls `signalEnumerator(for: .workingSet)`. The app also signals
   the working set when it comes to the foreground and after a sign-in.

Hidden from enumeration: `.DS_Store`, `Thumbs.db`, `desktop.ini`, `~$*`
(Office owner files), and names starting with `.`. Items the system creates
with those names are still written to the server.

### 5.4 Operations

| Operation | Behavior |
|---|---|
| `item(for:)` | Read from DB; fall back to `stat` if unknown |
| `fetchContents` | Stream download to a temporary file in the extension's temp dir; report progress; return the item with its current version |
| `createItem` | Directory → `createDirectory`; file → stream upload; a name collision returns `.filenameCollision` |
| `modifyItem` contents | Before uploading, `stat` the server file. If its version ≠ the base version the system supplies, upload to `"<name> (Conflict <device> <yyyy-MM-dd HHmm>).<ext>"` in the same folder, then report the original as changed. Otherwise overwrite in place (streamed) to preserve server ACLs |
| `modifyItem` rename/move | `move(from:to:)`; update DB paths (with descendants) |
| `modifyItem` dates only | Ignored (returns item; server keeps its own mtime) |
| `deleteItem` | `remove(path, recursive: true)` — no trash; `.trashContainer` is not supported |

Capabilities: reading, writing, renaming, reparenting, deleting, adding
subitems. No trash and no excluding from sync.

Memory: transfers stream from or to files on disk. Content is never loaded fully into
memory, keeping the extension under its memory limit.

### 5.5 Errors & authentication

| `SMBError` | File Provider error |
|---|---|
| `.authenticationFailed`, missing credentials | `NSFileProviderError(.notAuthenticated)` — Files shows a button to open the app; the app opens to sign-in for that domain |
| `.serverUnreachable` | `NSFileProviderError(.serverUnreachable)` |
| `.notFound` | `NSFileProviderError(.noSuchItem)` |
| `.alreadyExists` | `NSFileProviderError(.filenameCollision)` |
| `.noSpace` | `NSFileProviderError(.insufficientQuota)` |
| `.permissionDenied` | `NSCocoaError(.fileWriteNoPermission)` / `.fileReadNoPermission` |

Signing out keeps the domain (and its Files location) but deletes the
password and evicts downloaded content. The domain then reports
`.notAuthenticated` until the user signs in again.

## 6. App UI

SwiftUI. iPad uses `NavigationSplitView`, iPhone uses `NavigationStack`. System
styles throughout, with Dynamic Type, VoiceOver labels, Dark Mode, and an
accent color and app icon from asset catalogs.

Screens:

1. **Welcome** (no servers, no MDM): explains the app; "Add Server".
2. **Server list** (sidebar/root): managed servers first with a lock badge;
   status dot (signed in / needs sign-in / error); "Add Server" when allowed.
3. **Sign-in sheet**: display name, read-only `host/share/path` summary,
   domain (editable if not managed), username (pre-filled; read-only when
   locked), password, `SupportMessage`, "Sign In". Validates by connecting and
   listing the root before saving the password.
4. **Add/Edit Server** (user servers): form with display name, host, port,
   share, path, domain, username, require-encryption toggle; "Test
   Connection".
5. **Server detail**: status, last error, "Open in Files" (opens the domain
   URL via `NSFileProviderManager.getUserVisibleURL`), "Browse", "Sign Out",
   "Remove" (user servers only).
6. **Browser**: a folder list with icons, sizes, and dates. Tapping a file
   opens Quick Look; files also support Share and "Open in…". Includes pull to
   refresh. It uses `SMBClient` directly; it's a convenience, not a second
   sync path.
7. **Settings / About**: version, "Copy Diagnostics" (config summary without
   secrets, last 200 log lines), Acknowledgements (bundled licence texts per
   §2.1), and a source code link.

Deep link `sharelink://signin?domain=<id>` opens the sign-in sheet; it's used
when Files sends the user to the app after `.notAuthenticated`.

## 7. Security & privacy

- Passwords stay in the Keychain only and are never logged. Logs use `os.Logger`
  with privacy annotations; diagnostics redact usernames to their first letter.
- No analytics, no tracking, no network calls other than to the configured SMB
  servers.
- `PrivacyInfo.xcprivacy` in the app, the extension, and the framework: no
  tracking; required-reason APIs declared (`UserDefaults` `CA92.1`/`1C8F.1`
  app-group, file timestamps `C617.1`).
- **Export compliance**: `ITSAppUsesNonExemptEncryption = NO` in the app and
  extension Info.plists, so TestFlight and App Store uploads skip the
  encryption questionnaire. The app uses only standard encryption (SMB
  signing/encryption and the OS's TLS/Keychain).
- Local Network: SMB to LAN hosts requires `NSLocalNetworkUsageDescription`
  in both the app and the extension.

## 8. Repository hygiene (public from day one)

- `.gitignore` (first commit) excludes `Config/Local.xcconfig`,
  `TestServer.local.json`, `*.local.json`, `*.p8`, `.env*`,
  `ExportOptions.local.plist`, the generated `.xcodeproj`, and build output.
- Committed templates: `Config/Local.xcconfig.example`
  (`DEVELOPMENT_TEAM = YOURTEAMID`), `TestServer.example.json`,
  `.env.example`.
- `Config/Base.xcconfig` includes `Local.xcconfig` optionally
  (`#include? "Local.xcconfig"`).
- Repo-local git identity is the maintainer's personal address.
- `scripts/check-secrets.sh` runs before pushes and in CI. It fails on
  `*.p8` content, `-----BEGIN`, 10-character Team-ID-like values in
  `DEVELOPMENT_TEAM`, and any pattern listed in a git-ignored
  `.proprietary-patterns` file (where org-specific names/domains live
  locally).
- Example values use `example.com` / `EXAMPLE` only.

## 9. Testing

- **Unit tests (`ShareLinkKitTests`, `swift test` on macOS)**: `ManagedConfigParser`
  (single share, numbered shares, lenient types, missing required keys,
  deterministic IDs); `MetadataStore` diffing (add/update/delete/rename by
  fileID, path-prefix rename, anchor expiry); versioning; error mapping; and
  the hidden-file filter. These run against an in-memory `FakeSMBClient`.
- **Integration tests (`ShareLinkIntegrationTests`, `swift test` on macOS)**: run
  `AMSMB2SMBClient` against a Docker Samba container
  (`Tests/Samba/docker-compose.yml`) on port 1445 with `server signing =
  mandatory`, plus a second share with `smb encrypt = required`. They cover
  list, stat, upload/download of a 50 MB file, rename, delete, a wrong-password
  error, and encryption on/off. They're skipped automatically when the
  container isn't running.
- **Manual checks**: against a real server using git-ignored
  `TestServer.local.json`, plus the on-device Office round trip (open .docx
  from Files → edit → AutoSave → verify on server; Excel and PowerPoint same)
  per `docs/TESTING.md`.
- **CI (GitHub Actions, macOS runner)**: XcodeGen generate, build app and
  extension for the simulator without signing, run unit tests, run
  `check-secrets.sh`.

## 10. TestFlight & release

- `project.yml` sets automatic signing; `DEVELOPMENT_TEAM` comes from
  `Config/Local.xcconfig`. `MARKETING_VERSION` lives in `Config/Base.xcconfig`;
  `CURRENT_PROJECT_VERSION` is set at archive time.
- `scripts/testflight.sh`:
  1. Runs `xcodegen generate`.
  2. Sets the build number from `git rev-list --count HEAD` (plus an offset).
  3. Runs `xcodebuild archive -allowProvisioningUpdates`.
  4. Exports with `method = app-store-connect` and `destination = upload`,
     authenticating with an App Store Connect API key from `.env` (`ASC_KEY_ID`,
     `ASC_ISSUER_ID`, `ASC_KEY_PATH`).
- One-time manual steps (documented in `docs/RELEASING.md`):
  1. Create the App Store Connect app record for `com.ajthom90.sharelink`.
  2. Create an API key.
  3. Add internal testers.

  Bundle IDs and the App Group are registered automatically by
  `-allowProvisioningUpdates`.
- Each upload is tagged (`v<version>-<build>`) and gets a GitHub Release with
  the third-party source tarball attached (§2.1, item 3).
- App Store submission later needs a privacy policy URL (GitHub Pages
  `docs/privacy.md`: "collects no data"), screenshots, and a support URL
  (GitHub Issues).

## 11. Open risks

- **Office + File Provider behaviour** differs by Office version; the manual
  round-trip test in §9 is the acceptance gate.
- **Polling staleness**: changes made by other users show up when Files
  re-enumerates or the app signals the working set, not instantly.
- **Server file IDs** may be 0 or unstable on some NAS devices; renames there
  degrade to delete + create, which is still correct.
