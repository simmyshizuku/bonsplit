import AppKit

/// Retained AppKit source whose terminal callback owns tab-drag cancellation.
@MainActor
final class TabDragSessionSource: NSObject, NSDraggingSource {
    private let generation: Int
    private let transfer: TabDragTransfer
    private let transferRegistration: TabDragTransferRegistration
    private let transferRegistry: TabDragTransferRegistry
    private weak var controller: SplitViewController?
    private var didFinish = false
    // Keep the source view owned until `endedAt`; AppKit owns the session and
    // retains this source while its native drag is active.
    // AppKit's drag manager may outlive the SwiftUI tab view that initiated the
    // drag; releasing either object during an accepted drop can strand the
    // WindowManager drag connection.
    private var sourceView: NSView?

    init(
        generation: Int,
        transfer: TabDragTransfer,
        transferRegistration: TabDragTransferRegistration,
        transferRegistry: TabDragTransferRegistry,
        controller: SplitViewController
    ) {
        self.generation = generation
        self.transfer = transfer
        self.transferRegistration = transferRegistration
        self.transferRegistry = transferRegistry
        self.controller = controller
        super.init()
    }

    /// Retains the source view until AppKit delivers this source's `endedAt` callback.
    func bind(sourceView: NSView) {
        guard !didFinish else { return }
        self.sourceView = sourceView
    }

    /// Completes a superseded source after a later native pointer boundary
    /// proves that AppKit has left this source's drag loop.
    func finishAfterNativeBoundary() {
        finishDrag()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        let isCancellation = Self.isCancellation(NSApp.currentEvent)
#if DEBUG
        dlog(
            "tab.dragEnded op=\(operation.rawValue) cancel=\(isCancellation ? 1 : 0) " +
            "event=\(NSApp.currentEvent.map { String($0.type.rawValue) } ?? "nil") " +
            "point=\(Int(screenPoint.x)),\(Int(screenPoint.y))"
        )
#endif
        finishDrag()
        // The system drag pasteboard advertises this session's transfer type
        // until another drag replaces it, which keeps host drop-capture
        // hit-testing armed forever and blocks the next tab drag from starting.
        transferRegistration.clearResidualCapability(from: session.draggingPasteboard)
        if operation.isEmpty, !isCancellation {
            reportUnplacedRelease(atScreenPoint: screenPoint)
        }
    }

    /// Reports a release that no destination accepted, after the source's
    /// terminal cleanup, so the host may relocate the tab (for example into a
    /// new window) without racing this drag's own state.
    func reportUnplacedRelease(atScreenPoint screenPoint: NSPoint) {
        controller?.tabDragDidEndWithoutDrop(transfer, atScreenPoint: screenPoint)
    }

    /// AppKit ends an Escape-cancelled drag with the same empty operation as
    /// a release over no destination; only the triggering event differs.
    static func isCancellation(_ event: NSEvent?) -> Bool {
        event?.type == .keyDown
    }

    func finishDrag() {
        guard !didFinish else { return }
        didFinish = true
        transferRegistry.end(transferRegistration)
        controller?.nativeTabDragSessionDidEnd(generation: generation)
        sourceView = nil
    }
}
