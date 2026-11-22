-- | Comparing two engines move by move (E03-S02).
--
-- Each engine is described in reference terms: given the moves played
-- from the start position, what are the legal moves, and what is perft.
-- Each engine replays the path itself, so a bug in how an engine applies a
-- move is found as well as a bug in how it lists moves.
--
-- 'findDivergence' is "divide" made automatic: compare the move lists; if
-- they agree, compare perft below every move; follow the first move whose
-- counts differ, one level down, until the move lists themselves differ.
module Pylos.Compare
  ( Engine (..)
  , referenceEngine
  , bitboardEngine
  , bitboardEngineWith
  , Divergence (..)
  , findDivergence
  , renderDivergence
  ) where

import Data.List (sort, (\\))

import qualified Pylos.Bitboard as B
import qualified Pylos.Reference.Board as R
import qualified Pylos.Reference.Move as R
import qualified Pylos.Reference.Notation as R
import qualified Pylos.Reference.Perft as R
import qualified Pylos.Reference.Rules as R

-- | An engine, seen through reference moves. The @[R.Move]@ argument is the
-- path from the start position; it is assumed to be legal.
data Engine = Engine
  { engineName :: String
  , engineMoves :: [R.Move] -> [R.Move]
  , enginePerft :: Int -> [R.Move] -> Integer
  }

-- | The reference engine.
referenceEngine :: Engine
referenceEngine =
  Engine
    { engineName = "reference"
    , engineMoves = R.legalMoves . refAfter
    , enginePerft = \d path -> R.perft d (refAfter path)
    }
  where
    refAfter = foldl (flip R.applyMove) R.startPosition

-- | The bitboard engine.
bitboardEngine :: Engine
bitboardEngine = bitboardEngineWith "bitboard" B.legalMoves

-- | The bitboard engine with a replaced move generator. The tests use it to
-- inject a deliberate bug.
bitboardEngineWith :: String -> (B.BPosition -> [B.BMove]) -> Engine
bitboardEngineWith name gen =
  Engine
    { engineName = name
    , engineMoves = map B.toRefMove . gen . bitAfter
    , enginePerft = \d path -> B.perftWith gen d (bitAfter path)
    }
  where
    bitAfter = foldl (\p m -> B.applyMove (B.fromRefMove m) p) B.startPosition

-- | Where two engines first disagree.
data Divergence = Divergence
  { divPath :: [R.Move]
  -- ^ The moves from the start to the position where the move lists differ.
  , divPosition :: R.Position
  -- ^ That position (as the reference engine reaches it).
  , divOnlyInFirst :: [R.Move]
  , divOnlyInSecond :: [R.Move]
  }
  deriving (Eq, Show)

-- | Compare two engines from the position after @path@, to depth @d@.
-- 'Nothing' means they agree on every move and perft count down to @d@.
findDivergence :: Engine -> Engine -> Int -> [R.Move] -> Maybe Divergence
findDivergence a b = go
  where
    go d path
      | d <= 0 = Nothing
      | movesA /= movesB =
          Just
            Divergence
              { divPath = path
              , divPosition = foldl (flip R.applyMove) R.startPosition path
              , divOnlyInFirst = movesA \\ movesB
              , divOnlyInSecond = movesB \\ movesA
              }
      | otherwise = firstJust [go (d - 1) (path ++ [m]) | m <- movesA, differs m]
      where
        movesA = sort (engineMoves a path)
        movesB = sort (engineMoves b path)
        differs m = enginePerft a (d - 1) (path ++ [m]) /= enginePerft b (d - 1) (path ++ [m])
    firstJust xs = case [x | Just x <- xs] of
      (x : _) -> Just x
      [] -> Nothing

-- | A human-readable report of a divergence.
renderDivergence :: String -> String -> Divergence -> String
renderDivergence nameA nameB dv =
  unlines $
    [ "First divergence after the moves: "
        ++ (if null (divPath dv) then "(start position)" else unwords' (divPath dv))
    , ""
    , R.renderPosition (divPosition dv)
    ]
      ++ [ "Only in " ++ nameA ++ ": " ++ R.renderMove m | m <- divOnlyInFirst dv ]
      ++ [ "Only in " ++ nameB ++ ": " ++ R.renderMove m | m <- divOnlyInSecond dv ]
  where
    unwords' = foldr1 (\x y -> x ++ ", " ++ y) . map R.renderMove
