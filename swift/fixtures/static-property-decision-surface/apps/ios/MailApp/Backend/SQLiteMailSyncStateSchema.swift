// @archlint.module shell
// @archlint.domain backend.sqlite
import Foundation

struct SQLiteMailSyncStateSchema {
  let request = URLRequest(url: URL(string: "http://localhost")!)
  let sql: String = SQLiteMailSyncStateDecider.createTablesSQL
}
