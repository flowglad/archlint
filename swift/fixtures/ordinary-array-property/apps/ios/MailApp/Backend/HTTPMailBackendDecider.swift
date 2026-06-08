// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decode(_ values: [Int]) -> Int {
    values.count
  }
}
