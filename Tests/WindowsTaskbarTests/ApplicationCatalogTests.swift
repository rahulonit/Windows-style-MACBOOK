import Foundation
import CoreGraphics
import Testing
@testable import WindowsTaskbar

@Test("Default pinned applications have unique bundle identifiers")
func defaultCatalogHasUniqueBundleIdentifiers() {
    let applications = ApplicationCatalog.defaultPinnedApps()
    let identifiers = applications.map(\.bundleIdentifier)
    #expect(Set(identifiers).count == identifiers.count)
}

@Test("Taskbar icon size is clamped to its supported range")
@MainActor
func taskbarIconSizeIsClamped() {
    #expect(
        PreferencesService.clampTaskbarIconSize(10)
            == PreferencesService.minimumTaskbarIconSize
    )
    #expect(PreferencesService.clampTaskbarIconSize(36.5) == 36.5)
    #expect(
        PreferencesService.clampTaskbarIconSize(80)
            == PreferencesService.maximumTaskbarIconSize
    )
    #expect(
        PreferencesService.clampTaskbarIconSize(.nan)
            == PreferencesService.defaultTaskbarIconSize
    )
}

@Test("Taskbar geometry scales proportionally with icon size")
func taskbarGeometryScalesProportionally() {
    let small: CGFloat = 26
    let large: CGFloat = 56
    let scale = large / small

    #expect(abs(TaskbarTheme.height(for: large) / TaskbarTheme.height(for: small) - scale) < 0.0001)
    #expect(abs(TaskbarTheme.buttonSize(for: large) / TaskbarTheme.buttonSize(for: small) - scale) < 0.0001)
    #expect(abs(TaskbarTheme.buttonSpacing(for: large) / TaskbarTheme.buttonSpacing(for: small) - scale) < 0.0001)
    #expect(TaskbarTheme.systemTrayIconSize == 20)
}

@Test("Full-screen geometry is detected without treating menu-bar-maximized windows as full screen")
func fullScreenGeometryDetectionIsTolerant() {
    let displayID: CGDirectDisplayID = 1
    let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)

    #expect(FullScreenMonitor.displayIDsFilled(
        by: [CGRect(x: 0, y: 0, width: 1798, height: 1168)],
        displayFrames: [(displayID, display)]
    ) == Set([displayID]))
    #expect(FullScreenMonitor.displayIDsFilled(
        by: [CGRect(x: 0, y: 0, width: 1800, height: 1120)],
        displayFrames: [(displayID, display)]
    ) == Set([displayID]))
    #expect(FullScreenMonitor.displayIDsFilled(
        by: [CGRect(x: 0, y: 39, width: 1800, height: 1130)],
        displayFrames: [(displayID, display)]
    ).isEmpty)
}

@Test("Full-screen Spaces are selected independently by display")
func fullScreenSpacesAreSelectedPerDisplay() {
    let spaces: [[String: Any]] = [
        [
            "Display Identifier": "DISPLAY-A",
            "Current Space": ["type": 0]
        ],
        [
            "Display Identifier": "DISPLAY-B",
            "Current Space": ["type": 4]
        ]
    ]

    #expect(FullScreenMonitor.fullScreenDisplayIdentifiers(in: spaces) == ["DISPLAY-B"])
}

@Test("Calendar grid always contains six correctly aligned weeks")
func calendarGridIsAligned() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let april = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
    let days = CalendarMonthGrid.days(for: april, calendar: calendar)

    #expect(days.count == 42)
    #expect(days.filter(\.isInDisplayedMonth).count == 30)
    #expect(calendar.component(.month, from: days[0].date) == 3)
    #expect(calendar.component(.day, from: days[0].date) == 29)
    #expect(calendar.component(.month, from: days[41].date) == 5)
    #expect(calendar.component(.day, from: days[41].date) == 9)
}

@Test("Taskbar layout reserves the measured width of the larger edge")
func taskbarLayoutUsesMeasuredEdgeWidths() {
    let layout = TaskbarLayoutPolicy.calculate(
        screenWidth: 1_000,
        appCount: 10,
        iconSize: 36,
        leadingRegionWidth: 50,
        trailingRegionWidth: 300,
        horizontalPadding: 8
    )

    #expect(layout.visibleAppCount == 3)
    #expect(layout.overflowCount == 7)
}

@Test("Application catalogue hides background and internal helper tools")
func applicationCatalogFiltersInternalTools() {
    #expect(ApplicationCatalog.isUserFacingApplication(
        displayName: "Example App",
        infoDictionary: [:]
    ))
    #expect(!ApplicationCatalog.isUserFacingApplication(
        displayName: "Creative Cloud Helper",
        infoDictionary: [:]
    ))
    #expect(!ApplicationCatalog.isUserFacingApplication(
        displayName: "Example App",
        infoDictionary: ["LSUIElement": true]
    ))
    #expect(!ApplicationCatalog.isUserFacingApplication(
        displayName: "Product Uninstaller",
        infoDictionary: [:]
    ))
}

@Test("Flyout sizes respond to content and available screen space")
func flyoutSizesRespondToContent() {
    let compact = FlyoutLayoutPolicy.preferredSize(
        for: .network,
        context: FlyoutLayoutContext(
            availableSize: CGSize(width: 1_200, height: 800),
            networkCount: 0,
            hasNetworkError: true
        )
    )
    let populated = FlyoutLayoutPolicy.preferredSize(
        for: .network,
        context: FlyoutLayoutContext(
            availableSize: CGSize(width: 1_200, height: 800),
            networkCount: 8,
            hasConnectedNetwork: true
        )
    )
    let constrained = FlyoutLayoutPolicy.preferredSize(
        for: .calendar,
        context: FlyoutLayoutContext(
            availableSize: CGSize(width: 340, height: 360)
        )
    )

    #expect(compact.height == 220)
    #expect(populated.height > compact.height)
    #expect(constrained == CGSize(width: 340, height: 360))
}

@Test("Repeated system notifications are coalesced but app events are not")
@MainActor
func repeatedNotificationsAreCoalesced() {
    let now = Date()
    let existing = TaskbarNotification(
        title: "Bluetooth connected",
        message: "Keyboard",
        symbolName: "antenna.radiowaves.left.and.right",
        category: .bluetooth,
        date: now.addingTimeInterval(-30)
    )

    #expect(TaskbarNotificationService.coalescingIndex(
        in: [existing],
        title: existing.title,
        message: existing.message,
        category: .bluetooth,
        now: now,
        interval: 300
    ) == 0)
    #expect(TaskbarNotificationService.coalescingIndex(
        in: [existing],
        title: "Application started",
        message: "Keyboard",
        category: .application,
        now: now,
        interval: 300
    ) == nil)
}
