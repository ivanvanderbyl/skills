import Testing

@testable import PaneWindow

enum Pane: PathPane {
    case sidebar
    case list(String)
    case chat(String)
    case artifact(String)

    var depth: Int {
        switch self {
        case .sidebar: 0
        case .list: 1
        case .chat: 2
        case .artifact: 3
        }
    }
}

private let list = Pane.list("Code")
private let chat = Pane.chat("Saturday 5K")
private let artifact = Pane.artifact("race-day-plan")

private func window(_ panes: [Pane], showing trailing: Pane, capacity: Int) -> PaneWindow<Pane> {
    var window = PaneWindow(root: panes[0], capacity: 1)
    for pane in panes.dropFirst() { window.open(pane) }
    while window.trailing != trailing { window.back() }
    window.resize(to: capacity)
    return window
}

@Suite("Reference clips")
struct ReferenceClips {
    /// The four-event loop of the analysed clip.
    @Test func foldLoopKeepsTheTrailingPane() {
        var w = window([.sidebar, list, chat, artifact], showing: chat, capacity: 1)
        #expect(w.visible == [chat])
        w.resize(to: 2)
        #expect(w.visible == [list, chat])
        w.forward()
        #expect(w.visible == [chat, artifact])
        w.resize(to: 1)
        #expect(w.visible == [artifact])
        w.back()
        #expect(w.visible == [chat])
    }

    /// The "path of screens" clip: three panes, starting on the sidebar.
    @Test func pathOfScreens() {
        var w = window([.sidebar, chat, artifact], showing: .sidebar, capacity: 1)
        w.forward()
        #expect(w.visible == [chat])
        w.resize(to: 2)
        #expect(w.visible == [.sidebar, chat])
        w.forward()
        #expect(w.visible == [chat, artifact])
        w.resize(to: 1)
        #expect(w.visible == [artifact])
        w.back()
        w.back()
        #expect(w.visible == [.sidebar])
    }

    /// An artifact opened on the closed Duo sits next to the chat after unfolding.
    @Test func artifactOpenedClosedUnfoldsBesideTheChat() {
        var w = window([.sidebar, chat], showing: chat, capacity: 1)
        w.open(artifact)
        #expect(w.visible == [artifact])
        w.resize(to: 2)
        #expect(w.visible == [chat, artifact])
    }

    /// One button takes the artifact full screen and the same button brings it back.
    @Test func fullScreenIsAToggle() {
        var w = window([.sidebar, chat, artifact], showing: artifact, capacity: 2)
        w.toggleExpanded()
        #expect(w.visible == [artifact])
        w.toggleExpanded()
        #expect(w.visible == [chat, artifact])
    }

    /// Opening a list keeps the chat on the right; leaving the list restores the sidebar.
    @Test func listOpensBesideTheChatThatStays() {
        var w = window([.sidebar, chat], showing: chat, capacity: 2)
        w.open(list)
        #expect(w.visible == [list, chat])
        w.close(list)
        #expect(w.visible == [.sidebar, chat])
    }

    /// Opening the sidebar hides the file; closing the sidebar brings it back.
    @Test func sidebarHidesTheFileWithoutClosingIt() {
        var w = window([.sidebar, chat, artifact], showing: artifact, capacity: 2)
        w.back()
        #expect(w.visible == [.sidebar, chat])
        #expect(w.path == [.sidebar, chat, artifact])
        w.forward()
        #expect(w.visible == [chat, artifact])
    }

    /// The artifact's Close button returns to sidebar and chat.
    @Test func closingTheArtifactReturnsToSidebarAndChat() {
        var w = window([.sidebar, chat, artifact], showing: artifact, capacity: 2)
        w.close(artifact)
        #expect(w.visible == [.sidebar, chat])
        #expect(w.canGoForward == false)
    }
}

@Suite("Invariants")
struct Invariants {
    @Test func backStopsWhereTheWindowWouldStopBeingFull() {
        var w = window([.sidebar, list, chat], showing: chat, capacity: 2)
        w.back()
        #expect(w.visible == [.sidebar, list])
        #expect(w.canGoBack == false)
        w.back()
        #expect(w.visible == [.sidebar, list])
    }

    @Test func forwardStopsAtTheEndOfThePath() {
        var w = window([.sidebar, chat], showing: chat, capacity: 1)
        #expect(w.canGoForward == false)
        w.forward()
        #expect(w.visible == [chat])
    }

    @Test func unfoldingOnTheRootFillsTheWindowForward() {
        var w = window([.sidebar, chat, artifact], showing: .sidebar, capacity: 1)
        w.resize(to: 2)
        #expect(w.visible == [.sidebar, chat])
    }

