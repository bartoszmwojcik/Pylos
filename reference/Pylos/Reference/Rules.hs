-- | The rules of the game: which moves are legal, what a move does, and when
-- the game is over.
--
-- Every function here is written to be read next to the rule it implements.
-- The rule ids (R03–R08, D08) refer to the Business rules and Decisions in
-- @.ai/specs/product-brief.md@. Speed is not a goal in this module (N04).
module Pylos.Reference.Rules
  ( -- * Squares and balls
    isSupported
  , isEmpty
  , isFree
  , freeBallsOf
    -- * Shapes (R07)
  , ShapeKind (..)
  , Shape (..)
  , allShapes
  , shapesThrough
  , completesShape
    -- * Moves
  , applyAction
  , actions
  , takeBackOptions
  , legalMoves
  , isLegal
  , applyMove
  , playMove
    -- * End of the game (R05)
  , winner
  , isGameOver
  ) where

import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

import Pylos.Reference.Board
import Pylos.Reference.Move

-- ---------------------------------------------------------------------------
-- Squares and balls

-- | A square can hold a ball only when all the squares beneath it hold balls.
-- Level a rests on the table and is always supported. R08.
isSupported :: Board -> Pos -> Bool
isSupported b p = all (`Map.member` b) (supports p)

-- | No ball on the square. A placement or a raise needs an empty target (R03, R08).
isEmpty :: Board -> Pos -> Bool
isEmpty b p = not (Map.member p b)

-- | A ball is free when no ball rests on it. R04.
--
-- Only a free ball may be raised (R03) or taken back (R07). Removing a free
-- ball never leaves another ball floating, because nothing stands on it.
isFree :: Board -> Pos -> Bool
isFree b p = Map.member p b && all (isEmpty b) (restingOn p)

-- | The free balls of one colour. R04.
freeBallsOf :: Colour -> Board -> [Pos]
freeBallsOf col b =
  [p | (p, owner) <- Map.toAscList b, owner == col, isFree b p]

-- ---------------------------------------------------------------------------
-- Shapes

-- | The two kinds of shape that allow a take-back. R07.
data ShapeKind
  = -- | A 2×2 block on level a, b or c.
    Square
  | -- | A full horizontal or vertical line of 4 on level a (D14).
    Row
  deriving (Eq, Ord, Show)

-- | A shape and the squares it is made of.
data Shape = Shape
  { shapeKind :: !ShapeKind
  , shapeSquares :: ![Pos]
  }
  deriving (Eq, Ord, Show)

-- | Every shape on the board: 9 + 4 + 1 squares on levels a, b, c, and
-- 4 horizontal + 4 vertical rows on level a. 22 in total. R07, D14.
--
-- Not shapes (R07): diagonals, rows of 3 on level b, and anything on level d.
allShapes :: [Shape]
allShapes = squares ++ rows
  where
    squares =
      [ Shape Square [Pos l r' c' | r' <- [r, r + 1], c' <- [c, c + 1]]
      | l <- [A, B, C]
      , let n = levelSize l
      , r <- [1 .. n - 1]
      , c <- [1 .. n - 1]
      ]
    rows =
      [Shape Row [Pos A r c | c <- [1 .. 4]] | r <- [1 .. 4]]
        ++ [Shape Row [Pos A r c | r <- [1 .. 4]] | c <- [1 .. 4]]

-- | The shapes that contain a given square. R07, D14.
shapesThrough :: Pos -> [Shape]
shapesThrough p = [s | s <- allShapes, p `elem` shapeSquares s]

-- | Does the ball just put on @p@ complete a shape of the mover's colour?
-- R07.
--
-- The board given is the board /after/ the action. Before the action @p@
-- was empty, so any complete shape through @p@ is new: this move completed
-- it. Shapes that do not contain @p@ were already there and do not count.
completesShape :: Colour -> Board -> Pos -> Bool
completesShape col b p = any ownsAll (shapesThrough p)
  where
    ownsAll s = all (\q -> Map.lookup q b == Just col) (shapeSquares s)

-- ---------------------------------------------------------------------------
-- Moves

