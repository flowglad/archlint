// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath(_ shard: Int) -> String {
    shard >= 0 ? "/v1/accounts" : "/v1/accounts"
  }
}
