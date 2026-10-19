import Foundation

struct LiveSessionSnapshot: Codable, Hashable {
    var sessionId: String
    var title: String
    var toolIcon: String
    var toolStatus: String
    var loopIteration: Int
    var isCompleted: Bool = false
    var lastMessage: String = ""
}
