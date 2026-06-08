// @archlint.module shell
// @archlint.domain backend.http
import Foundation

final class HTTPMailBackendClient {
  func makeRequest() -> URLRequest {
    URLRequest(url: URL(string: "http://localhost")!)
  }
}
