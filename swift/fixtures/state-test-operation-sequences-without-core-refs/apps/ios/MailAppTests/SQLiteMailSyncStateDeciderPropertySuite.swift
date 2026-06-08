// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func reduceProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { value in
      #expect(SQLiteMailSyncStateDecider.reduce(value) == value)
    }
  }

  @Test
  static func unrelatedOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(helper(value) == value)
      }
    }
  }

  static func helper(_ value: Int) -> Int {
    value
  }
}
