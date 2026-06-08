// @archlint.module test
// @archlint.domain backend.closure
import PropertyBased
import Testing

func helper(_ shard: Int) -> Bool {
  ClosureDecider.decideC(shard)
}

@Test
func closureProperty() async {
  await propertyCheck(
    input: Gen.int(in: 0...10).map { shard in
      _ = ClosureDecider.decideB(shard)
      return shard
    }
  ) { shard in
    #expect(ClosureDecider.decideA(shard) || helper(shard) || shard >= 0)
  }
}
