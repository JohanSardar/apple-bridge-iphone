import ActivityKit

struct AgentTaskAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var progress: Double
        var title: String? = nil
    }
    let taskID: String
    let title: String
}
