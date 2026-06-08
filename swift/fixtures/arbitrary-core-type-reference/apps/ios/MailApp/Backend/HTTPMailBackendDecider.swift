// @archlint.module core
// @archlint.domain backend.http
struct CoreVocabulary {}

enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
