-- | What one move is (decision D08).
--
-- A move is a single compound value: the action (place a ball from the
-- reserve, or raise one of your balls) plus the set of balls taken back after
-- it. Perft counts these values.
module Pylos.Reference.Move
  ( Action (..)
  , Move (..)
  , actionTarget
  , noTakeBack
  , isRaise
  ) where

import Data.Set (Set)
import qualified Data.Set as Set

import Pylos.Reference.Board (Pos)

-- | The first part of a move. D08.
--
-- * @Place p@ puts a ball from the reserve on square @p@.
-- * @Raise from to@ moves one of the mover's own balls from @from@ up to
--   @to@ (R03). It does not use the reserve.
data Action
  = Place !Pos
  | Raise !Pos !Pos
  deriving (Eq, Ord, Show)

-- | A compound move: an action plus 0–2 take-backs. D08, R07.
--
-- The take-backs are a 'Set', not a list. So two moves that take back the
-- same balls in a different order are the same move (D08): @Set@ equality
-- ignores order, and the derived 'Eq' and 'Ord' compare the sets.
data Move = Move
  { moveAction :: !Action
  , moveTakeBack :: !(Set Pos)
  }
  deriving (Eq, Ord, Show)

-- | The square the action puts a ball on.
actionTarget :: Action -> Pos
actionTarget (Place p) = p
actionTarget (Raise _ to) = to

-- | A move with no take-back.
noTakeBack :: Action -> Move
noTakeBack a = Move a Set.empty

-- | Whether a move is a raise.
isRaise :: Move -> Bool
isRaise (Move (Raise _ _) _) = True
isRaise _ = False
