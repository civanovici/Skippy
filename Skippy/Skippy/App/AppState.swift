import Foundation
import Observation

@Observable
final class AppState {
    enum Tab: Hashable {
        case home
        case library
        case series
        case collections
        case user
    }

    var selectedTab: Tab = .home
    var selectedBookID: String?
}
