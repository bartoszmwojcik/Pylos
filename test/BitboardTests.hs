-- | Tests of the bitboard engine against the reference (E03, D05).
module BitboardTests (tests) where

import Control.Monad (forM_)
import Data.Bits (popCount)
import Data.List (isInfixOf, isPrefixOf, sort)
import qualified Data.Set as Set
import System.Directory (listDirectory, doesDirectoryExist)
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import Gen (Reachable (..))
import qualified Pylos.Bitboard as B
import Pylos.Compare
import Pylos.Reference.Board
import Pylos.Reference.Move
import Pylos.Reference.Notation (parseMoves)
import Pylos.Reference.Playout (playout)
import Pylos.Reference.Random (mkGen)
import Pylos.Reference.Rules

tests :: TestTree
tests =
  testGroup
    "Bitboard engine"
    [ testGroup
        "E03-S01 same moves as the reference"
        [ testProperty "converting to bitboards and back gives the same position" $
            \(Reachable _ p) -> B.toReference (B.fromReference p) === p
        , testProperty "both engines generate the same move set" $
            \(Reachable _ p) ->
              sort (map B.toRefMove (B.legalMoves (B.fromReference p)))
                === sort (legalMoves p)
        , testProperty "both engines agree on the position after every move" $
            \(Reachable _ p) ->
              conjoin
                [ counterexample (show m) $
                    B.toReference (B.applyMove (B.fromRefMove m) (B.fromReference p))
                      === applyMove m p
                | m <- legalMoves p
                ]
        , testProperty "both engines agree on the winner" $
            \(Reachable _ p) -> B.winner (B.fromReference p) === winner p
        , testProperty "move conversion round-trips" $
            \(Reachable _ p) ->
              conjoin [B.toRefMove (B.fromRefMove m) === m | m <- legalMoves p]
        , testCase "negative: no reference module imports the bitboard engine" $
            referenceSources >>= mapM_ checkNoBitboardImport
        ]
    , testGroup
        "E03-S02 parity"
        [ testProperty "seeded playouts agree with the reference" $
            \seed -> B.playout 300 (mkGen seed) B.startPosition === playout 300 (mkGen seed) startPosition
        , testCase "the engines agree to depth 3 below a mid-game position" $
            findDivergence referenceEngine bitboardEngine 3 (pathOf ["a11", "a12", "a21", "a22"])
              @?= Nothing
        , testCase "negative: an injected bug is found by the divide comparison" $ do
            -- The bug: the generator forgets every take-back of two balls.
            let buggy = bitboardEngineWith "buggy" (filter ((/= 2) . popCount . B.bmTakeBack) . B.legalMoves)
                start = pathOf ["a11", "a33", "a12", "a34"]
            case findDivergence referenceEngine buggy 3 start of
              Nothing -> assertFailure "the injected bug was not found"
              Just dv -> do
                -- Found two plies below the start, where White can first
                -- complete a square and take back two balls.
                length (divPath dv) @?= 6
                take 4 (divPath dv) @?= start
                divOnlyInSecond dv @?= []
                assertBool "missing moves should all take back 2" $
                  not (null (divOnlyInFirst dv))
                    && all ((== 2) . Set.size . moveTakeBack) (divOnlyInFirst dv)
                let report = renderDivergence "reference" "buggy" dv
                assertBool report ("First divergence after the moves" `isInfixOf` report)
        ]
    ]
  where
    pathOf ms = either error id (parseMoves ms)

-- | All Haskell files under reference/.
referenceSources :: IO [FilePath]
referenceSources = go "reference"
  where
    go dir = do
      entries <- listDirectory dir
      fmap concat $ mapM (\e -> let path = dir </> e in do
        isDir <- doesDirectoryExist path
        if isDir then go path else pure [path | ".hs" `isSuffixOf'` e]) entries
    isSuffixOf' suf s = reverse suf `isPrefixOf` reverse s

checkNoBitboardImport :: FilePath -> IO ()
checkNoBitboardImport path = do
  src <- readFile path
  forM_ (lines src) $ \l ->
    assertBool (path ++ " imports the bitboard engine: " ++ l) $
      not ("import" `isPrefixOf` l && ("Pylos.Bitboard" `isInfixOf` l || "Pylos.Compare" `isInfixOf` l))
