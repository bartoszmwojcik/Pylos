-- | Writing a bot as one line of text (D15): @kind@ or @kind:knob=value@.
--
-- > random
-- > greedy:reserve=10,free=1
-- > alphabeta:depth=3
-- > mcts:iterations=2000
--
-- Each bot has at most one knob (D15, "fewer knobs"). For greedy the knob
-- is the pair of evaluation weights, so it is written as two settings.
module Pylos.Bot.Spec
  ( BotSpec (..)
  , Weights (..)
  , defaultWeights
  , parseSpec
  , renderSpec
  , botKinds
  ) where

import Data.Char (isDigit, isSpace)
import Data.List (intercalate)

-- | The weights of the evaluation function (see "Pylos.Bot.Eval").
data Weights = Weights
  { wReserve :: !Int
  -- ^ per ball of reserve advantage
  , wFree :: !Int
  -- ^ per free ball advantage
  }
  deriving (Eq, Show)

-- | The weights alpha-beta always uses, and greedy uses unless told otherwise.
defaultWeights :: Weights
defaultWeights = Weights {wReserve = 10, wFree = 1}

-- | A bot and its knob. D15.
data BotSpec
  = -- | A uniformly random legal move.
    RandomBot
  | -- | The move with the best evaluation one ply ahead.
    GreedyBot !Weights
  | -- | Alpha-beta search to this many plies.
    AlphaBetaBot !Int
  | -- | Monte Carlo tree search with this many iterations.
    MctsBot !Int
  deriving (Eq, Show)

-- | Each bot kind with an example spec and a one-line explanation.
botKinds :: [(String, String, String)]
botKinds =
  [ ("random", "random", "plays a uniformly random legal move")
  , ("greedy", "greedy:reserve=10,free=1", "best move one ply ahead; weights for reserve and free-ball advantage")
  , ("alphabeta", "alphabeta:depth=3", "alpha-beta search; depth 1-6 plies")
  , ("mcts", "mcts:iterations=2000", "Monte Carlo tree search; 1-200000 iterations per move")
  ]

-- | Write a spec in its canonical form.
renderSpec :: BotSpec -> String
renderSpec RandomBot = "random"
renderSpec (GreedyBot w) = "greedy:reserve=" ++ show (wReserve w) ++ ",free=" ++ show (wFree w)
renderSpec (AlphaBetaBot d) = "alphabeta:depth=" ++ show d
renderSpec (MctsBot n) = "mcts:iterations=" ++ show n

-- | Read a spec. Errors name the bad part.
parseSpec :: String -> Either String BotSpec
parseSpec raw = do
  let text = trim raw
      (kind, rest) = break (== ':') text
  settings <- case rest of
    "" -> Right []
    (_ : body) -> traverse parseSetting (splitOn ',' body)
  case kind of
    "random" -> RandomBot <$ only [] settings
    "greedy" -> do
      only ["reserve", "free"] settings
      r <- maybe (Right (wReserve defaultWeights)) (inRange "reserve" (-1000) 1000) (lookup "reserve" settings)
      f <- maybe (Right (wFree defaultWeights)) (inRange "free" (-1000) 1000) (lookup "free" settings)
      Right (GreedyBot (Weights r f))
    "alphabeta" -> do
      only ["depth"] settings
      AlphaBetaBot <$> maybe (Right 3) (inRange "depth" 1 6) (lookup "depth" settings)
    "mcts" -> do
      only ["iterations"] settings
      MctsBot <$> maybe (Right 2000) (inRange "iterations" 1 200000) (lookup "iterations" settings)
    _ ->
      Left
        ( "unknown bot \"" ++ kind ++ "\" (known: "
            ++ intercalate ", " [k | (k, _, _) <- botKinds]
            ++ ")"
        )
  where
    only allowed settings = case [k | (k, _) <- settings, k `notElem` allowed] of
      [] -> Right ()
      (k : _) -> Left ("unknown setting \"" ++ k ++ "\" for this bot")
    inRange name lo hi v
      | v >= lo && v <= hi = Right v
      | otherwise = Left (name ++ "=" ++ show v ++ " is out of range " ++ show lo ++ ".." ++ show hi)

parseSetting :: String -> Either String (String, Int)
parseSetting s = case break (== '=') (trim s) of
  (k, '=' : v)
    | not (null k), Just n <- readInt (trim v) -> Right (trim k, n)
  _ -> Left ("bad setting \"" ++ trim s ++ "\" (expected name=number)")
  where
    readInt ('-' : ds) | not (null ds), all isDigit ds = Just (negate (read ds))
    readInt ds | not (null ds), all isDigit ds, length ds < 10 = Just (read ds)
    readInt _ = Nothing

splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, []) -> [a]
  (a, _ : b) -> a : splitOn c b

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse
