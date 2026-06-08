// @archlint.module interface
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  var normalizedDisplayName: String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