-- | Every action the player to move can take, ignoring take-backs.
--
-- * Place (R08): a ball from the reserve on any empty, supported square.
--   Needs a ball in the reserve.
-- * Raise (R03): one of the player's own free balls moves to an empty
--   square on a strictly higher level. The target must be supported
--   /after/ the ball has left its square. That is what forbids raising a
--   ball onto a square it supports: once it has left, the target is missing
--   a support. A raise replaces placing, so the reserve is not used.
actions :: Position -> [Action]
actions pos = placements ++ raises
  where
    b = board pos
    me = toMove pos
    placements
      | reserveOf me pos > 0 =
          [Place p | p <- allPositions, isEmpty b p, isSupported b p]
      | otherwise = []
    raises =
      [ Raise from to
      | from <- freeBallsOf me b
      , let without = Map.delete from b
      , to <- allPositions
      , posLevel to > posLevel from
      , isEmpty without to
      , isSupported without to
      ]

-- | The board after an action, before any take-back. R03.
applyAction :: Colour -> Action -> Board -> Board
applyAction col (Place p) b = Map.insert p col b
applyAction col (Raise from to) b = Map.insert to col (Map.delete from b)

-- | The take-back sets allowed after completing a shape. R07, R04, D08.
--
-- The player may take back nothing, one of their own free balls, or two.
-- Two balls are taken back one after the other (R04), so the second ball
-- only has to be free once the first is gone. A pair is allowed when at
-- least one order works (D08). The result is a set of sets, so a pair that
-- works in both orders is listed once.
--
-- The ball just placed or raised is free, so it may be taken back too.
-- Never more than 2 balls, however many shapes the move completed (R07).
takeBackOptions :: Colour -> Board -> [Set Pos]
takeBackOptions col b = Set.toAscList (Set.fromList (none : singles ++ pairs))
  where
    none = Set.empty
    firsts = freeBallsOf col b
    singles = [Set.singleton x | x <- firsts]
    pairs =
      [ Set.fromList [x, y]
      | x <- firsts
      , y <- freeBallsOf col (Map.delete x b)
      , y /= x
      ]

-- | All legal moves of the player to move, each once. D08.
--
-- For each action: if it completes a shape (R07), it comes with every
-- take-back option, including taking nothing back; otherwise it comes with
-- no take-back. A finished game has no legal moves (R05).
legalMoves :: Position -> [Move]
legalMoves pos
  | isGameOver pos = []
  | otherwise =
      [ Move a t
      | a <- actions pos
      , let after = applyAction me a (board pos)
      , t <-
          if completesShape me after (actionTarget a)
            then takeBackOptions me after
            else [Set.empty]
      ]
  where
    me = toMove pos

-- | Is this move one of the legal moves? Equality is D08's: same action,
-- same take-back set.
isLegal :: Move -> Position -> Bool
isLegal m pos = m `elem` legalMoves pos

-- | Play a move without checking that it is legal. D08, R03, R07.
--
-- The action is applied, the take-back balls go back to the mover's
-- reserve, and the turn passes to the opponent. Use 'playMove' when the
-- move may be illegal.
applyMove :: Move -> Position -> Position
applyMove (Move a takeBack) pos =
  pos
    { board = boardAfter
    , whiteReserve = newReserve White
    , blackReserve = newReserve Black
    , toMove = opponent me
    }
  where
    me = toMove pos
    boardAfter =
      foldr Map.delete (applyAction me a (board pos)) (Set.toList takeBack)
    used = case a of
      Place _ -> 1
      Raise _ _ -> 0
    newReserve col
      | col == me = reserveOf col pos - used + Set.size takeBack
      | otherwise = reserveOf col pos

-- | Play a move after checking that it is legal (D08, via 'isLegal').
playMove :: Move -> Position -> Either String Position
playMove m pos
  | isLegal m pos = Right (applyMove m pos)
  | otherwise = Left "illegal move"

-- ---------------------------------------------------------------------------
-- End of the game

-- | The winner, if the game is over. R05.
--
-- The player to move who has no ball left in the reserve loses, even if
-- they could still raise. Placing the apex uses the last ball on the board,
-- so the opponent is then to move with an empty reserve and loses.
--
-- A player with a ball in the reserve can always place it: the lowest
-- level that is not full rests on full levels, so any empty square there is
-- supported. So no other way for the game to end is needed. There is no
-- draw rule (R06): an endless game is stopped by a ply cap outside the
-- engine (D12).
winner :: Position -> Maybe Colour
winner pos
  | reserveOf (toMove pos) pos == 0 = Just (opponent (toMove pos))
  | otherwise = Nothing

-- | The game is over when there is a winner. R05.
isGameOver :: Position -> Bool
isGameOver pos = winner pos /= Nothing
