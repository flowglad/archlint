// @archlint.module shell
// @archlint.domain backend.http
import Foundation

func decidePathForRequest(_ shard: Int) -> String {
  HTTPMailBackendDecider.decidePath(shard)
}

final class HTTPMailBackendClient {
  func makeRequest() -> URLRequest {
    let path = decidePathForRequest(0)
    let url = URL(string: "http://localhost" + path)!
    return URLRequest(url: url)
  }
}
