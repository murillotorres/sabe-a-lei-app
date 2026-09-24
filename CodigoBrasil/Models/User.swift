import Foundation

struct User: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let email: String
    let createdAt: String
}
