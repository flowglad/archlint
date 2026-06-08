// @archlint.module state
// @archlint.domain backend.sqlite
struct SQLiteMailSyncStateStore {
  func snapshot(_ value: Int) -> Int {
    SQLiteMailSyncStateDecider.reduce(value)
  }
}
