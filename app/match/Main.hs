-- | @pylos-match@: play a match between two bots and print the score (S3).
--
-- > pylos-match BOT_A BOT_B [GAMES] [PLYCAP] [RECORD_DIR]
--
-- The bots swap colours every game, so neither always moves first. Game i
-- uses seed i, so a match can be repeated exactly. A game that reaches the
-- ply cap is a draw (D12). With RECORD_DIR, every game is written there as a
-- JSON record (D09) that @pylos-ref replay@ can check.
module Main (main) where

import Control.Monad (foldM, forM_)
import qualified Data.ByteString.Lazy.Char8 as BL
import GHC.Clock (getMonotonicTime)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hFlush, hPutStrLn, stderr, stdout)
import Text.Printf (printf)
import Text.Read (readMaybe)

import Pylos.Bot
import Pylos.Match
import Pylos.Reference.Board (Colour (..))
import Pylos.Reference.Random (mkGen)
import Pylos.Reference.Record (encodeRecord)

main :: IO ()
main = do
  args <- getArgs
  (a, b, n, cap, dir) <- case args of
    [x, y] -> pure (x, y, "10", "300", Nothing)
    [x, y, k] -> pure (x, y, k, "300", Nothing)
    [x, y, k, c] -> pure (x, y, k, c, Nothing)
    [x, y, k, c, d] -> pure (x, y, k, c, Just d)
    _ -> die' "usage: pylos-match BOT_A BOT_B [GAMES] [PLYCAP] [RECORD_DIR]\nbots: random, greedy:reserve=10,free=1, alphabeta:depth=3, mcts:iterations=2000"
  botA <- either (die' . ("bot A: " ++)) pure (parseSpec a)
  botB <- either (die' . ("bot B: " ++)) pure (parseSpec b)
  games <- maybe (die' ("bad GAMES: " ++ n)) pure (readMaybe n)
  plyCap <- maybe (die' ("bad PLYCAP: " ++ cap)) pure (readMaybe cap)
  forM_ dir (createDirectoryIfMissing True)
  printf "A = %s\nB = %s\n" (renderSpec botA) (renderSpec botB)
  (scoreA, scoreB) <- foldM (playOne botA botB plyCap dir) (mempty, mempty) [1 .. games]
  printf "\nA %-28s %d wins, %d losses, %d draws\n" (renderSpec botA) (wins scoreA) (losses scoreA) (draws scoreA)
  printf "B %-28s %d wins, %d losses, %d draws\n" (renderSpec botB) (wins scoreB) (losses scoreB) (draws scoreB)

playOne :: BotSpec -> BotSpec -> Int -> Maybe FilePath -> (MatchScore, MatchScore) -> Int -> IO (MatchScore, MatchScore)
playOne botA botB plyCap dir (sa, sb) i = do
  -- Odd games: A is White. Even games: B is White.
  let aWhite = odd i
      (white, black) = if aWhite then (botA, botB) else (botB, botA)
      colourA = if aWhite then White else Black
      colourB = if aWhite then Black else White
  t0 <- getMonotonicTime
  let game = playGame white black plyCap (mkGen (fromIntegral i))
      res = gameResult game
  t1 <- res `seq` getMonotonicTime
  printf
    "game %3d: A is %-5s  %-14s %3d plies  %.2f s\n"
    i
    (show colourA)
    (describe res)
    (length (gameMoves game))
    (t1 - t0)
  hFlush stdout
  forM_ dir $ \d ->
    BL.writeFile (d ++ "/game-" ++ show i ++ ".json") (encodeRecord (gameRecord white black game))
  pure (sa <> scoreGame colourA res, sb <> scoreGame colourB res)
  where
    describe (WonBy c) = show c ++ " wins"
    describe DrawByCap = "draw (cap)"

die' :: String -> IO a
die' msg = hPutStrLn stderr msg >> exitFailure
