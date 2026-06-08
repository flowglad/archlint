// @archlint.module value
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  func normalizedDisplayName() -> String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
