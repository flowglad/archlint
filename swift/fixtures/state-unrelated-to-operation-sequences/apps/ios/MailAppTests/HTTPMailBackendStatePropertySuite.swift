// @archlint.module stateTest
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendStatePropertySuite {
  @Test
  static func unrelatedOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(OtherDecider.reduce(value) == value)
      }
    }
  }
}
