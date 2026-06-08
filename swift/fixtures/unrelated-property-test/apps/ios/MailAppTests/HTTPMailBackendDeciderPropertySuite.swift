// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func unrelatedProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { value in
      #expect(value == value)
    }
  }
}
