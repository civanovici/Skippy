import Foundation
import Observation

@Observable
final class AppState {
    enum Tab: Hashable {
        case home
        case library
        case series
        case collections
    }

    var selectedTab: Tab = .library
    var selectedBookID: String?
}
