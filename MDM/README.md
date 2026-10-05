# ShareLink managed app configuration

ShareLink reads `com.apple.configuration.managed`. Every key is a flat string so it can be entered in consoles that do not support nested dictionaries. Values are parsed leniently: an integer may arrive as `445`, and a boolean may arrive as `true`, `yes`, `1`, or `on` (and the matching false forms). Whitespace around a value is ignored. Paths may use backslashes; leading and trailing slashes are removed.

An example dictionary is [example-managed-config.plist](example-managed-config.plist). It configures two shares (`files.example.com` / `Departments` / `Finance`, and `archive.example.com` / `Archive` with encryption required), sets `AllowUserServers` to false, and sets `SupportMessage`. Examples in this document use `files.example.com`, `archive.example.com`, `EXAMPLE`, and `jdoe`.

## Keys

Share 1 uses the names in the table. Shares 2 through 10 use the same names with a `ShareN.` prefix (`Share2.Host`, `Share3.Host`, … `Share10.Host`).

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

A share entry that is missing `Host` or `Share` is skipped. ShareLink records that as a configuration issue and reports it back (see Feedback). A share slot that has no keys at all is ignored.

`AllowUserServers` and `SupportMessage` apply to the whole app, not to one share. There is no `Share2.AllowUserServers` key.

[sharelink-appconfig.xml](sharelink-appconfig.xml) describes share 1, share 2, and the two global keys in the AppConfig specification format, with defaults of port 445, booleans false, and `AllowUserServers` true. Shares 3–10 are the same keys with a higher prefix. Add those in the console when you need them. The XML does not list them, because the specification file would otherwise repeat the same nine fields eight more times.

If the MDM sends a `Share2.*` key when share 2 has no host and share (for example because it deploys every default in the specification), ShareLink treats share 2 as present and reports it missing `Share2.Host` and `Share2.Share`. Leave share 2's keys unset unless both `Share2.Host` and `Share2.Share` are filled in.

## Miradore

1. Management → Applications → add ShareLink from the App Store (VPP/Apps and Books) as a managed app.
2. Under the app's deployment, open Managed app configuration and use **Add new** for each key/value.
3. For `Username`, use Miradore's user variable for the user name. Check Miradore's variable list in the console for the exact token.
4. Deploy.

The token syntax differs by console and is not written here. Copy it from Miradore's variable list rather than inventing one.

## What users see

1. Open ShareLink. Each configured share is listed under its display name with a lock badge. Managed shares cannot be edited or deleted in the app.
2. Tap a share that still needs a password. The sign-in sheet shows the display name, a read-only summary of the host, share, and path, the domain, and the username when `Username` was set. When `UsernameLocked` is true, the username cannot be changed. `SupportMessage` is shown on this screen.
3. Enter the password and sign in. ShareLink connects and lists the share root before it saves the password to the Keychain.
4. The share appears in the Files app under that display name: Files → Browse → the ShareLink location.
5. When `AllowUserServers` is false, Add Server is hidden and any server the user had added is removed.
6. When a managed share is removed from the configuration, its Files location disappears, along with that share's cached files, metadata, and saved password.

## Feedback

ShareLink writes `com.apple.feedback.managed` with:

| Key | Type | Meaning |
|---|---|---|
| `ConfiguredShares` | int | How many managed shares were accepted |
| `SignedInShares` | int | How many of those have saved credentials |
| `ConfigErrors` | string array | Issues from the last parse, such as a share missing its host |
| `AppVersion` | string | The installed ShareLink version |

## Other MDMs

Upload [sharelink-appconfig.xml](sharelink-appconfig.xml) where the console accepts an AppConfig specification. Where it only accepts key/value pairs, enter the same keys as in the table above. [example-managed-config.plist](example-managed-config.plist) is a complete two-share example you can use as a template. Replace the `example.com` hosts, the `EXAMPLE` domain, and `jdoe` before deploying it.
