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
