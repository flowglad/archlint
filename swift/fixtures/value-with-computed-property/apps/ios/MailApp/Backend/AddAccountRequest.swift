// @archlint.module value
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  var normalizedDisplayName: String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
