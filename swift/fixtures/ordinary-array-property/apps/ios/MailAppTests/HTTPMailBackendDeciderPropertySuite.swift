// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func decodeAcceptsGeneratedArraysProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      #expect(HTTPMailBackendDecider.decode(values) == values.count)
    }
  }
}
