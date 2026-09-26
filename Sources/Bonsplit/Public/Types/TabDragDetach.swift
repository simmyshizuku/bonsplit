import AppKit

/// A tab drag that has left every destination, as reported to the host for
/// tearing the tab off into its own window.
public struct TabDragDetachContext: Sendable {
    /// The dragged tab.
    public let tab: Tab
    /// The pane that owned the tab when the drag began.
    public let sourcePaneId: PaneID
    /// The pointer location in screen coordinates.
    public let screenPoint: NSPoint
    /// Where the pointer would sit, measured from a pane's top-left corner,
    /// if the tab were that pane's first tab. A host places a torn-off
    /// window with this offset so the pointer lands on the tab it grabbed.
    public let pointerOffsetInPane: CGSize

    public init(tab: Tab, sourcePaneId: PaneID, screenPoint: NSPoint, pointerOffsetInPane: CGSize) {
        self.tab = tab
        self.sourcePaneId = sourcePaneId
        self.screenPoint = screenPoint
        self.pointerOffsetInPane = pointerOffsetInPane
    }
}

/// The image a tab drag shows while it is over no destination, typically a
/// thumbnail of the window the tab would become.
public struct TabDragDetachedPreview {
    /// The preview image, drawn scaled into ``frame``.
    public let image: NSImage
    /// The preview's frame in screen coordinates for the current pointer.
    public let frame: NSRect

    public init(image: NSImage, frame: NSRect) {
        self.image = image
        self.frame = frame
    }
}
