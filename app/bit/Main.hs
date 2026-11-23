-- | @pylos-bit@: the bitboard engine and its comparison with the reference.
--
-- > pylos-bit perft DEPTH [MOVE ...]     bitboard perft 1..DEPTH, with times
-- > pylos-bit bench DEPTH [MOVE ...]     both engines, perft DEPTH, nodes per second
-- > pylos-bit compare DEPTH [MOVE ...]   find the first move where the engines differ
-- > pylos-bit parity [DIR]               check every golden value (D11)
module Main (main) where

import Control.Exception (evaluate)
import Control.Monad (forM, unless)
import Data.Aeson (FromJSON, eitherDecodeFileStrict')
import qualified Data.Text as T
import GHC.Clock (getMonotonicTime)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hFlush, hPutStrLn, stderr, stdout)
import Text.Printf (printf)
import Text.Read (readMaybe)

import qualified Pylos.Bitboard as B
import Pylos.Compare
import qualified Pylos.Reference.Board as R
import Pylos.Reference.Golden
import Pylos.Reference.Move (Move)
import Pylos.Reference.Notation (parseMoves, playMoves)
import qualified Pylos.Reference.Perft as R
import Pylos.Reference.Random (mkGen)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("perft" : d : ms) -> do
      depth <- readArg d
      (_, pos) <- pathAndPosition ms
      let bpos = B.fromReference pos
      mapM_
        ( \k -> do
            (n, t) <- timed (B.perft k bpos)
            printf "perft %d: %d (%.3f s)\n" k n t
        )
        [1 .. depth]
    ("bench" : d : ms) -> do
      depth <- readArg d
      (_, pos) <- pathAndPosition ms
      (nr, tr) <- timed (R.perft depth pos)
      report "reference" depth nr tr
      (nb, tb) <- timed (B.perft depth (B.fromReference pos))
      report "bitboard" depth nb tb
      unless (nr == nb) (die' "MISMATCH: the engines disagree")
      printf "speed-up: %.1fx\n" (tr / max tb 1e-9)
    ("compare" : d : ms) -> do
      depth <- readArg d
      (path, _) <- pathAndPosition ms
      case findDivergence referenceEngine bitboardEngine depth path of
        Nothing -> putStrLn ("The engines agree on every move down to depth " ++ show depth ++ ".")
        Just dv -> do
          putStr (renderDivergence "reference" "bitboard" dv)
          exitFailure
    ["parity"] -> parity "golden"
    ["parity", dir] -> parity dir
    _ -> die' usage

usage :: String
usage =
  unlines
    [ "usage:"
    , "  pylos-bit perft DEPTH [MOVE ...]"
    , "  pylos-bit bench DEPTH [MOVE ...]"
    , "  pylos-bit compare DEPTH [MOVE ...]"
    , "  pylos-bit parity [DIR]"
    ]

die' :: String -> IO a
die' msg = hPutStrLn stderr msg >> exitFailure

readArg :: String -> IO Int
readArg s = maybe (die' ("bad DEPTH: " ++ s)) pure (readMaybe s)

pathAndPosition :: [String] -> IO ([Move], R.Position)
pathAndPosition args = do
  ms <- either die' pure (parseMoves args)
  pos <- either die' pure (playMoves R.startPosition ms)
  pure (ms, pos)

timed :: Integer -> IO (Integer, Double)
timed x = do
  t0 <- getMonotonicTime
  n <- evaluate x
  t1 <- getMonotonicTime
  pure (n, t1 - t0)

report :: String -> Int -> Integer -> Double -> IO ()
report name depth n t =
  printf
    "%-9s perft %d: %d nodes in %.3f s = %.0f nodes/s\n"
    name
    depth
    n
    t
    (fromIntegral n / max t 1e-9)

-- | Check the bitboard engine against every golden value.
parity :: FilePath -> IO ()
parity dir = do
  perfts <- load (dir ++ "/perft.json") :: IO [GoldenPerft]
  okPerft <- forM perfts $ \g -> do
    (_, pos) <- pathAndPosition (map T.unpack (goldenMoves g))
    let bpos = B.fromReference pos
        got = [B.perft d bpos | d <- [1 .. length (goldenPerft g)]]
        ok = got == goldenPerft g
    printf "perft %-18s %s\n" (T.unpack (goldenName g)) (if ok then "ok" else "MISMATCH " ++ show got)
    hFlush stdout
    pure ok
  playouts <- load (dir ++ "/playouts.json") :: IO [GoldenPlayout]
  let bad =
        [ (g, got)
        | g <- playouts
        , let got = playoutResultText (B.playout (gpBound g) (mkGen (gpSeed g)) B.startPosition)
        , got /= (gpResult g, gpPlies g)
        ]
  printf "playouts: %d of %d match\n" (length playouts - length bad) (length playouts)
  mapM_ (\(g, got) -> printf "  seed %d: golden %s, bitboard %s\n" (gpSeed g) (show (gpResult g, gpPlies g)) (show got)) bad
  unless (and okPerft && null bad) exitFailure
  where
    load :: FromJSON a => FilePath -> IO a
    load path = eitherDecodeFileStrict' path >>= either die' pure
