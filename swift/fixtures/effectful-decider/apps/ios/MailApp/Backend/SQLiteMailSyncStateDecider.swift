// @archlint.module core
// @archlint.domain backend.http
import Foundation

enum SQLiteMailSyncStateDecider {
  static func decideRequest() -> URLRequest {
    URLRequest(url: URL(string: "http://localhost")!)
  }
}
