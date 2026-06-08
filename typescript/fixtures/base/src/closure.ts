// @archlint.module core
// @archlint.domain demo.closure

export function decideA(value: number): boolean {
  return value >= 0;
}

export function decideB(value: number): boolean {
  return value < 0;
}

export function decideC(value: number): boolean {
  return value === 0;
}
