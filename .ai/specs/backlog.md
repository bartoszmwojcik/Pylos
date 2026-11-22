# Backlogs

## .ai/specs/product-brief.md
Backlog source: .ai/specs/product-brief.md
Last filed: 2026-11-22

| Id | Issue | Title | Epic | Depends on | Adopted |
|---|---|---|---|---|---|
| E01 | [#1](https://github.com/bartoszmwojcik/Pylos/issues/1) | Toolchain and project skeleton | — | — | no |
| E02 | [#2](https://github.com/bartoszmwojcik/Pylos/issues/2) | Reference engine (S1) | — | — | no |
| E03 | [#3](https://github.com/bartoszmwojcik/Pylos/issues/3) | Bitboard engine (S2) | — | — | no |
| E04 | [#4](https://github.com/bartoszmwojcik/Pylos/issues/4) | Later (parked) | — | — | no |
| E01-S01 | [#5](https://github.com/bartoszmwojcik/Pylos/issues/5) | The owner can build and test the project on the headless server | #1 | — | no |
| E01-S02 | [#6](https://github.com/bartoszmwojcik/Pylos/issues/6) | The owner can read why the project is built the way it is | #1 | E01-S01 | no |
| E02-S01 | [#7](https://github.com/bartoszmwojcik/Pylos/issues/7) | The owner can build any board position and see it printed | #2 | E01-S01 | no |
| E02-S02 | [#8](https://github.com/bartoszmwojcik/Pylos/issues/8) | The owner can list and apply every legal move under the agreed rules | #2 | E02-S01 | no |
| E02-S03 | [#9](https://github.com/bartoszmwojcik/Pylos/issues/9) | The owner can write, read and replay games in notation | #2 | E02-S02 | no |
| E02-S04 | [#10](https://github.com/bartoszmwojcik/Pylos/issues/10) | The owner can run perft and bounded playouts and freeze golden values | #2 | E02-S02, E02-S03 | no |
| E03-S01 | [#11](https://github.com/bartoszmwojcik/Pylos/issues/11) | The owner can generate moves with the bitboard engine and get the same move sets as the reference | #3 | E02-S04 | no |
| E03-S02 | [#12](https://github.com/bartoszmwojcik/Pylos/issues/12) | The owner can confirm perft and playout parity and see the speed-up | #3 | E03-S01 | no |
