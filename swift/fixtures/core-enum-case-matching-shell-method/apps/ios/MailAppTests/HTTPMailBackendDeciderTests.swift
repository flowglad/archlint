// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

@Test
func decisionProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { shard in
    #expect(HTTPMailBackendDecider.decide(shard) == .add)
  }
}
