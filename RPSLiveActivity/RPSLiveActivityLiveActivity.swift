//
//  RPSLiveActivityLiveActivity.swift
//  RPSLiveActivity
//
//  Created by Jason Dank on 8/29/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RPSLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct RPSLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RPSLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension RPSLiveActivityAttributes {
    fileprivate static var preview: RPSLiveActivityAttributes {
        RPSLiveActivityAttributes(name: "World")
    }
}

extension RPSLiveActivityAttributes.ContentState {
    fileprivate static var smiley: RPSLiveActivityAttributes.ContentState {
        RPSLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: RPSLiveActivityAttributes.ContentState {
         RPSLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: RPSLiveActivityAttributes.preview) {
   RPSLiveActivityLiveActivity()
} contentStates: {
    RPSLiveActivityAttributes.ContentState.smiley
    RPSLiveActivityAttributes.ContentState.starEyes
}
