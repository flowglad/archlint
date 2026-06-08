// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

@Test
func pathProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { _ in
    #expect(HTTPMailBackendDecider.decidePath() == "/v1/accounts")
  }
}
