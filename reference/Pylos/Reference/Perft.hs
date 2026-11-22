-- | Perft: counting move sequences. D08.
--
-- @perft n p@ is the number of different sequences of @n@ legal moves that
-- can be played from position @p@. Moves are compound values (D08), so a
-- placement with three take-back options counts as four moves. Perft counts
-- move sequences, not distinct positions: two sequences that reach the same
-- position both count.
--
-- Two engines that agree on perft for many positions and depths almost
-- certainly generate the same moves. That is how the bitboard engine is
-- checked against this one (D05).
module Pylos.Reference.Perft
  ( perft
  , divide
  ) where

import Pylos.Reference.Board (Position)
import Pylos.Reference.Move (Move)
import Pylos.Reference.Rules (applyMove, legalMoves)

-- | The number of move sequences of length @n@. D08.
--
-- Depth 0 has one sequence, the empty one. A finished game has no legal
-- moves, so it contributes 0 at every depth above 0.
perft :: Int -> Position -> Integer
perft n pos
  | n <= 0 = 1
  | otherwise = sum [perft (n - 1) (applyMove m pos) | m <- legalMoves pos]

-- | Perft split by the first move. Used to find where two engines disagree:
-- compare the counts move by move, then follow the first move that differs.
divide :: Int -> Position -> [(Move, Integer)]
divide n pos = [(m, perft (n - 1) (applyMove m pos)) | m <- legalMoves pos]
