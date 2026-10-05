# Releasing ShareLink

## First TestFlight build checklist

1. `Config/Local.xcconfig` — copy `Config/Local.xcconfig.example` and set the Team ID.
2. App Store Connect app record.
3. API key in `.env`.
4. `./scripts/testflight.sh --internal-only`
5. Add internal testers.
6. Push the tag and create the GitHub prerelease with the third-party source tarball.

## One-time setup

1. Apple Developer account.
2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set the Team ID.
3. In App Store Connect, create the app record: name "ShareLink" (or an available variant), bundle ID `com.ajthom90.sharelink`, SKU `sharelink-ios`. The bundle ID and App Group are registered automatically on the first archive via `-allowProvisioningUpdates`; if not, register them in the developer portal: App ID `com.ajthom90.sharelink` + `.FileProvider`, both with App Groups capability → `group.com.ajthom90.sharelink`.
4. Create an App Store Connect API key (Users and Access → Integrations → Team Keys, App Manager role), save the `.p8` outside the repo, and fill `.env`.
5. In TestFlight, create an internal group and add testers.

## Each build

`./scripts/testflight.sh --internal-only`, then push the tag and create the GitHub prerelease with the third-party source tarball (the LGPL corresponding-source requirement).

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is set, so no questionnaire.

## Moving to App Store

Privacy policy URL (GitHub Pages `docs/privacy.md` or the raw GitHub URL), support URL (GitHub Issues), screenshots (iPhone 6.9", iPad 13"), App Privacy "Data Not Collected", Standard EULA (see spec §2.1), and price Free.
