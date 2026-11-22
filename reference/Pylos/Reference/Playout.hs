-- | Bounded random playouts. D12.
--
-- A playout plays uniformly random legal moves until the game ends or a
-- ply bound is reached. The engine has no draw rule (R06): a game can go on
-- for ever, because take-backs return balls to the reserve. So a playout
-- always has a bound, and reports 'Capped' when it hits it. Deciding that a
-- capped game is a draw is the match runner's job (S3), not the engine's.
module Pylos.Reference.Playout
  ( Outcome (..)
  , PlayoutResult (..)
  , playout
  , playoutMoves
  , pickMove
  ) where

import Data.List (sort)

import Pylos.Reference.Board
import Pylos.Reference.Move (Move)
import Pylos.Reference.Random
import Pylos.Reference.Rules (applyMove, legalMoves, winner)

-- | How a finished game ended: who won. R05.
newtype Outcome = Winner Colour
  deriving (Eq, Ord, Show)

-- | The result of a bounded playout. D12.
data PlayoutResult
  = -- | The game ended after this many plies.
    Finished !Outcome !Int
  | -- | The ply bound was reached first.
    Capped !Int
  deriving (Eq, Ord, Show)

-- | Pick a random move. The moves are sorted first, so the choice depends
-- only on the set of legal moves and the generator, not on the order an
-- engine happens to list them in. That lets the bitboard engine replay the
-- same seeded games (D11). See @docs/adr/0019-playouts-pick-from-sorted-moves.md@.
pickMove :: [Move] -> Gen -> Maybe (Move, Gen)
pickMove [] _ = Nothing
pickMove ms g = Just (sorted !! i, g')
  where
    sorted = sort ms
    (i, g') = uniformIndex (length sorted) g

-- | Play random moves from a position, at most @bound@ plies. D12.
playout :: Int -> Gen -> Position -> PlayoutResult
playout bound g pos = fst (playoutMoves bound g pos)

-- | Like 'playout', also returning the moves played, in order.
playoutMoves :: Int -> Gen -> Position -> (PlayoutResult, [Move])
playoutMoves bound = go 0 []
  where
    go plies acc g pos
      | Just w <- winner pos = (Finished (Winner w) plies, reverse acc)
      | plies >= bound = (Capped plies, reverse acc)
      | otherwise = case pickMove (legalMoves pos) g of
          -- Unreachable: a game that is not over always has a move (R05).
          Nothing -> (Capped plies, reverse acc)
          Just (m, g') -> go (plies + 1) (m : acc) g' (applyMove m pos)
