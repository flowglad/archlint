// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func roundTripOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(value == value)
      }
    }
  }
}
