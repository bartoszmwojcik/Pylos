# Decision records

Each record explains one choice and the reason for it. The product brief (`.ai/specs/product-brief.md`) is the source of the decisions. To add a record, copy `0000-template.md`, take the next free number, and append a row below.

| Number | Title | Status | Brief id |
|---|---|---|---|
| [0000](0000-template.md) | Template | n/a | n/a |
| [0001](0001-slice-plan.md) | Slice plan S1–S5, Now versus Later | Accepted | Scope, D04, D05 (supersedes R01, R02, N01 in the brief) |
| [0002](0002-haskell-backend-serves-frontend.md) | Haskell backend serves the web frontend | Accepted | D01 |
| [0003](0003-bots-first-observable.md) | Bots first, and bot games must be observable | Accepted | D02 |
| [0004](0004-browser-demo.md) | The demo runs in a web browser | Accepted | D03 |
| [0005](0005-pure-reference-engine.md) | Pure reference engine checked by QuickCheck | Accepted | D04 |
| [0006](0006-bitboard-engine-checked-by-perft.md) | Bitboard engine checked against the reference by perft | Accepted | D05 |
| [0007](0007-understandable-code-and-reasons.md) | Code and reasons must be understandable | Accepted | D06 |
| [0008](0008-discovery-and-backlog-first.md) | Discovery and a backlog come before spec or code | Accepted | D07 |
| [0009](0009-compound-move-and-perft-definition.md) | A move is a compound value; perft counts moves | Accepted | D08 |
| [0010](0010-notation-and-game-records.md) | Position notation and JSON game records | Accepted | D09 |
| [0011](0011-toolchain-ghc-cabal-tasty.md) | Toolchain: GHC 9.10, ghcup, cabal, tasty | Accepted | D10 |
| [0012](0012-golden-perft-and-playout-files.md) | Golden perft and playout files | Accepted | D11 |
| [0013](0013-bounded-playout-no-engine-draw-rule.md) | Bounded playout; no draw rule in the engine | Accepted | D12 (with R06) |
| [0014](0014-decision-records-and-haddock-rule-ids.md) | Decision records and Haddock rule citations | Accepted | D13 |
| [0015](0015-row-rule-is-standard.md) | The row rule is part of the standard rules | Accepted | D14 (supersedes N01; R07, R08) |
| [0016](0016-package-layout.md) | Two libraries: the reference engine cannot import the bitboard engine | Proposed | D04, D05, P03 |
| [0017](0017-record-and-golden-formats.md) | A version field in game records; one JSON value per line in golden files | Proposed | D09, D11 |
| [0018](0018-own-random-generator.md) | The engine carries its own random number generator | Proposed | D11, D12 |
| [0019](0019-playouts-pick-from-sorted-moves.md) | A playout picks its random move from the sorted move list | Proposed | D05, D11, D12 |
| [0020](0020-bitboard-representation.md) | The bitboard representation | Proposed | D05, R03, R04, R07, R08 |
| [0021](0021-dependencies.md) | Library dependencies | Proposed | D09, D10 |
| [0022](0022-bots.md) | How the bots work | Accepted (D15); algorithms proposed | D15, D12 |
| [0023](0023-web-server.md) | The live game server | Accepted (D16); structure proposed | D16, D17, N02 |
| [0024](0024-ci-and-freeze-file.md) | CI and the dependency freeze file | Accepted (owner approved CI and the freeze file); details proposed | D10 |
| [0025](0025-human-play-protocol.md) | Human play on the server: the `human` player, the move route, one writer at a time | Proposed (D18, D16 are the owner's) | D18, D16, D12 |

Records 0002–0015 copy decisions the owner made in the brief. Records from 0016 on are implementation choices made while building the engines. They stay Proposed until the owner accepts them.
