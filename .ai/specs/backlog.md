# Backlogs

## .ai/specs/product-brief.md
Backlog source: .ai/specs/product-brief.md
Last filed: 2026-11-24 (E05 #30 with stories #31–#35 and parked E06 #36 added after the S5 refresh; E01–E04 are closed)

| Id | Issue | Title | Epic | Depends on | Adopted |
|---|---|---|---|---|---|
| E01 | [#1](https://github.com/bartoszmwojcik/Pylos/issues/1) | Toolchain and project skeleton | — | — | no |
| E02 | [#2](https://github.com/bartoszmwojcik/Pylos/issues/2) | Reference engine (S1) | — | — | no |
| E03 | [#3](https://github.com/bartoszmwojcik/Pylos/issues/3) | Bitboard engine (S2) | — | — | no |
| E04 | [#4](https://github.com/bartoszmwojcik/Pylos/issues/4) | Bots and live 3D viewer (S3, S4) | — | — | no |
| E05 | [#30](https://github.com/bartoszmwojcik/Pylos/issues/30) | Human-vs-bot play (S5) | — | — | no |
| E06 | [#36](https://github.com/bartoszmwojcik/Pylos/issues/36) | Later | — | — | no |
| E01-S01 | [#5](https://github.com/bartoszmwojcik/Pylos/issues/5) | The owner can build and test the project on the headless server | #1 | — | no |
| E01-S02 | [#6](https://github.com/bartoszmwojcik/Pylos/issues/6) | The owner can read why the project is built the way it is | #1 | E01-S01 | no |
| E02-S01 | [#7](https://github.com/bartoszmwojcik/Pylos/issues/7) | The owner can build any board position and see it printed | #2 | E01-S01 | no |
| E02-S02 | [#8](https://github.com/bartoszmwojcik/Pylos/issues/8) | The owner can list and apply every placement and raise, and the game ends correctly | #2 | E02-S01 | no |
| E02-S05 | [#15](https://github.com/bartoszmwojcik/Pylos/issues/15) | The owner can complete squares and rows and take back 0–2 balls under the chosen rules | #2 | E02-S02 | no |
| E02-S03 | [#9](https://github.com/bartoszmwojcik/Pylos/issues/9) | The owner can write, read and replay games in notation | #2 | E02-S05 | no |
| E02-S04 | [#10](https://github.com/bartoszmwojcik/Pylos/issues/10) | The owner can run perft and bounded playouts and freeze golden values | #2 | E02-S05, E02-S03 | no |
| E03-S01 | [#11](https://github.com/bartoszmwojcik/Pylos/issues/11) | The owner can generate moves with the bitboard engine and get the same move sets as the reference | #3 | E02-S04 | no |
| E03-S02 | [#12](https://github.com/bartoszmwojcik/Pylos/issues/12) | The owner can confirm perft and playout parity and see the speed-up | #3 | E03-S01 | no |
| E04-S01 | [#18](https://github.com/bartoszmwojcik/Pylos/issues/18) | The owner can pick a bot by a one-line spec and it always plays a legal move | #4 | E03-S02 | no |
| E04-S02 | [#19](https://github.com/bartoszmwojcik/Pylos/issues/19) | The owner can run a match between two bots and read the score | #4 | E04-S01 | no |
| E04-S03 | [#20](https://github.com/bartoszmwojcik/Pylos/issues/20) | The owner can start and follow a live bot game through the web server | #4 | E04-S01 | no |
| E04-S04 | [#21](https://github.com/bartoszmwojcik/Pylos/issues/21) | The owner can watch a live bot game in 3D in the browser | #4 | E04-S03 | no |
| E05-S01 | [#31](https://github.com/bartoszmwojcik/Pylos/issues/31) | The owner can start the server so a phone on the home network can open it | #30 | — | no |
| E05-S02 | [#32](https://github.com/bartoszmwojcik/Pylos/issues/32) | The owner can play a full game against a bot through the server | #30 | — | no |
| E05-S03 | [#33](https://github.com/bartoszmwojcik/Pylos/issues/33) | The owner can play a bot in the 3D viewer with a mouse on a large screen | #30 | E05-S02 | no |
| E05-S04 | [#34](https://github.com/bartoszmwojcik/Pylos/issues/34) | The owner can play a bot on a phone by touch | #30 | E05-S01, E05-S03 | no |
| E05-S05 | [#35](https://github.com/bartoszmwojcik/Pylos/issues/35) | The owner can choose a training game and see the bot's score after each move | #30 | E05-S03 | no |
