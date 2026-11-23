-- | The evaluation function shared by the greedy and alpha-beta bots (D15).
--
-- Pylos is won by keeping balls: the player who runs out of reserve first
-- loses (R05). So the main term is the reserve advantage. The second term
-- counts free balls, because free balls can be raised (saving a ball, R03)
-- or taken back (R07).
module Pylos.Bot.Eval
  ( evaluate
  , winScore
  ) where

import Data.Bits (popCount, (.|.))

import qualified Pylos.Bitboard as B
import Pylos.Bot.Spec (Weights (..))

-- | A score above any evaluation: a won game.
winScore :: Int
winScore = 1000000

-- | How good the position is for the player to move. Positive is good.
--
-- A finished game is a loss for the player to move (R05).
evaluate :: Weights -> B.BPosition -> Int
evaluate w p
  | B.reserveToMove p == 0 = negate winScore
  | otherwise =
      wReserve w * (myReserve - theirReserve) + wFree w * (myFree - theirFree)
  where
    (own, other) = B.ownAndOther p
    occ = own .|. other
    myReserve = B.reserveToMove p
    theirReserve = if B.bWhiteToMove p then B.bBlackReserve p else B.bWhiteReserve p
    myFree = popCount (B.freeOf own occ)
    theirFree = popCount (B.freeOf other occ)
