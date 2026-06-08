// @archlint.module test
// @archlint.domain backend.http
import XCTest

final class HTTPMailBackendDeciderTests: XCTestCase {
  func testPath() {
    XCTAssertEqual(HTTPMailBackendDecider.decidePath(), "/v1/accounts")
  }
}
