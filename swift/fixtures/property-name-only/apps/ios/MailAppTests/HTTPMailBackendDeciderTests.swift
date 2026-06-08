// @archlint.module test
// @archlint.domain backend.http
import Testing

@Test
func pathProperty() {
  #expect(HTTPMailBackendDecider.decidePath() == "/v1/accounts")
}
