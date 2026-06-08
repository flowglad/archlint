// @archlint.module shell
// @archlint.domain backend.http
import Foundation

final class HTTPMailBackendClient {
  func makeRequest() -> URLRequest {
    let path = HTTPMailBackendDecider.decidePath(0)
    let url = URL(string: "http://localhost" + path)!
    return URLRequest(url: url)
  }
}
