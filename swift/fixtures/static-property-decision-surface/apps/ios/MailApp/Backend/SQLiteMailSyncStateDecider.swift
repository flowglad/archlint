// @archlint.module core
// @archlint.domain backend.sqlite
enum SQLiteMailSyncStateDecider {
  static let createTablesSQL: String = "CREATE TABLE messages(id TEXT)"

  static func loadedState(_ shard: Int) -> String {
    shard >= 0 ? "loaded" : "loaded"
  }
}
