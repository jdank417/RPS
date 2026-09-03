//
//  Waiver.swift
//  RPS
//
//  The liability waiver shown at registration and, for an account that
//  predates it, as a one-time gate on next launch. Identical wording lives
//  in rps_admin's docs/LIABILITY_WAIVER.md (the canonical copy) and its
//  Angular console's core/waiver.ts - there's no shared-code path between
//  the clients, so if this text changes, update all three together,
//  including the version tag (the backend rejects an acceptance for
//  anything other than its own CURRENT_WAIVER_VERSION, see
//  app/core/waiver.py).
//

import Foundation

enum Waiver {
    static let currentVersion = "2026-09-03"

    static let intro = """
    Sailboat racing is inherently dangerous and can result in serious injury, death, or \
    property damage — from causes including, without limitation, collision with other \
    vessels, docks, or objects; capsizing; being struck by the boom, rigging, or other \
    equipment; falling overboard; adverse weather and sea conditions; and the acts or \
    omissions of other sailors, race committees, or third parties.
    """

    static let leadIn =
        "By creating an account and using RPS (\"the App\"), you acknowledge and agree to all of the following:"

    struct Clause: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let clauses: [Clause] = [
        Clause(
            title: "Assumption of risk.",
            body: """
            You choose to sail, race, and use the App entirely at your own risk. Neither \
            the App's developer nor any yacht club whose information appears in the App is \
            responsible for your safety, or the safety of your vessel or crew, on the water.
            """
        ),
        Clause(
            title: "Navigation aid only — not a safety device.",
            body: """
            Course, mark, bearing, distance, wind, tidal, and timing information shown in \
            the App is provided for convenience only. It may be inaccurate, delayed, or \
            unavailable — including due to GPS error, network loss, third-party weather \
            data, or a mark's charted or reported position being wrong or out of date. It \
            is never a substitute for your own seamanship, the Racing Rules of Sailing, the \
            official Sailing Instructions, or the Race Committee's actual signals and \
            instructions. Always confirm the course, marks, and start against official \
            sources before and during a race.
            """
        ),
        Clause(
            title: "No warranty.",
            body: """
            The App is provided "as is" and "as available," without warranty of any kind, \
            express or implied, including as to accuracy, reliability, availability, or \
            fitness for a particular purpose.
            """
        ),
        Clause(
            title: "Limitation of liability.",
            body: """
            To the fullest extent permitted by law, the developer of RPS will not be liable \
            for any injury, death, property damage, or other loss of any kind arising out \
            of or related to your use of the App or your participation in sailing or \
            racing, whether based on negligence, breach of warranty, or any other legal \
            theory, even if advised of the possibility of such loss.
            """
        ),
        Clause(
            title: "Release.",
            body: """
            To the fullest extent permitted by law, you release and agree not to bring any \
            claim against the developer of RPS arising from your use of the App or your \
            participation in sailing or racing events.
            """
        ),
    ]

    static let closing = "If you do not agree to all of the above, do not create an account or use the App."
}
