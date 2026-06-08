// @archlint.module shell
// @archlint.domain backend.http
import Combine

final class FakeMailBackendClient {
  @Published var accounts: [String] = []
}
