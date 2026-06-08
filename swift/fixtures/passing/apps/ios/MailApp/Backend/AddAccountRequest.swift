// @archlint.module interface
// @archlint.domain backend.http
struct AddAccountRequest: Equatable {
  let displayName: String
  let emailAddress: String
}
