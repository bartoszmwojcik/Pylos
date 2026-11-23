# Code review rules

These rules are applied by `om-code-review` in addition to its built-in checklist. Add repo-specific checks here as conventions emerge in the code.

## Priorities

1. **Rule correctness.** Engine code must implement the Business rules in `.ai/specs/product-brief.md` (the active rules R03–R08, with D14) and the move definition D08 exactly.
   - A behaviour change to a rule needs a superseding row in the brief, approved by the owner.
   - It also needs an updated hand-built test for that rule.
2. **Oracle integrity.**
   - The reference engine must stay independent of the bitboard engine: no imports from bitboard modules.
   - Golden perft and playout files (D11) change only through a deliberate regeneration that is explained in the PR. They are never edited by hand to make a test pass.
3. **Explainability (D06, D13).**
   - A rule function without a Haddock comment citing its rule id is a finding.
   - So is a non-obvious design choice without a decision record in `docs/adr/`.
4. **Purity and readability in the reference engine (D04, N04).**
   - Flag `IO`, mutable state or unsafe operations in reference modules.
   - Flag optimisation that obscures the rule.
5. **Tests.**
   - New engine behaviour comes with a QuickCheck property or an HUnit rule test.
   - Properties must use generators of reachable positions (produced by random legal play), not arbitrary boards.
6. **Validation gate.** `cabal build all` and `cabal test all` pass. Treat compiler warnings in new code as findings.

## Severity

- **Blocker:** a rule implemented contrary to the brief, an edited golden file, a broken oracle independence, or a failing validation gate.
- **Major:** a missing test for new behaviour, or a missing rule citation or decision record.
- **Minor:** naming, style, or Haddock wording.
