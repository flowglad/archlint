// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func pathProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { shard in
      #expect(helperPath(shard) == "/v1/accounts")
    }
  }

  static func helperPath(_ shard: Int) -> String {
    HTTPMailBackendDecider.decidePath(shard)
  }
}
