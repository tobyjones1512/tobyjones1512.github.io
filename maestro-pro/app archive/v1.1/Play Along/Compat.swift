import SwiftUI

// iOS 17 is the oldest system the app runs on. These stand in for newer modifiers: on iOS 17 sheets are the system's
// default size and the navigation title is left to the bar.
extension View {
    @ViewBuilder func pageSheet() -> some View {
        if #available(iOS 18, macCatalyst 18, *) { presentationSizing(.page) } else { self }
    }

    @ViewBuilder func titleHidden() -> some View {
        if #available(iOS 18, macCatalyst 18, *) { toolbar(removing: .title) } else { self }
    }
}
