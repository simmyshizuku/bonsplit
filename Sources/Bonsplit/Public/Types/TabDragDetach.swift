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

    public init(tab: Tab, sourcePaneId: PaneID, screenPoint: NSPoint) {
        self.tab = tab
        self.sourcePaneId = sourcePaneId
        self.screenPoint = screenPoint
    }
}

/// The image a tab drag shows while it is over no destination, typically a
/// thumbnail of the window the tab would become. Bonsplit centers it on the
/// pointer and animates the tab's own drag image into it.
public struct TabDragDetachedPreview {
    /// The preview image, drawn scaled to ``size``.
    public let image: NSImage
    /// The preview's on-screen size.
    public let size: NSSize

    public init(image: NSImage, size: NSSize) {
        self.image = image
        self.size = size
    }
}
