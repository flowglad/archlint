// @archlint.module core
// @archlint.domain demo.constant

export function decideConstant(x: number): string {
  return x >= 0 ? "positive" : "negative";
}
