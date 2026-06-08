// @archlint.module shell
// @archlint.domain backend.http
struct HTTPMailBackendClient {
  func makePath() -> String {
    let decidePath = "/v1/accounts"
    return decidePath
  }
}
