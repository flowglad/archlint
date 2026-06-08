// @archlint.module shell
// @archlint.domain backend.http
import Foundation

actor FakeMailBackendClient {
  private var accounts: [String] = []

  func add(_ account: String) {
    accounts.append(account)
  }
}
