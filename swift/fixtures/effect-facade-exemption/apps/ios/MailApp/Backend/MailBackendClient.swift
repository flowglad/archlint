// @archlint.module exempt
// @archlint.exempt-reason effect-facade
protocol MailBackendClient {
  func sync() async throws
}
