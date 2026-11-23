-- | The golden files (D11): the reference engine still produces them, and
-- the bitboard engine matches them.
module GoldenTests (tests) where

import Data.Aeson (FromJSON, eitherDecodeFileStrict')
import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import qualified Pylos.Bitboard as B
import Pylos.Reference.Golden
import Pylos.Reference.Notation (parseMoves, playMoves)
import Pylos.Reference.Board (startPosition)
import Pylos.Reference.Random (mkGen)

tests :: TestTree
tests =
  testGroup
    "Golden files (D11)"
    [ testCase "golden/perft.json holds the start and at least 3 mid-game positions" $ do
        g <- load "golden/perft.json" :: IO [GoldenPerft]
        map goldenName g @?= [n | (n, _, _) <- goldenPositions]
        assertBool "fewer than 4 positions" (length g >= 4)
        case g of
          (start : _) -> take 4 (goldenPerft start) @?= [16, 240, 3360, 43680]
          [] -> assertFailure "empty golden file"
    , testCase "golden/playouts.json holds at least 100 seeded playouts" $ do
        g <- load "golden/playouts.json" :: IO [GoldenPlayout]
        assertBool "fewer than 100 playouts" (length g >= 100)
    , testCase "the reference engine reproduces golden/perft.json" $ do
        g <- load "golden/perft.json"
        either assertFailure (@?= g) (traverse computeGoldenPerft goldenPositions)
    , testCase "the reference engine reproduces golden/playouts.json" $ do
        g <- load "golden/playouts.json"
        map computeGoldenPlayout playoutSeeds @?= g
    , testCase "E03-S02: the bitboard engine matches every golden perft value" $ do
        g <- load "golden/perft.json" :: IO [GoldenPerft]
        mapM_ checkBitboardPerft g
    , testCase "E03-S02: the bitboard engine matches every golden playout" $ do
        g <- load "golden/playouts.json" :: IO [GoldenPlayout]
        mapM_ checkBitboardPlayout g
    ]

load :: FromJSON a => FilePath -> IO a
load path = eitherDecodeFileStrict' path >>= either (assertFailure . ((path ++ ": ") ++)) pure

checkBitboardPerft :: GoldenPerft -> Assertion
checkBitboardPerft g = do
  pos <-
    either assertFailure pure $
      parseMoves (map T.unpack (goldenMoves g)) >>= playMoves startPosition
  let bpos = B.fromReference pos
  assertEqual
    (T.unpack (goldenName g))
    (goldenPerft g)
    [B.perft d bpos | d <- [1 .. length (goldenPerft g)]]

checkBitboardPlayout :: GoldenPlayout -> Assertion
checkBitboardPlayout g =
  assertEqual
    ("seed " ++ show (gpSeed g))
    (gpResult g, gpPlies g)
    (playoutResultText (B.playout (gpBound g) (mkGen (gpSeed g)) B.startPosition))
