// @archlint.module core
// @archlint.domain backend.closure
enum ClosureDecider {
  static func decideA(_ shard: Int) -> Bool {
    shard >= 0
  }

  static func decideB(_ shard: Int) -> Bool {
    shard < 0
  }

  static func decideC(_ shard: Int) -> Bool {
    shard == 0
  }
}
