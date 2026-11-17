import Foundation

enum ShellTab: String, CaseIterable, Identifiable {
    case bogo, activity, settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bogo: return "BOGO"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .bogo: return "checkmark.shield"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

enum ShellModel {
    static let tabs = ShellTab.allCases
}
