-- | Test generators and helpers.
--
-- Properties run over /reachable/ positions: positions produced by random
-- legal play from the start (CODE_REVIEW.md). An arbitrary board could hold
-- states the game can never reach, such as a floating ball, which would
-- test nothing useful.
module Gen
  ( Reachable (..)
  , genReachable
  , pos
  , mkPosition
  , afterMoves
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Test.QuickCheck

import Pylos.Reference.Board
import Pylos.Reference.Move
import Pylos.Reference.Notation (parseMoves, parsePos, playMoves)
import Pylos.Reference.Rules

-- | A reachable position and the moves that reach it from the start.
data Reachable = Reachable
  { reachPath :: [Move]
  , reachPosition :: Position
  }

instance Show Reachable where
  show (Reachable path p) = show path ++ "\n" ++ renderPosition p

instance Arbitrary Reachable where
  arbitrary = genReachable
  -- Shrink to shorter games: every prefix of a legal game is legal.
  shrink (Reachable path _) =
    [ Reachable p (foldl (flip applyMove) startPosition p)
    | n <- [0 .. length path - 1]
    , let p = take n path
    ]

-- | Play 0 to 90 random legal moves from the start. A third of the moves
-- prefer the interesting kinds (raises and take-backs), so those cases
-- are well covered.
genReachable :: Gen Reachable
genReachable = do
  n <- chooseInt (0, 90)
  go n [] startPosition
  where
    go 0 acc p = pure (Reachable (reverse acc) p)
    go k acc p = case legalMoves p of
      [] -> pure (Reachable (reverse acc) p)
      ms -> do
        let special = [m | m <- ms, isRaise m || not (Set.null (moveTakeBack m))]
        m <-
          if null special
            then elements ms
            else frequency [(2, elements ms), (1, elements special)]
        go (k - 1) (m : acc) (applyMove m p)

-- | A square from its notation; fails loudly on a typo in a test.
pos :: String -> Pos
pos s = either error id (parsePos s)

-- | A hand-built position: White's squares, Black's squares, who moves.
-- Reserves are what is left of 15 balls each.
mkPosition :: [String] -> [String] -> Colour -> Position
mkPosition ws bs mover =
  Position
    { board = Map.fromList ([(pos s, White) | s <- ws] ++ [(pos s, Black) | s <- bs])
    , whiteReserve = ballsPerPlayer - length ws
    , blackReserve = ballsPerPlayer - length bs
    , toMove = mover
    }

-- | The position after a list of moves in notation, from the start.
afterMoves :: [String] -> Position
afterMoves ms = either error id (parseMoves ms >>= playMoves startPosition)
