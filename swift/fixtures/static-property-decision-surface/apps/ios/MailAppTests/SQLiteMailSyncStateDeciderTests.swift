// @archlint.module test
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

@Test
func schemaProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { shard in
    #expect(SQLiteMailSyncStateDecider.loadedState(shard) == "loaded")
  }
}
