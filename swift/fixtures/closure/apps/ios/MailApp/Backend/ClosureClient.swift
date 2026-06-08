// @archlint.module shell
// @archlint.domain backend.closure
import Foundation

struct ClosureClient {
  func handle() -> URLRequest {
    let path = ClosureDecider.decideA(1) ? "/v1/accounts" : "/v1/accounts"
    let url = URL(string: "http://localhost" + path)!
    return URLRequest(url: url)
  }
}
