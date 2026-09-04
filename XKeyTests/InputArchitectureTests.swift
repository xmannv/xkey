import XCTest

final class InputArchitectureTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    func testXKeyIMControllerUsesSharedRuntimeInsteadOfStandaloneTypingDecisions() throws {
        let controller = try source("XKeyIM/XKeyIMController.swift")

        XCTAssertFalse(controller.contains("VNEngine.EngineSettings("))
        XCTAssertFalse(controller.contains("XKeyIMSettings"))
        let unexpectedEngineAccesses = controller
            .components(separatedBy: .newlines)
            .filter { $0.contains("engine.") }
            .filter { !$0.contains("engine.smartSwitchManager") }
            .filter { !$0.contains("engine.logCallback") }
        XCTAssertEqual(unexpectedEngineAccesses, [])
    }

    func testTapControllerDoesNotClassifySmartSwitchAsMainAppOnly() throws {
        let controller = try source("XKeyIM/TapController.swift")

        let smartSwitchAppOnlyClaims = controller
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains("Smart Switch") }
            .filter {
                let line = $0.lowercased()
                return line.contains("app-only")
                    || (line.contains("only") && line.contains("xkey.app"))
            }
        XCTAssertEqual(smartSwitchAppOnlyClaims, [])
        XCTAssertTrue(controller.contains("source.onAppContext"))
    }

    func testXKeyIMExplainsAndRequestsEachEventTapPermission() throws {
        let tapController = try source("XKeyIM/TapController.swift")
        let inputController = try source("XKeyIM/XKeyIMController.swift")

        XCTAssertTrue(tapController.contains("eventPermissionStatus()"))
        XCTAssertTrue(inputController.contains("Cấp quyền Input Monitoring…"))
        XCTAssertTrue(inputController.contains("CGRequestListenEventAccess()"))
        XCTAssertTrue(inputController.contains("Privacy_ListenEvent"))
        XCTAssertTrue(inputController.contains("Cấp quyền Accessibility…"))
        XCTAssertTrue(inputController.contains("CGRequestPostEventAccess()"))
        XCTAssertTrue(inputController.contains("Privacy_Accessibility"))
        XCTAssertFalse(inputController.contains("chưa có quyền Trợ năng"))
    }

    func testEveryTapHostHandlesRuntimePermissionLoss() throws {
        let eventTapManager = try source("XKey/EventHandling/EventTapManager.swift")
        let appDelegate = try source("XKey/App/AppDelegate.swift")
        let tapController = try source("XKeyIM/TapController.swift")

        XCTAssertTrue(eventTapManager.contains("eventPermissionCheck"))
        XCTAssertTrue(eventTapManager.contains("onEventTapPermissionLost"))
        XCTAssertTrue(appDelegate.contains("eventTapManager?.onEventTapPermissionLost"))
        XCTAssertTrue(tapController.contains(
            "manager.eventPermissionCheck = { Self.hasEventPermission() }"
        ))
        XCTAssertTrue(tapController.contains("manager.onEventTapPermissionLost"))
    }

    func testSecureInputSystemQueryHasOneProductionOwner() throws {
        var matches: [String] = []

        for directory in ["Shared", "XKey", "XKeyIM"] {
            let directoryURL = repositoryRoot.appendingPathComponent(directory)
            let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "swift" else { continue }
                let fileSource = try String(contentsOf: fileURL, encoding: .utf8)
                let count = fileSource.components(separatedBy: "IsSecureEventInputEnabled()").count - 1
                matches.append(contentsOf: repeatElement(
                    fileURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""),
                    count: count
                ))
            }
        }

        XCTAssertEqual(matches, ["Shared/InputSession/SecureInputDetector.swift"])
    }

    func testOnlyTransportAdaptersImportTheirOSFrameworks() throws {
        XCTAssertTrue(try source("XKey/EventHandling/CGEventTransport.swift")
            .contains("import CoreGraphics"))
        XCTAssertTrue(try source("XKeyIM/IMKitTransport.swift")
            .contains("import InputMethodKit"))

        let inputSessionDirectory = repositoryRoot.appendingPathComponent("Shared/InputSession")
        let enumerator = FileManager.default.enumerator(
            at: inputSessionDirectory,
            includingPropertiesForKeys: nil
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let fileSource = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(fileSource.contains("import InputMethodKit"), fileURL.lastPathComponent)
            XCTAssertFalse(fileSource.contains("import CoreGraphics"), fileURL.lastPathComponent)
        }
    }

    func testAppDelegateDrainsMainTapBeforeHandingInputToXKeyIM() throws {
        let appDelegate = try source("XKey/App/AppDelegate.swift")
        let tapController = try source("XKeyIM/TapController.swift")

        XCTAssertTrue(appDelegate.contains("eventTapManager?.suspendAndDrainPendingInjection()"))
        XCTAssertFalse(appDelegate.contains("eventTapManager?.suspend()"))
        XCTAssertTrue(appDelegate.contains("acknowledgePendingRequest"))
        XCTAssertTrue(appDelegate.contains("managerBecameReady("))
        XCTAssertTrue(tapController.contains("beginRequest(requesterPID:"))
        XCTAssertTrue(tapController.contains("claimDecision(for:"))
        XCTAssertTrue(tapController.contains("blocksIMKitProcessingForHandoff"))
        XCTAssertTrue(tapController.contains("cancelRequest("))

        let observer = try XCTUnwrap(appDelegate.range(of: "setupSharedSettingsObserver()"))
        let tapSetup = try XCTUnwrap(appDelegate.range(of: "setupKeyboardHandling()"))
        XCTAssertLessThan(observer.lowerBound, tapSetup.lowerBound)
        let managerReady = try XCTUnwrap(appDelegate.range(of: "managerBecameReady("))
        let tapStart = try XCTUnwrap(appDelegate.range(of: "try manager.start()"))
        XCTAssertLessThan(managerReady.lowerBound, tapStart.lowerBound)
    }

    func testSharedSettingsObserverKeepsMainLanguageRuntimeInSyncAcrossHandoff() throws {
        let appDelegate = try source("XKey/App/AppDelegate.swift")
        let observerStart = try XCTUnwrap(
            appDelegate.range(of: "private func setupSharedSettingsObserver()")
        )
        let observerTail = appDelegate[observerStart.lowerBound...]
        let observerEnd = try XCTUnwrap(
            observerTail.range(of: "private func startSecureInputPolling()")
        )
        let observerBody = observerTail[..<observerEnd.lowerBound]

        XCTAssertTrue(observerBody.contains("mainSettingsChangeTracker?.update"))
        XCTAssertTrue(appDelegate.contains("case .restoreAfterXKeyIM:"))
        XCTAssertTrue(appDelegate.contains("case .applyVietnamese(let enabled):"))
        XCTAssertFalse(observerBody.contains(
            "viewModel.isVietnameseEnabled = SharedSettings.shared.vietnameseEnabled"
        ))

        let xkeyIMBranch = try XCTUnwrap(appDelegate.range(of: "if isXKeyIM {"))
        let branchTail = appDelegate[xkeyIMBranch.lowerBound...]
        let otherBranch = try XCTUnwrap(branchTail.range(of: "} else {"))
        let xkeyIMBody = branchTail[..<otherBranch.lowerBound]
        XCTAssertTrue(xkeyIMBody.contains("smartSwitchHandledBundleId = nil"))

        let inputSourceSetup = try XCTUnwrap(appDelegate.range(of: "setupInputSourceManager()"))
        let coldStartSync = try XCTUnwrap(
            appDelegate.range(of: "applyInitialMainSettingsState()")
        )
        XCTAssertLessThan(inputSourceSetup.lowerBound, coldStartSync.lowerBound)
    }

    func testEveryMainTapStartUsesTheOwnershipGate() throws {
        let appDelegate = try source("XKey/App/AppDelegate.swift")
        let statusBarViewModel = try source("XKey/UI/StatusBarViewModel.swift")
        let directStarts = appDelegate.components(separatedBy: "try manager.start()").count - 1

        XCTAssertEqual(directStarts, 1)
        XCTAssertTrue(appDelegate.contains("reconcileMainEventTapOwnership"))
        let permissionStart = try XCTUnwrap(appDelegate.range(of: "private func startPermissionMonitoring()"))
        let permissionTail = appDelegate[permissionStart.lowerBound...]
        let permissionEnd = try XCTUnwrap(permissionTail.range(of: "private func setupGlobalHotkey()"))
        let permissionBody = permissionTail[..<permissionEnd.lowerBound]
        XCTAssertTrue(permissionBody.contains("reconcileMainEventTapOwnership()"))
        XCTAssertFalse(permissionBody.contains("manager.start()"))
        XCTAssertFalse(statusBarViewModel.contains("eventTapManager?.restart()"))
        XCTAssertTrue(statusBarViewModel.contains("onRemoteDesktopTargetChanged?(enabled)"))
        XCTAssertTrue(appDelegate.contains("restartMainEventTapThroughOwnershipGate"))
        XCTAssertTrue(appDelegate.contains("mainTapOwnershipSlowRecheckDelay"))
        XCTAssertTrue(appDelegate.contains("try manager.start()\n                manager.resume()"))
        XCTAssertTrue(appDelegate.contains(
            "attempt: exhaustedFastRetries ? Self.mainTapOwnershipMaxRechecks : attempt + 1"
        ))
        XCTAssertTrue(appDelegate.contains("remoteDesktopTargetLifecycle.apply"))
        XCTAssertTrue(appDelegate.contains("applyRemoteDesktopTargetMode(preferences.isRemoteDesktopTarget)"))
        XCTAssertTrue(appDelegate.contains("applyRemoteDesktopTargetMode(SharedSettings.shared.isRemoteDesktopTarget)"))
    }
}
