// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
