// @archlint.module interface
// @archlint.domain backend.http
// actor CommentOnly { private var accounts: [String] = [] }
// @Published var commentOnly: String = ""
// DatabaseQueue and UserDefaults.standard are mentioned in prose only.

struct FakeMailBackendClient {
  let endpoint: String
}
