// @archlint.module core
// @archlint.domain demo.decision

export function decide(x: number): string {
  return x >= 0 ? "positive" : "negative";
}

export const decisionNode = (value: number): { kind: "node"; value: number } => ({
  kind: "node",
  value,
});

export function wrappedDecide(x: number): string {
  return decide(x);
}
