// @archlint.module shell
// @archlint.domain backend.http
import Foundation

struct HTTPMailBackendClient {
  func add() -> URLRequest {
    return URLRequest(url: URL(string: "http://localhost")!)
  }
}
