# ShareLink

ShareLink is a free, open-source SMB client for iPhone and iPad. It connects to SMB shares and shows them in the Files app, so Microsoft Word, Excel, PowerPoint, and other apps can open, edit, and save documents on the server, including AutoSave.

Organizations that manage devices with an MDM push the server, share, and path through managed app configuration. The user signs in with a password. People without an MDM can add a server themselves.

## Features

- One Files location per configured share, through a File Provider extension, so Office and other apps open and save documents in place.
- Managed app configuration for the server, share, path, port, domain, and username. The username can be pre-filled, and it can be locked. A support message can be shown on the sign-in screen.
- Optional SMB3 encryption when the organization requires it. Signing follows the server: ShareLink works with Windows Server's default security (SMB signing required) and with Samba.
- An in-app browser for a signed-in share: a folder list with sizes and dates, Quick Look, and the system share sheet. Office uses the Files location; the browser is a convenience beside that.
- Settings can copy a diagnostics report with usernames, hosts, paths, and share names redacted, and can show the bundled licence texts.

Sign-in uses a username and password. The app runs on iPhone and iPad.

## Requirements

iOS 17 or iPadOS 17.

## For IT admins

Server settings are a flat managed app configuration dictionary. The key reference, Miradore steps, and the files to upload are in [MDM/README.md](MDM/README.md).

## Using with Microsoft Office

After the share is signed in, open the Files app, tap Browse, and open the ShareLink location. It uses the display name from the configuration. In Word, Excel, or PowerPoint, choose Open, then Browse, and open the same location. Edits, including AutoSave, are written back to the server.

## Building from source

1. `brew install xcodegen`
2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` to your Apple Developer Team ID. `Config/Local.xcconfig` is git-ignored.
3. `xcodegen generate`
4. Open `ShareLink.xcodeproj`.
5. The App Group `group.com.ajthom90.sharelink` must be changed to your own if you fork. It is `AppGroup.identifier` in `Packages/ShareLinkKit/Sources/ShareLinkKit/Support/AppGroup.swift` and the App Group entitlement in `project.yml`. It is also the Keychain access group. Bundle IDs in `project.yml` are `com.ajthom90.sharelink` and `com.ajthom90.sharelink.FileProvider`.

## Running tests

From `Packages/ShareLinkKit`, run `swift test`. Samba integration tests use Docker; the commands, the read-only real-server test, and the on-device Office checklist are in [docs/TESTING.md](docs/TESTING.md).

## Licensing

ShareLink's own code is under the MIT License. See [LICENSE](LICENSE).

libsmb2 and AMSMB2 are LGPL-2.1. They are dynamically linked as `AMSMB2.framework`. To use a modified libsmb2, rebuild ShareLink from this source against your modified AMSMB2 or libsmb2 (point the package dependency at your fork) and install that build on your device.

Notices, the full licence texts, and the corresponding-source archive are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## Privacy

ShareLink collects no data. Details are in [docs/privacy.md](docs/privacy.md).
