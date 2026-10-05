import XCTest

/// Drives ShareLink and Files against the Docker Samba share on 127.0.0.1:1445.
/// The app is launched with `-SLE2EManagedConfig` so the managed share exists even
/// when the test runner reinstalls ShareLink and wipes seeded defaults.
@MainActor
final class FilesEndToEndTests: XCTestCase {
    private let locationName = "Samba Test"
    private let password = "ShareLink-Test-1"
    /// Two taps would collapse the section again. The label and the disclosure
    /// are different hit targets, so each point is tried at most once.
    private var locationExpandTaps = 0
    /// The provider row in Edit Sidebar is the app name and its switch can
    /// already read as on while the domain's `userEnabled` flag is still false.
    /// One off/on flip is what makes Files apply the change.
    private var forcedProviderToggle = false
    private var providerRowTaps = 0

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSignInListsShareAndCreatesFolder() throws {
        addUIInterruptionMonitor(withDescription: "System dialogs") { alert in
            for label in ["Allow", "OK", "Continue", "Not Now"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["-SLE2EManagedConfig"]
        app.launch()

        let passwordField = app.secureTextFields["signin.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 20), "sign-in password field did not appear")
        let username = app.textFields["Username"]
        if username.exists {
            XCTAssertEqual(username.value as? String, "testuser", "managed config did not prefill the username")
        }
        attach(app.screenshot(), name: "01-sign-in-sheet")

        passwordField.tap()
        passwordField.typeText(password)
        let submit = app.buttons["signin.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "sign-in button")
        if !submit.isHittable {
            app.swipeUp()
        }
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: submit)
        waitForExpectations(timeout: 5)
        submit.tap()

        try waitForSignedIn(app)
        attach(app.screenshot(), name: "02-signed-in")

        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        dismissFilesChrome(files)
        attach(files.screenshot(), name: "03-files-launched")

        // A single domain is listed under the app name. Files only applies
        // NSFileProviderDomain.displayName once a second domain exists.
        let location = try waitForFilesLabel(locationName, alternate: "ShareLink", in: files, timeout: 60, insideLocation: false)
        attach(files.screenshot(), name: "04-location-visible")
        location.tap()

        // Files' accessibility label spells the extension dot as ", ".
        let hello = try waitForFilesLabel("hello.txt", alternate: "hello, txt", in: files, timeout: 60, insideLocation: true)
        attach(files.screenshot(), name: "05-hello-txt")
        _ = hello

        // Files creates the folder under its own default name ("untitled folder",
        // or a numbered variant). Typing a replacement into the inline rename
        // field does not reliably schedule a provider rename, so the test leaves
        // that name alone. The script checks the server for a new directory.
        let existingFolders = folderItemLabels(in: files)
        try createFolder(in: files)
        if let created = waitForNewFolderName(in: files, excluding: existingFolders, timeout: 15) {
            XCTContext.runActivity(named: "Created folder \(created)") { _ in }
            attach(XCTAttachment(string: created), name: "created-folder-name")
        } else {
            attach(XCTAttachment(string: "Files did not expose a new folder name. The script checks the server for a new directory."), name: "created-folder-name")
        }
        attach(files.screenshot(), name: "07-folder-created")
    }

    // MARK: - ShareLink

    private func waitForSignedIn(_ app: XCUIApplication) throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            dismissSystemAlerts(around: app)
            if let status = element(identifier: "server.status", in: app) {
                let value = status.value as? String ?? ""
                if status.label.localizedCaseInsensitiveContains("Signed in")
                    || value.localizedCaseInsensitiveContains("Signed in") {
                    return
                }
            }
            if app.staticTexts["Couldn't sign in. Check your username and password."].exists {
                attach(app.screenshot(), name: "sign-in-rejected")
                XCTFail("Samba rejected the test password")
                throw E2EError.failed("sign-in rejected")
            }
            if app.staticTexts["The server can't be reached. Check your network connection."].exists {
                attach(app.screenshot(), name: "sign-in-unreachable")
                XCTFail("Samba was unreachable from the simulator")
                throw E2EError.failed("server unreachable")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        attach(app.screenshot(), name: "sign-in-timeout")
        attachHierarchy("sign-in-timeout", app)
        XCTFail("server did not show signed-in status within 30s")
        throw E2EError.failed("signed-in timeout")
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let types: [XCUIElement.ElementType] = [.other, .cell, .button, .staticText, .image, .group]
        for type in types {
            let match = app.descendants(matching: type).matching(predicate).firstMatch
            if match.exists { return match }
        }
        return nil
    }

    private func dismissSystemAlerts(around app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [springboard, app] {
            for label in ["Allow", "OK"] {
                let button = host.alerts.buttons[label].firstMatch
                if button.exists && button.isHittable {
                    button.tap()
                    return
                }
            }
        }
        // A tap outside the form sheet dismisses sign-in. Stay on the password field
        // so an interruption monitor still has an event to deliver.
        let password = app.secureTextFields["signin.password"]
        if password.exists && password.isHittable {
            password.tap()
        }
    }

    // MARK: - Files

    /// iPad Files keeps locations in a sidebar that starts collapsed. New File Provider
    /// domains are registered with `userEnabled == false`, so they stay out of the
    /// sidebar until Edit Sidebar turns them on.
    private func waitForFilesLabel(_ label: String, alternate: String? = nil, in files: XCUIApplication, timeout: TimeInterval, insideLocation: Bool) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        while Date() < deadline {
            dismissFilesChrome(files)
            // A fresh domain can show "could not be displayed" once, with the
            // items already materialized. Try Again reloads the listing.
            if insideLocation, files.buttons["Try Again"].firstMatch.exists {
                _ = tapFirst(in: files, labels: ["Try Again"], types: [.button])
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                continue
            }
            // A disabled domain shows "To browse and add files, turn on …" with
            // a Turn On button. That screen can also contain the display name,
            // so confirm it before treating the name as the open location.
            if confirmTurnOn(files, timeout: 0) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                continue
            }
            if insideLocation {
                if !showingProviderLocation(files) {
                    revealLocation(named: locationName, in: files, attempt: attempt)
                    if !inSidebarEditMode(files) {
                        _ = tapFirst(in: files, labels: [locationName, "ShareLink"], types: [.button, .staticText, .cell, .other])
                    }
                }
            } else {
                revealLocation(named: label, in: files, attempt: attempt)
            }
            if let found = providerElement(files, label: label, alternate: alternate), !inSidebarEditMode(files), !turnOnButton(files).exists {
                return found
            }
            attempt += 1
            if !inSidebarEditMode(files) {
                if insideLocation {
                    pullToRefresh(files)
                } else if attempt.isMultiple(of: 4) {
                    scrollSidebar(files)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        attach(files.screenshot(), name: "timeout-\(label)")
        attachHierarchy("timeout-\(label)", files)
        attach(XCTAttachment(string: controlLabels(files)), name: "controls-\(label)")
        XCTFail("Timed out after \(Int(timeout))s waiting for \(label) in Files")
        throw E2EError.failed("missing \(label)")
    }

    private func revealLocation(named name: String, in files: XCUIApplication, attempt: Int) {
        selectBrowse(files)
        openSidebar(files)
        if filesElement(files, label: name) != nil, !inSidebarEditMode(files), !turnOnButton(files).exists {
            return
        }
        // Edit mode stays up until the location switch is flipped. Once that
        // flip has happened, stay out of edit mode and open the provider row.
        if inSidebarEditMode(files) || (!forcedProviderToggle && attempt.isMultiple(of: 3)) {
            enableLocation(named: name, in: files)
        }
        _ = confirmTurnOn(files, timeout: 0)
        let title = navigationTitle(files)
        if !inSidebarEditMode(files), filesElement(files, label: name) == nil,
           title != name, title != "ShareLink", providerRowTaps < 2,
           let row = sidebarRow(named: "ShareLink", in: files) {
            providerRowTaps += 1
            row.tap()
        }
    }

    private func selectBrowse(_ files: XCUIApplication) {
        let browse = files.buttons["Browse"].firstMatch
        guard browse.exists, browse.isHittable, !browse.isSelected else { return }
        browse.tap()
    }

    /// Sidebar landmarks that are not also the title of the On My iPad browser.
    private func sidebarIsOpen(_ files: XCUIApplication) -> Bool {
        for label in ["Locations", "iCloud Drive", "Recently Deleted", "Tags", "Edit Sidebar"] {
            for type in [XCUIElement.ElementType.staticText, .button, .cell, .other] {
                let match = files.descendants(matching: type)[label].firstMatch
                if match.exists && match.isHittable { return true }
            }
        }
        return false
    }

    private func openSidebar(_ files: XCUIApplication) {
        if sidebarIsOpen(files) { return }
        let toggle = files.buttons["ToggleSideBar"].firstMatch
        if toggle.exists && toggle.isHittable {
            let label = toggle.label.lowercased()
            if label.contains("hide") { return }
            toggle.tap()
        } else {
            tapFirst(in: files, labels: ["Toggle sidebar", "Show Sidebar"], types: [.button])
        }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !sidebarIsOpen(files) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// Turns the provider on from the sidebar's Edit control. iOS adds the domain
    /// disabled. Edit Sidebar lists the provider under the app name ("ShareLink"),
    /// and that switch can already be on while `userEnabled` is still false.
    /// Flipping it off and back on is the gesture that surfaces Turn On.
    private func enableLocation(named name: String, in files: XCUIApplication) {
        if forcedProviderToggle, !inSidebarEditMode(files) { return }
        if !inSidebarEditMode(files) {
            if !files.buttons["Edit Sidebar"].firstMatch.exists && !files.menuItems["Edit Sidebar"].firstMatch.exists {
                tapSidebarMore(files)
            }
            _ = tapFirst(in: files, labels: ["Edit Sidebar", "Edit"], types: [.menuItem, .button])
        }
        guard inSidebarEditMode(files) else { return }
        expandLocations(files)
        if let domainSwitch = locationSwitch(named: name, in: files) {
            if switchIsOff(domainSwitch) {
                _ = setSwitch(named: name, on: true, in: files)
            }
            _ = confirmTurnOn(files, timeout: 2)
            finishEditing(files)
            return
        }
        guard locationSwitch(named: "ShareLink", in: files) != nil else { return }
        if !forcedProviderToggle {
            forcedProviderToggle = true
            attach(files.screenshot(), name: "sidebar-before-toggle")
            _ = setSwitch(named: "ShareLink", on: false, in: files)
            _ = confirmIfPresent(files, labels: ["Turn Off", "Remove", "Remove from Sidebar"], timeout: 1)
            _ = setSwitch(named: "ShareLink", on: true, in: files)
            _ = confirmTurnOn(files, timeout: 3)
            attach(files.screenshot(), name: "sidebar-after-toggle")
        }
        finishEditing(files)
    }

    private func finishEditing(_ files: XCUIApplication) {
        let done = files.buttons["Done"].firstMatch
        if done.exists, done.isHittable, done.isEnabled, done.frame.minX < 100 {
            done.tap()
        }
    }

    private func turnOnButton(_ files: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label == 'Turn On' OR label BEGINSWITH 'Turn On'")
        let alert = files.alerts.buttons.matching(predicate).firstMatch
        if alert.exists { return alert }
        let sheet = files.sheets.buttons.matching(predicate).firstMatch
        if sheet.exists { return sheet }
        return files.buttons.matching(predicate).firstMatch
    }

    @discardableResult
    private func confirmTurnOn(_ files: XCUIApplication, timeout: TimeInterval) -> Bool {
        confirmIfPresent(files, labels: ["Turn On"], timeout: timeout)
    }

    @discardableResult
    private func confirmIfPresent(_ files: XCUIApplication, labels: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        repeat {
            for label in labels {
                let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label)
                for query in [files.alerts.buttons, files.sheets.buttons, files.buttons] {
                    let button = query.matching(predicate).firstMatch
                    if button.exists, button.isHittable, button.isEnabled {
                        button.tap()
                        return true
                    }
                }
            }
            if timeout < 0.05 { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }

    /// Drives the Edit Sidebar switch for `name` to `on`. Re-queries after each
    /// tap; a coordinate tap covers a switch whose first hit does not register.
    private func setSwitch(named name: String, on: Bool, in files: XCUIApplication) -> Bool {
        let wantOff = !on
        for _ in 0..<2 {
            guard let toggle = locationSwitch(named: name, in: files), toggle.isHittable else { return false }
            if switchIsOff(toggle) == wantOff { return true }
            toggle.tap()
            let deadline = Date().addingTimeInterval(1.5)
            while Date() < deadline {
                if let current = locationSwitch(named: name, in: files), switchIsOff(current) == wantOff {
                    return true
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            if let toggle = locationSwitch(named: name, in: files), toggle.exists {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
            }
        }
        if let toggle = locationSwitch(named: name, in: files) {
            return switchIsOff(toggle) == wantOff
        }
        return false
    }

    private func inSidebarEditMode(_ files: XCUIApplication) -> Bool {
        let done = files.buttons["Done"].firstMatch
        return done.exists && done.isHittable && done.frame.minX < 100
    }

    /// Edit Sidebar starts with Locations collapsed. XCUITest exposes the header as
    /// a static text; a tap on the label does not run "Expand content". The
    /// disclosure is the row's trailing edge. A second tap collapses it, so each
    /// point is used once.
    private func expandLocations(_ files: XCUIApplication) {
        if locationsSectionIsExpanded(files) || files.switches.count > 0 { return }
        guard locationExpandTaps < 2 else { return }
        let before = files.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item'")).count
        let text = files.staticTexts["Locations"].firstMatch
        guard text.exists, text.isHittable else { return }
        locationExpandTaps += 1
        // Trailing edge is the disclosure. The center is the fallback if that misses.
        let dx: CGFloat = locationExpandTaps == 1 ? 0.92 : 0.5
        text.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let after = files.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item'")).count
            if after > before || files.switches.count > 0 || locationsSectionIsExpanded(files) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func locationsSectionIsExpanded(_ files: XCUIApplication) -> Bool {
        for label in ["iCloud Drive", "On My iPad", locationName, "ShareLink", "Recently Deleted"] {
            let item = files.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item' AND label == %@", label)
            ).firstMatch
            if item.exists && item.isHittable { return true }
        }
        return false
    }

    private func tapSidebarMore(_ files: XCUIApplication) {
        var best: XCUIElement?
        var bestX = CGFloat.greatestFiniteMagnitude
        for button in files.buttons.allElementsBoundByIndex where button.exists && button.isHittable {
            let label = button.label
            let identifier = button.identifier.lowercased()
            let isMore = label == "More" || label == "More…" || label == "More..." || label.hasPrefix("More")
                || identifier.contains("ellipsis") || identifier.contains("sidebar.more")
            guard isMore else { continue }
            if button.frame.minX < bestX {
                bestX = button.frame.minX
                best = button
            }
        }
        best?.tap()
    }

    private func switchIsOff(_ toggle: XCUIElement) -> Bool {
        let value = toggle.value
        if let number = value as? NSNumber { return number.intValue == 0 }
        if let string = value as? String {
            return string == "0" || string.caseInsensitiveCompare("off") == .orderedSame
        }
        return false
    }

    /// The switch is a child of the sidebar cell (`DOC.sidebar.item.<name>`),
    /// with an empty label. Match the cell, then a switch on that row.
    private func locationSwitch(named name: String, in files: XCUIApplication) -> XCUIElement? {
        let ident = "DOC.sidebar.item.\(name)"
        let cell = files.cells.matching(NSPredicate(format: "identifier == %@", ident)).firstMatch
        if cell.exists {
            let nested = cell.switches.firstMatch
            if nested.exists { return nested }
            for toggle in files.switches.allElementsBoundByIndex where toggle.exists {
                if abs(toggle.frame.midY - cell.frame.midY) < 36 { return toggle }
            }
        }
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, name + ",")
        let named = files.switches.matching(predicate).firstMatch
        if named.exists { return named }
        return nil
    }

    /// A sidebar row, not the navigation title that repeats the same label.
    private func sidebarRow(named name: String, in files: XCUIApplication) -> XCUIElement? {
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, name + ",")
        let types: [XCUIElement.ElementType] = [.button, .cell, .staticText, .other]
        for type in types {
            let matches = files.descendants(matching: type).matching(predicate)
            let count = min(matches.count, 8)
            for index in 0..<count {
                let match = matches.element(boundBy: index)
                guard match.exists, match.isHittable else { continue }
                if match.frame.midX < 420, match.frame.width < 500 { return match }
            }
        }
        return nil
    }

    /// Files titles a single-domain provider with the app name.
    private func showingProviderLocation(_ files: XCUIApplication) -> Bool {
        let title = navigationTitle(files)
        return title == locationName || title == "ShareLink"
    }

    private func providerElement(_ files: XCUIApplication, label: String, alternate: String?) -> XCUIElement? {
        if let found = filesElement(files, label: label) { return found }
        if let alternate, let found = filesElement(files, label: alternate) { return found }
        return nil
    }

    private func navigationTitle(_ files: XCUIApplication) -> String {
        let bar = files.navigationBars.firstMatch
        guard bar.exists else { return "" }
        let title = bar.staticTexts.firstMatch
        return title.exists ? title.label : ""
    }

    private func scrollSidebar(_ files: XCUIApplication) {
        // Swiping the Locations header collapses that section. Scroll a tag row instead.
        guard sidebarIsOpen(files), !inSidebarEditMode(files) else { return }
        let anchor = files.buttons["Important"].firstMatch
        if anchor.exists && anchor.isHittable {
            anchor.swipeUp()
            return
        }
        let sidebar = files.collectionViews["Sidebar"].firstMatch
        if sidebar.exists && sidebar.isHittable {
            sidebar.swipeUp()
        }
    }

    private func filesElement(_ files: XCUIApplication, label: String) -> XCUIElement? {
        if let row = sidebarRow(named: label, in: files) { return row }
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ",")
        let types: [XCUIElement.ElementType] = [.button, .staticText, .cell, .other, .radioButton]
        for type in types {
            let match = files.descendants(matching: type).matching(predicate).firstMatch
            if match.exists && match.isHittable { return match }
        }
        // A location row can contain a switch that must be turned on before the name is hittable.
        let cell = files.cells.containing(predicate).firstMatch
        if cell.exists {
            let toggle = cell.switches.firstMatch
            if toggle.exists, (toggle.value as? String) == "0" || (toggle.value as? String) == "Off" {
                toggle.tap()
            }
            if cell.isHittable { return cell }
        }
        return nil
    }

    @discardableResult
    private func tapFirst(in app: XCUIApplication, labels: [String], types: [XCUIElement.ElementType]) -> Bool {
        for label in labels {
            for type in types {
                let match = app.descendants(matching: type)[label].firstMatch
                if match.exists && match.isHittable {
                    match.tap()
                    return true
                }
            }
        }
        return false
    }

    private func pullToRefresh(_ files: XCUIApplication) {
        for query in [files.collectionViews, files.tables, files.scrollViews] {
            let view = query.firstMatch
            if view.exists && view.isHittable {
                view.swipeDown()
                return
            }
        }
    }

    private func dismissFilesChrome(_ files: XCUIApplication) {
        let labels = ["Continue", "Not Now", "Skip", "Close", "Got It", "Allow"]
        for _ in 0..<4 {
            var dismissed = false
            for label in labels {
                let button = files.buttons[label].firstMatch
                if button.exists && button.isHittable {
                    button.tap()
                    dismissed = true
                    break
                }
            }
            if !dismissed { return }
        }
    }

    private func createFolder(in files: XCUIApplication) throws {
        let labels = ["New Folder", "Create Folder"]
        if !tapFirst(in: files, labels: labels, types: [.button, .menuItem]) {
            let opened = tapFirst(
                in: files,
                labels: ["More…", "More...", "More", "More Actions", "Actions"],
                types: [.button, .menuItem]
            )
            if !opened {
                let overflow = files.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More'")).firstMatch
                if overflow.exists && overflow.isHittable {
                    overflow.tap()
                }
            }
            var command: XCUIElement?
            for label in labels {
                let item = files.menuItems[label].firstMatch
                if item.exists {
                    command = item
                    break
                }
                let button = files.buttons[label].firstMatch
                if button.exists {
                    command = button
                    break
                }
            }
            guard let command, command.waitForExistence(timeout: 5), command.isHittable else {
                attach(files.screenshot(), name: "no-new-folder")
                attachHierarchy("no-new-folder", files)
                attach(XCTAttachment(string: controlLabels(files)), name: "controls-new-folder")
                XCTFail("New Folder command was not available")
                throw E2EError.failed("no new folder")
            }
            command.tap()
        }

        commitDefaultFolderName(in: files)
    }

    /// Leaves Files' default name in the field. Return commits it; a tap outside
    /// the editor does the same when Return leaves the field up. The text is not
    /// replaced: a typed name does not reliably become a provider rename.
    private func commitDefaultFolderName(in files: XCUIApplication) {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if confirmCreateDialog(files) { return }
            let rename = files.textViews["DOC.inlineRenameField"].firstMatch
            if rename.exists {
                attach(files.screenshot(), name: "06-default-folder-name")
                if rename.isHittable { rename.tap() }
                if files.keyboards.firstMatch.waitForExistence(timeout: 3) {
                    rename.typeText(XCUIKeyboardKey.return.rawValue)
                    let gone = Date().addingTimeInterval(3)
                    while Date() < gone, files.textViews["DOC.inlineRenameField"].firstMatch.exists {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    }
                }
                if files.textViews["DOC.inlineRenameField"].firstMatch.exists {
                    tapAwayFromRename(files)
                }
                return
            }
            for query in [files.textFields, files.textViews] {
                for field in query.allElementsBoundByIndex where field.exists {
                    let value = (field.value as? String) ?? ""
                    if value.localizedCaseInsensitiveContains("untitled") {
                        attach(files.screenshot(), name: "06-default-folder-name")
                        if field.isHittable { field.tap() }
                        field.typeText(XCUIKeyboardKey.return.rawValue)
                        return
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        // Some Files versions create the folder without showing an editor.
        attach(files.screenshot(), name: "06-default-folder-name")
    }

    private func confirmCreateDialog(_ files: XCUIApplication) -> Bool {
        let dialog = files.alerts.firstMatch.exists || files.sheets.firstMatch.exists
        guard dialog else { return false }
        for label in ["Create Folder", "Create", "Add", "Save", "Done", "OK"] {
            for query in [files.alerts.buttons, files.sheets.buttons] {
                let button = query[label].firstMatch
                if button.exists, button.isHittable, button.isEnabled {
                    attach(files.screenshot(), name: "06-default-folder-name")
                    button.tap()
                    return true
                }
            }
        }
        return false
    }

    private func tapAwayFromRename(_ files: XCUIApplication) {
        let title = files.navigationBars.firstMatch
        if title.exists, title.isHittable {
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        files.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.2)).tap()
    }

    /// Item rows are labeled "name, Folder". Sidebar controls are not.
    private func folderItemLabels(in files: XCUIApplication) -> Set<String> {
        var labels = Set<String>()
        for query in [files.cells, files.buttons] {
            for element in query.allElementsBoundByIndex where element.exists {
                let label = element.label
                guard label.range(of: ", Folder", options: [.caseInsensitive, .backwards]) != nil else { continue }
                labels.insert(label)
            }
        }
        return labels
    }

    private func waitForNewFolderName(in files: XCUIApplication, excluding existing: Set<String>, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fresh = folderItemLabels(in: files).subtracting(existing)
            if let label = fresh.sorted().first {
                return folderDisplayName(label)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        return nil
    }

    private func folderDisplayName(_ label: String) -> String {
        if let range = label.range(of: ", Folder", options: [.caseInsensitive, .backwards]) {
            return String(label[..<range.lowerBound])
        }
        return label
    }

    // MARK: - Attachments

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ attachment: XCTAttachment, name: String) {
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachHierarchy(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func controlLabels(_ app: XCUIApplication) -> String {
        var lines: [String] = []
        for element in app.buttons.allElementsBoundByIndex {
            lines.append("button \(element.identifier) | \(element.label)")
        }
        for element in app.switches.allElementsBoundByIndex {
            lines.append("switch \(element.identifier) | \(element.label) | \(element.value ?? "")")
        }
        for element in app.menuItems.allElementsBoundByIndex {
            lines.append("menu \(element.identifier) | \(element.label)")
        }
        for element in app.staticTexts.allElementsBoundByIndex where element.label.count < 80 {
            lines.append("text \(element.label)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct E2EError: Error, CustomStringConvertible {
    var description: String
    static func failed(_ message: String) -> E2EError { E2EError(description: message) }
}
