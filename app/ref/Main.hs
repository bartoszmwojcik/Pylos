{-# LANGUAGE OverloadedStrings #-}

-- | @pylos-ref@: the command line of the reference engine.
--
-- > pylos-ref show [MOVE ...]                  print the position after the moves
-- > pylos-ref moves [MOVE ...]                 list the legal moves there
-- > pylos-ref perft DEPTH [MOVE ...]           perft 1..DEPTH, with times
-- > pylos-ref divide DEPTH [MOVE ...]          perft DEPTH-1 after each first move
-- > pylos-ref playout SEED [BOUND]             one random game, as a JSON record
-- > pylos-ref replay FILE                      replay a JSON game record
-- > pylos-ref golden [DIR]                     regenerate the golden files (D11)
--
-- Each MOVE is one argument in the notation of D09, e.g. @a11@,
-- @a11-b22@ or @"a22 x a11"@ (quote moves with take-backs).
module Main (main) where

import Control.Exception (evaluate)
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson (ToJSON, encode)
import Data.List (intercalate)
import GHC.Clock (getMonotonicTime)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Printf (printf)
import Text.Read (readMaybe)

import Pylos.Reference.Board
import Pylos.Reference.Golden
import Pylos.Reference.Notation
import Pylos.Reference.Perft
import Pylos.Reference.Playout
import Pylos.Reference.Random (mkGen)
import Pylos.Reference.Record
import Pylos.Reference.Rules

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("show" : ms) -> positionAfter ms >>= putStr . renderPosition
    ("moves" : ms) -> do
      pos <- positionAfter ms
      mapM_ (putStrLn . renderMove) (legalMoves pos)
    ("perft" : d : ms) -> do
      depth <- readArg "DEPTH" d
      pos <- positionAfter ms
      mapM_ (perftLine pos) [1 .. depth]
    ("divide" : d : ms) -> do
      depth <- readArg "DEPTH" d
      pos <- positionAfter ms
      let rows = divide depth pos
      mapM_ (\(m, n) -> putStrLn (renderMove m ++ ": " ++ show n)) rows
      putStrLn ("total: " ++ show (sum (map snd rows)))
    ["playout", s] -> playoutCmd s "300"
    ["playout", s, b] -> playoutCmd s b
    ["replay", file] -> do
      bytes <- BL.readFile file
      record <- either die' pure (decodeRecord bytes)
      (final, res) <- either die' pure (replay record)
      putStr (renderPosition final)
      putStrLn ("Recorded result: " ++ show (recordResult record))
      putStrLn ("Replayed result: " ++ show res)
    ["golden"] -> golden "golden"
    ["golden", dir] -> golden dir
    _ -> die' usage

usage :: String
usage =
  intercalate
    "\n"
    [ "usage:"
    , "  pylos-ref show [MOVE ...]"
    , "  pylos-ref moves [MOVE ...]"
    , "  pylos-ref perft DEPTH [MOVE ...]"
    , "  pylos-ref divide DEPTH [MOVE ...]"
    , "  pylos-ref playout SEED [BOUND]"
    , "  pylos-ref replay FILE"
    , "  pylos-ref golden [DIR]"
    , "Each MOVE is one argument, e.g. a11, a11-b22, \"a22 x a11\"."
    ]

die' :: String -> IO a
die' msg = hPutStrLn stderr msg >> exitFailure

readArg :: Read a => String -> String -> IO a
readArg name s = maybe (die' ("bad " ++ name ++ ": " ++ s)) pure (readMaybe s)

-- | Parse and play the moves; exit non-zero naming the first bad one.
positionAfter :: [String] -> IO Position
positionAfter args = do
  ms <- either die' pure (parseMoves args)
  either die' pure (playMoves startPosition ms)

perftLine :: Position -> Int -> IO ()
perftLine pos d = do
  t0 <- getMonotonicTime
  n <- evaluate (perft d pos)
  t1 <- getMonotonicTime
  printf "perft %d: %d (%.3f s)\n" d n (t1 - t0)

playoutCmd :: String -> String -> IO ()
playoutCmd s b = do
  seed <- readArg "SEED" s
  bound <- readArg "BOUND" b
  let (res, ms) = playoutMoves bound (mkGen seed) startPosition
  BL.putStrLn (encodeRecord (recordFromPlayout "random" "random" res ms))

-- | Regenerate the golden files. One JSON value per line, so a change shows
-- up as a readable diff.
golden :: FilePath -> IO ()
golden dir = do
  perfts <- either die' pure (traverse computeGoldenPerft goldenPositions)
  writeLines (dir ++ "/perft.json") perfts
  writeLines (dir ++ "/playouts.json") (map computeGoldenPlayout playoutSeeds)
  putStrLn ("wrote " ++ dir ++ "/perft.json and " ++ dir ++ "/playouts.json")
  where
    writeLines :: ToJSON a => FilePath -> [a] -> IO ()
    writeLines path xs =
      BL.writeFile path (BL.concat ["[\n", BL.intercalate ",\n" (map encode xs), "\n]\n"])
