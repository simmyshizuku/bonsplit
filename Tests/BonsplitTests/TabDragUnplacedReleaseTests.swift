import AppKit
@testable import Bonsplit
import Testing

@Suite("Unplaced tab drag release")
@MainActor
struct TabDragUnplacedReleaseTests {
    @Test("A release over no destination reports the tab, its pane, and the point")
    func unplacedReleaseReportsTab() throws {
        let fixture = try makeFixture()

        fixture.source.finishDrag()
        fixture.source.reportUnplacedRelease(atScreenPoint: NSPoint(x: 40, y: 900))

        let report = try #require(fixture.delegate.reports.first)
        #expect(fixture.delegate.reports.count == 1)
        #expect(report.tabId == fixture.tabId)
        #expect(report.paneId == fixture.paneId)
        #expect(report.point == NSPoint(x: 40, y: 900))
        #expect(fixture.controller.internalController.tabDragSession == nil)
    }

    @Test("A tab closed while its drag was in flight is not reported")
    func closedTabIsNotReported() throws {
        let fixture = try makeFixture()
        #expect(fixture.controller.closeTab(fixture.tabId))

        fixture.source.finishDrag()
        fixture.source.reportUnplacedRelease(atScreenPoint: .zero)

        #expect(fixture.delegate.reports.isEmpty)
    }

    @Test("Only a key event ends a drag as a cancellation")
    func cancellationIsKeyDriven() throws {
        let escape = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )
        let mouseUp = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )

        #expect(TabDragSessionSource.isCancellation(escape))
        #expect(!TabDragSessionSource.isCancellation(mouseUp))
        #expect(!TabDragSessionSource.isCancellation(nil))
    }

    private func makeFixture() throws -> Fixture {
        let registry = TabDragTransferRegistry()
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(
                allowTabReordering: true,
                allowCrossPaneTabMove: true,
                newTabPosition: .end
            ),
            tabDragTransferRegistry: registry
        )
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        let split = controller.internalController
        let pane = try #require(split.focusedPane)
        let tab = try #require(pane.selectedTab)
        let generation = split.beginTabDrag(tab, from: pane.id)
        let transfer = TabDragTransfer(tab: Tab(from: tab), sourcePaneId: pane.id)
        let registration = try #require(registry.register(transfer))
        let source = TabDragSessionSource(
            generation: generation,
            transfer: transfer,
            transferRegistration: registration,
            transferRegistry: registry,
            controller: split
        )
        return Fixture(
            controller: controller,
            delegate: delegate,
            source: source,
            tabId: TabID(id: tab.id),
            paneId: pane.id
        )
    }

    private struct Fixture {
        let controller: BonsplitController
        let delegate: RecordingDelegate
        let source: TabDragSessionSource
        let tabId: TabID
        let paneId: PaneID
    }

    private final class RecordingDelegate: BonsplitDelegate {
        struct Report {
            let tabId: TabID
            let paneId: PaneID
            let point: NSPoint
        }

        var reports: [Report] = []

        func splitTabBar(
            _ controller: BonsplitController,
            didEndTabDragWithoutDrop tab: Tab,
            fromPane pane: PaneID,
            atScreenPoint point: NSPoint
        ) {
            reports.append(Report(tabId: tab.id, paneId: pane, point: point))
        }
    }
}
