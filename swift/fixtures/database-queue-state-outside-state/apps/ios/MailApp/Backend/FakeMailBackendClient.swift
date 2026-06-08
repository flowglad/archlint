// @archlint.module shell
// @archlint.domain backend.http
import GRDB

struct FakeMailBackendClient {
  let database: DatabaseQueue
}
