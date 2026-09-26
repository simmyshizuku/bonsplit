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

    @Test("A drag over no destination shows the host's detached preview")
    func detachedPreviewComesFromHost() throws {
        let fixture = try makeFixture()
        let image = NSImage(size: NSSize(width: 10, height: 10))
        fixture.delegate.preview = TabDragDetachedPreview(
            image: image,
            size: NSSize(width: 30, height: 20)
        )

        let preview = try #require(
            fixture.source.detachedPreview(atScreenPoint: NSPoint(x: 5, y: 6))
        )

        #expect(preview.image === image)
        #expect(preview.size == NSSize(width: 30, height: 20))
        let request = try #require(fixture.delegate.previewRequests.first)
        #expect(request.tabId == fixture.tabId)
        #expect(request.point == NSPoint(x: 5, y: 6))
    }

    @Test("Without a host preview the tab keeps its own drag image")
    func noHostPreviewKeepsTabImage() throws {
        let fixture = try makeFixture()

        #expect(fixture.source.detachedPreview(atScreenPoint: .zero) == nil)
        #expect(fixture.delegate.previewRequests.count == 1)
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

    fileprivate final class RecordingDelegate: BonsplitDelegate {
        struct Report {
            let tabId: TabID
            let paneId: PaneID
            let point: NSPoint
        }

        var reports: [Report] = []
        var previewRequests: [Report] = []
        var preview: TabDragDetachedPreview?

        func splitTabBar(
            _ controller: BonsplitController,
            detachedPreviewFor context: TabDragDetachContext
        ) -> TabDragDetachedPreview? {
            previewRequests.append(Report(context))
            return preview
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didEndTabDragWithoutDrop context: TabDragDetachContext
        ) {
            reports.append(Report(context))
        }
    }
}

private extension TabDragUnplacedReleaseTests.RecordingDelegate.Report {
    init(_ context: TabDragDetachContext) {
        self.init(
            tabId: context.tab.id,
            paneId: context.sourcePaneId,
            point: context.screenPoint
        )
    }
}

@Suite("Dragging image resize animation")
struct DraggingImageResizeAnimationTests {
    @Test("The size eases from start to end")
    func sizeEasesBetweenEnds() {
        let from = NSSize(width: 100, height: 20)
        let to = NSSize(width: 300, height: 200)

        #expect(DraggingImageResizeAnimation.size(from: from, to: to, progress: 0) == from)
        #expect(DraggingImageResizeAnimation.size(from: from, to: to, progress: 1) == to)
        #expect(DraggingImageResizeAnimation.size(from: from, to: to, progress: 2) == to)
        let halfway = DraggingImageResizeAnimation.size(from: from, to: to, progress: 0.5)
        // Ease-out covers most of the distance in the first half.
        #expect(halfway.width == 275)
        #expect(halfway.height == 177.5)
    }

    @Test("Frames are centered on the pointer")
    func frameIsCenteredOnPointer() {
        let frame = DraggingImageResizeAnimation.frame(
            of: NSSize(width: 300, height: 200),
            centeredOn: NSPoint(x: 500, y: 400)
        )

        #expect(frame == NSRect(x: 350, y: 300, width: 300, height: 200))
    }
}
