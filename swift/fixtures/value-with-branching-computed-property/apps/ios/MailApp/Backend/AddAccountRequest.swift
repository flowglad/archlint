// @archlint.module value
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  var normalizedDisplayName: String {
    if displayName.isEmpty {
      return "Mailbox"
    }
    return displayName
  }
}
