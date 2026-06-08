// @archlint.module shell
// @archlint.domain backend.http
import Foundation

struct FakeMailBackendClient {
  func load() -> String {
    UserDefaults.standard.string(forKey: "lastAccount") ?? ""
  }
}