    @Test func aPathShorterThanTheWindowShowsWhatItHas() {
        var w = PaneWindow(root: Pane.sidebar, capacity: 2)
        #expect(w.visible == [.sidebar])
        #expect(w.canExpand == false)
        w.toggleExpanded()
        #expect(w.isExpanded == false)
    }

    @Test func foldingLeavesFullScreenSoUnfoldingIsSideBySide() {
        var w = window([.sidebar, chat, artifact], showing: artifact, capacity: 2)
        w.toggleExpanded()
        w.resize(to: 1)
        w.resize(to: 2)
        #expect(w.visible == [chat, artifact])
    }

    @Test func pickingADifferentChatDropsTheOldChatsArtifact() {
        var w = window([.sidebar, list, chat, artifact], showing: artifact, capacity: 2)
        w.open(.chat("Race group names"))
        #expect(w.path == [.sidebar, list, .chat("Race group names")])
        #expect(w.visible == [list, .chat("Race group names")])
    }

    @Test func reopeningAPaneAlreadyOnThePathKeepsDeeperPanes() {
        var w = window([.sidebar, chat, artifact], showing: artifact, capacity: 1)
        w.open(chat)
        #expect(w.path == [.sidebar, chat, artifact])
        #expect(w.visible == [chat])
    }

    /// Tapping the row of a chat that is already on screen must not slide to its artifact.
    @Test func openingAPaneAlreadyInTheWindowChangesNothing() {
        let sideBySide = window([.sidebar, list, chat, artifact], showing: chat, capacity: 2)
        #expect(sideBySide.visible == [list, chat])
        for pane in [list, chat] {
            var w = sideBySide
            w.open(pane)
            #expect(w == sideBySide)
        }

        var fullScreen = window([.sidebar, chat, artifact], showing: artifact, capacity: 2)
        fullScreen.toggleExpanded()
        var w = fullScreen
        w.open(artifact)
        #expect(w == fullScreen)
    }

    /// Picking a chat from the list keeps the list beside it, even when the
    /// chat's artifact is still on the path.
    @Test func openingAPaneOutsideTheWindowSlidesTheLeastDistance() {
        var w = window([.sidebar, list, chat, artifact], showing: list, capacity: 2)
        #expect(w.visible == [.sidebar, list])
        w.open(chat)
        #expect(w.visible == [list, chat])
        #expect(w.path == [.sidebar, list, chat, artifact])

        w.forward()
        #expect(w.visible == [chat, artifact])
        w.open(list)
        #expect(w.visible == [list, chat])
    }

    @Test func openingAPaneHiddenByFullScreenBringsItBack() {
        var w = window([.sidebar, chat, artifact], showing: artifact, capacity: 2)
        w.toggleExpanded()
        w.open(chat)
        #expect(w.visible == [chat, artifact])
        #expect(w.isExpanded == false)
    }

    @Test func theRootCannotBeClosed() {
        var w = window([.sidebar, chat], showing: chat, capacity: 2)
        w.close(.sidebar)
        #expect(w.path == [.sidebar, chat])
    }

    @Test func closingAPaneBeyondTheWindowLeavesTheWindowAlone() {
        var w = window([.sidebar, chat, artifact], showing: .sidebar, capacity: 1)
        w.close(artifact)
        #expect(w.visible == [.sidebar])
        #expect(w.path == [.sidebar, chat])
    }

    /// Every reachable state keeps the window inside the path and full when it can be.
    @Test func everyEventSequenceKeepsTheWindowValid() {
        let events: [(String, (inout PaneWindow<Pane>) -> Void)] = [
            ("fold", { $0.resize(to: 1) }), ("unfold", { $0.resize(to: 2) }),
            ("forward", { $0.forward() }), ("back", { $0.back() }),
            ("openList", { $0.open(list) }), ("openChat", { $0.open(chat) }),
            ("openOtherChat", { $0.open(.chat("Pace group names")) }),
            ("openArtifact", { $0.open(artifact) }),
            ("closeList", { $0.close(list) }), ("closeArtifact", { $0.close(artifact) }),
            ("expand", { $0.toggleExpanded() }),
        ]
        var seen: Set<PaneWindow<Pane>> = []
        var frontier = [PaneWindow(root: Pane.sidebar, capacity: 1)]
        while let state = frontier.popLast() {
            guard seen.insert(state).inserted else { continue }
            let depths = state.path.map(\.depth)
            #expect(depths == depths.sorted() && Set(depths).count == depths.count)
            #expect(state.path.indices.contains(state.trailingIndex))
            #expect(state.trailingIndex >= min(state.capacity, state.path.count) - 1)
            #expect(state.visible.count == (state.isExpanded ? 1 : min(state.capacity, state.path.count)))
            #expect(!state.isExpanded || state.capacity > 1)
            for (_, apply) in events {
                var next = state
                apply(&next)
                frontier.append(next)
            }
        }
        #expect(seen.count > 20)
    }
}
