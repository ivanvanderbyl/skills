/// A pane that has a fixed place on the app's path of screens.
///
/// `depth` orders panes from general (0) to specific. Two panes of the same
/// kind, such as two different chats, share a depth.
public protocol PathPane: Hashable, Sendable {
    var depth: Int { get }
}

/// The Duo pattern: a window of adjacent panes over an ordered path of screens.
///
/// The window is anchored to its trailing, most specific pane. Folding and
/// unfolding change how many panes fit (`capacity`) and keep the trailing
/// pane, so the screen the user was on survives every pose change. The one
/// exception is a window too near the start of the path to fill backwards,
/// such as the root pane alone: it fills forward instead.
public struct PaneWindow<Pane: PathPane>: Hashable, Sendable {
    /// Screens from general to specific, with strictly increasing depth.
    public private(set) var path: [Pane]
    /// Index in `path` of the most specific visible pane.
    public private(set) var trailingIndex: Int
    /// How many panes fit side by side: 1 for compact width, 2 for regular.
    public private(set) var capacity: Int
    /// The trailing pane fills the window. Only possible when `capacity > 1`.
    public private(set) var isExpanded: Bool

    public init(root: Pane, capacity: Int = 1) {
        path = [root]
        trailingIndex = 0
        self.capacity = max(1, capacity)
        isExpanded = false
    }

    /// Index in `path` of the most general visible pane.
    public var leadingIndex: Int {
        isExpanded ? trailingIndex : max(0, trailingIndex - capacity + 1)
    }

    /// The panes on screen, leading edge first.
    public var visible: [Pane] { Array(path[leadingIndex...trailingIndex]) }

    public var trailing: Pane { path[trailingIndex] }

    public var canGoBack: Bool { trailingIndex > lowestTrailingIndex }
    public var canGoForward: Bool { trailingIndex < path.count - 1 }
    public var canExpand: Bool { capacity > 1 && path.count > 1 }

    /// The device folded, unfolded, rotated or entered a shared-screen size.
    /// The trailing pane stays; panes appear or disappear on the leading side.
    public mutating func resize(to newCapacity: Int) {
        capacity = max(1, newCapacity)
        trailingIndex = max(trailingIndex, lowestTrailingIndex)
        if capacity == 1 { isExpanded = false }
    }

    /// Slides the window one pane towards the specific end. The path is unchanged.
    public mutating func forward() {
        isExpanded = false
        trailingIndex = min(trailingIndex + 1, path.count - 1)
    }

    /// Slides the window one pane towards the general end. The path is
    /// unchanged, so the panes that slid out return on `forward()`.
    public mutating func back() {
        isExpanded = false
        trailingIndex = max(trailingIndex - 1, lowestTrailingIndex)
    }

    /// Puts `pane` on the path and slides the window the least distance that
    /// shows it, so the panes the user was looking at stay when they can.
    ///
    /// A pane already in the window changes nothing. A pane at a new depth is
    /// inserted and deeper panes stay. A pane that replaces a different pane
    /// of the same depth drops the deeper panes, because they belonged to the
    /// pane it replaced.
    public mutating func open(_ pane: Pane) {
        guard !visible.contains(pane) else { return }
        isExpanded = false
        let index: Int
        if let existing = path.firstIndex(where: { $0.depth == pane.depth }) {
            index = existing
            if path[existing] != pane {
                path[existing] = pane
                path.removeSubrange((existing + 1)...)
            }
        } else {
            index = path.firstIndex(where: { $0.depth > pane.depth }) ?? path.count
            path.insert(pane, at: index)
            // The trailing pane moved one place along the path; follow it.
            if index <= trailingIndex { trailingIndex += 1 }
        }
        // The pane is visible when the trailing index is in index...(index + capacity - 1).
        trailingIndex = min(max(trailingIndex, index), index + capacity - 1, path.count - 1)
    }

    /// Removes `pane` from the path. The root pane cannot be closed.
    public mutating func close(_ pane: Pane) {
        guard let index = path.firstIndex(of: pane), index > 0 else { return }
        isExpanded = false
        path.remove(at: index)
        if index <= trailingIndex { trailingIndex -= 1 }
        trailingIndex = min(max(trailingIndex, lowestTrailingIndex), path.count - 1)
    }

    /// Switches the trailing pane between full screen and side by side.
    public mutating func toggleExpanded() {
        guard canExpand else { return }
        isExpanded.toggle()
    }

    /// The window is full whenever the path is long enough to fill it.
    private var lowestTrailingIndex: Int { min(capacity, path.count) - 1 }
}
