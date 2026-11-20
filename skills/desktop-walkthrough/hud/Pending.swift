// Delivery progress of the HUD: after the user presses a button (an answer, a feedback button, stop)
// or sends a message, the bar shows that the input is on its way, that the session took it, and it
// goes away once the agent has visibly reacted. Methods of the HUD class; stored state is in HUD.swift.
import AppKit
import QuartzCore

/// Written by the bridge mod after it handed a HUD message or a stop to the session: `{"kind", "at"}`.
let bridgeAckPath = "\(bridgeDir)/ack"
/// Rewritten by the bridge mod at every tool call of the owning session: the agent is doing something.
let toolAtPath = "\(bridgeDir)/tool-at"

/// An input the user gave on the HUD that the session has not visibly acted on yet.
///
/// Why it exists: between a press and the agent's reaction there are seconds in which nothing on
/// screen changes (the session is polled, a turn starts, the model thinks), and the user could not
/// tell whether the press had registered. Created by {@link HUD.notePending}; advanced and removed
/// by {@link HUD.updatePending}.
struct PendingInput {
    /// How the input travels to the session.
    enum Route {
        /// An answer the waiting `dw ask` / `dw wait-user` process picks up (it polls the answer file).
        case answer
        /// A line in the bridge's inbox: feedback buttons, the message box, an answer nobody waited for.
        case message
        /// The stop switch and the bridge's control file.
        case stop
    }
    let label: String
    let route: Route
    let at: Date
    /// When the session took the input (nil = still on its way).
    var delivered: Date?
    /// True once a turn was seen running after the delivery: its end then counts as the reaction.
    var sawBusy = false
    /// When the agent reacted (nil = not yet); the bar fades out from then.
    var done: Date?
}

extension HUD {
    // MARK: delivery progress

    /// Start showing that an input is on its way. Called by every control whose press goes to the session.
    ///
    /// @param label - The words on the pressed control (shown back to the user).
    /// @param route - How it travels (decides what counts as "arrived").
    func notePending(_ label: String, route: PendingInput.Route) {
        pendingInput = PendingInput(label: label, route: route, at: Date())
        if pendingBar.superlayer == nil {
            pendingBar.anchorPoint = .zero
            pendingBar.zPosition = 10
            box.layer?.addSublayer(pendingBar)
        }
        pendingBar.removeAllAnimations()
        pendingBar.opacity = 1
        updatePending()
        refresh()
    }

    /// Status line while an input is on its way or waits for the agent's reaction, with the symbol
    /// that goes before it (nil = nothing pending, or a stop: the stopped bar says it all).
    func pendingStatus() -> (symbol: String?, tint: NSColor, text: String)? {
        guard let pending = pendingInput, pending.done == nil, pending.route != .stop else { return nil }
        if pending.delivered != nil {
            return ("tray.and.arrow.down.fill", .labelColor, "「\(pending.label)」が Claude Code に届きました。応答を待っています…")
        }
        // Long on its way: the session is probably busy with something that cannot be interrupted
        if Date().timeIntervalSince(pending.at) > 20 {
            return ("exclamationmark.triangle.fill", .systemOrange,
                    "「\(pending.label)」がまだ届いていません（セッションが別の処理中かもしれません。チャットも確認してください）")
        }
        return ("paperplane.fill", .labelColor, "「\(pending.label)」を送信中…")
    }

    /// Advance the delivery progress: has the session taken the input, has the agent reacted, how far
    /// is the bar. Called about thirty times a second; returns at once when nothing is pending.
    func updatePending() {
        guard var pending = pendingInput else { return }
        let now = Date()
        /// True when a file was written after the press.
        func written(_ path: String) -> Bool { mtime(path).map { $0 > pending.at } ?? false }
        let stageBefore = (pending.delivered != nil, pending.done != nil)

        if pending.delivered == nil {
            let taken: Bool
            switch pending.route {
            // The waiting process deletes the answer file when it has read it
            case .answer: taken = !exists(askAnswerPath)
            // The bridge acknowledges; one loaded before that existed still rewrites the feed for each HUD message
            case .message: taken = written(bridgeAckPath) || written(feedPath)
            case .stop: taken = written(bridgeAckPath) || written(feedPath) || modBusy == false
            }
            if taken { pending.delivered = now }
        }
        if let delivered = pending.delivered, pending.done == nil {
            if modBusy == true { pending.sawBusy = true }
            let reacted: Bool
            switch pending.route {
            // A stop is done when the turn is over (or was never running)
            case .stop: reacted = modBusy != true
            // The agent called a tool or narrated, or its turn ended after answering in the chat
            default:
                reacted = written(toolAtPath) || written(statusPath) || written(actionStampPath) || written(narrationStampPath)
                    || (pending.sawBusy && modBusy == false)
                    || (modBusy == nil && now.timeIntervalSince(delivered) > 3)
            }
            if reacted { pending.done = now }
        }
        // Nothing came of it for two minutes: stop showing it
        if pending.done == nil, now.timeIntervalSince(pending.at) > 120 { pending.done = now }

        // The bar creeps while waiting (toward 60% on the way, toward 95% once taken) and fills at the reaction
        let width = box.bounds.width
        var progress: CGFloat
        if pending.done != nil {
            progress = 1
        } else if let delivered = pending.delivered {
            progress = 0.6 + 0.35 * (1 - CGFloat(exp(-now.timeIntervalSince(delivered) / 3.0)))
        } else {
            progress = 0.6 * (1 - CGFloat(exp(-now.timeIntervalSince(pending.at) / 1.2)))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pendingBar.frame = CGRect(x: 0, y: 0, width: width * progress, height: 4)
        let late = pending.delivered == nil && now.timeIntervalSince(pending.at) > 20
        // One colour for the way there and for the wait (the line's symbol and words tell the stage);
        // the explainer's green means the explainer
        pendingBar.backgroundColor = (late ? NSColor.systemOrange : primaryFill).hudCG
        CATransaction.commit()

        if let done = pending.done {
            // Full for a moment, then gone
            let since = now.timeIntervalSince(done)
            pendingBar.opacity = Float(max(0, 1 - max(0, since - 0.25) / 0.45))
            if since > 0.7 {
                pendingInput = nil
                pendingBar.removeFromSuperlayer()
                refresh()
                return
            }
        }
        pendingInput = pending
        // The status text follows each stage as it is reached, not at the next slow tick
        if stageBefore != (pending.delivered != nil, pending.done != nil) { refresh() }
    }
}
