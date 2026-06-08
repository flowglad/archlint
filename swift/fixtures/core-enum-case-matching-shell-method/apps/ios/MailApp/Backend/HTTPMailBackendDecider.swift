// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  enum Decision {
    case add
  }

  static func decide(_ shard: Int) -> Decision {
    shard >= 0 ? .add : .add
  }
}
