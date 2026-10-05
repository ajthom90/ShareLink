# Testing ShareLink

Commands below are run from the repository root unless a step says otherwise. `TestServer.local.json` is git-ignored. The only credential in the repository is the Samba test password `ShareLink-Test-1`.

## Unit tests

```bash
cd Packages/ShareLinkKit && swift test --filter ShareLinkKitTests
```

`swift test` from that directory also builds the integration target. Those tests skip themselves when Docker Samba is not running and when `SHARELINK_TEST_SERVER_JSON` is unset.

## Samba integration

Start the container (SMB signing required on `signed`, SMB encryption required on `encrypted`, published on `127.0.0.1:1445`):

```bash
docker compose -f Tests/Samba/docker-compose.yml up -d --build
```

The account is `testuser` / `ShareLink-Test-1`. Then:

```bash
cd Packages/ShareLinkKit && swift test --filter SambaIntegrationTests
```

If nothing accepts TCP on `127.0.0.1:1445`, the suite is skipped and `swift test` still exits 0. Stop the container with:

```bash
docker compose -f Tests/Samba/docker-compose.yml down
```

## Real-server read-only test

Copy `TestServer.example.json` to `TestServer.local.json` and fill in a server you are allowed to read. The test connects, lists the share root, stats the first entry, and prints the entry count. It does not upload, rename, or delete.

From the repository root, so `$PWD` is the root:

```bash
SHARELINK_TEST_SERVER_JSON=$PWD/TestServer.local.json swift test --package-path Packages/ShareLinkKit --filter RealServerTests
```

The suite is skipped when the variable is unset or the file is not readable.

## Simulator end-to-end (File Provider)

`scripts/e2e-simulator.sh` is the test that actually launches the File Provider extension. Package tests run the provider engine in-process. This script boots the newest available iPad Pro (or iPad Air) simulator, builds ShareLink with signing allowed, and runs `ShareLinkUITests` against the Docker Samba container. When nothing accepts TCP on `127.0.0.1:1445` it prints `SKIP` and exits 0.

```bash
docker compose -f Tests/Samba/docker-compose.yml up -d --build
./scripts/e2e-simulator.sh
```

What a passing run proves:

- The signed simulator build embeds the App Group `group.com.ajthom90.sharelink` for both the app and the extension. Simulator binaries are ad-hoc signed and `codesign -d --entitlements` prints an empty dictionary, so the script reads `*.app-Simulated.xcent` and `*.appex-Simulated.xcent` under `build/DerivedData-e2e/Build/Intermediates.noindex/` (or the `__TEXT,__entitlements` section when those files are absent).
- Managed configuration for the `signed` share reaches the app. The script installs ShareLink and writes `com.apple.configuration.managed` with `simctl spawn defaults write`. `xcodebuild test` can reinstall the app and drop that defaults domain, so the UI test also launches with `-SLE2EManagedConfig`. In Debug builds, `ShareLinkApp.launchManagedConfig()` turns that argument into the same dictionary: host `127.0.0.1`, port `1445`, share `signed`, user `testuser`, display name `Samba Test`.
- Sign-in stores the password in the Keychain shared with the extension. iOS registers a new domain with `userEnabled == false`, so the test opens the Files sidebar, expands Locations, and flips the provider switch off and on (an already-on switch does not enable the domain). With one domain, Files labels that location with the app name "ShareLink" rather than the domain display name "Samba Test"; the display name is what the system stores, and Files applies it in the sidebar only when a second domain exists. The test accepts either label, then requires `hello.txt` in the location. Files' accessibility label writes that name as `hello, txt`. The extension — loading `AMSMB2.framework` from the app's `Frameworks` folder — is what serves the file. On a fresh domain Files can show a listing error after that file is already materialized; the test taps Try Again and still requires `hello.txt`.
- Creating a folder in Files calls through `createItem` to Samba. The test uses New Folder (or Create Folder) and commits whatever default name Files assigns, with Return or a tap outside the inline editor. It does not type a replacement: that rename does not reliably reach the provider. Before the test the script runs `docker compose -f Tests/Samba/docker-compose.yml exec -T samba ls -1 /shares/signed`, removes leftover `untitled folder*` directories, and remembers the directory names. After XCTest it requires at least one new directory and prints its name.
- Uninstall and a keychain reset leave the File Provider domain in place, including materialized names from earlier runs. The simulator does not allow `launchctl disable` of `fileproviderd` from `simctl spawn`, so the script identifies that device's `fileproviderd` and stops it, then removes this provider's domain records: its `Domains.plist`, the FPFS directory under `Library/CloudStorage`, the domain database that references that directory, and the App Group `Domains` index. Launchd starts the daemon again. `E2E_ERASE=1 ./scripts/e2e-simulator.sh` shuts the simulator down and runs `xcrun simctl erase` before boot. That wipes the whole simulator. It is off by default.

Office save-back still needs a device. Word, Excel, and PowerPoint opening a document from Files and writing it back are covered by the on-device checklist in [Manual Office acceptance](#manual-office-acceptance), not by this simulator test.

## Manual Office acceptance

On a device:

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
