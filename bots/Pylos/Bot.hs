{-# LANGUAGE BangPatterns #-}

-- | The bots (S3, D15). Every bot is a pure function from a position and a
-- random generator to a move, so a game is reproducible from its seed.
--
-- * __random__: a uniformly random legal move.
-- * __greedy__: tries every move and keeps the one whose resulting
--   position evaluates best ("Pylos.Bot.Eval"). It looks one ply ahead.
-- * __alphabeta__: looks @depth@ plies ahead, assuming the opponent also
--   plays its best (minimax), and skips branches that cannot change the
--   result (alpha-beta pruning). Same evaluation as greedy.
-- * __mcts__: Monte Carlo tree search. It does not use the evaluation at
--   all: it plays many random games and grows a tree towards the moves
--   that win most often.
--
-- All bots use the bitboard engine for speed. See
-- @docs/adr/0022-bots.md@.
--
-- For a training game (D22) a bot can also say how it scores the position:
-- 'chooseMoveScored' returns the move with a 'BotScore', and
-- 'scorePosition' scores a position the bot did not move into (the one
-- after the human's move). Every score is from White's point of view. See
-- @docs/adr/0026-bot-scores.md@.
module Pylos.Bot
  ( chooseMove
  , chooseMoveScored
  , scorePosition
  , BotScore (..)
  , winScore
  , module Pylos.Bot.Spec
  ) where

import Data.Bits (popCount)
import Data.List (sortOn)
import Data.Ord (Down (..))

import qualified Pylos.Bitboard as B
import Pylos.Bot.Eval
import Pylos.Bot.Spec
import Pylos.Reference.Random (Gen, nextWord64, uniformIndex)

-- | How a bot scores a position, for a training game (D22).
--
-- __Every score is from White's point of view__: a higher number is better
-- for White, whichever side the bot plays. So the screen can show one
-- number that means the same thing all game long (ADR 0026).
data BotScore
  = -- | The shared evaluation ("Pylos.Bot.Eval") for greedy, or the
    -- alpha-beta search score at its depth. Positive is good for White.
    -- A value of 'winScore' or more (or @-winScore@ or less) is a won (or
    -- lost) game for White; alpha-beta adds the plies it had left, so a
    -- larger value is a sooner win.
    EvalScore !Int
  | -- | MCTS: the share of its random games that White won through the
    -- move the bot chose, from 0 to 1 (a capped game counts as half).
    WinRate !Double
  | -- | The bot has no score: random always, MCTS for a position it did
    -- not search ('scorePosition').
    NoScore
  deriving (Eq, Show)

-- | The bot's move, or 'Nothing' when the game is over.
--
-- It is 'chooseMoveScored' with the score dropped. Because the score is
-- never forced, it is never computed; and the move and generator are the
-- same ones 'chooseMoveScored' returns, whether or not a caller asks for
-- the score.
chooseMove :: BotSpec -> Gen -> B.BPosition -> Maybe (B.BMove, Gen)
chooseMove spec g p = dropScore <$> chooseMoveScored spec g p
  where
    dropScore (m, g', _) = (m, g')

-- | The bot's move, the next generator and the bot's score of the
-- position its move leads to (D22). 'Nothing' when the game is over.
--
-- * random: 'NoScore'.
-- * greedy: the evaluation of the position after its move.
-- * alpha-beta: its search score of the chosen move.
-- * mcts: the 'WinRate' of the chosen move.
chooseMoveScored :: BotSpec -> Gen -> B.BPosition -> Maybe (B.BMove, Gen, BotScore)
chooseMoveScored spec g p = case B.legalMoves p of
  [] -> Nothing
  moves -> Just $ case spec of
    RandomBot -> let (m, g') = pick moves g in (m, g', NoScore)
    GreedyBot w -> let (m, g', s) = greedy w moves g p in (m, g', EvalScore (forWhite p s))
    AlphaBetaBot d -> let (m, g', s) = alphaBeta d moves g p in (m, g', EvalScore (forWhite p s))
    MctsBot n -> mcts n moves g p

-- | How the bot scores a position it did not choose: the one after the
-- human's move, with the bot to move (D22). Pure, and it uses no random
-- numbers, so it cannot change which move the bot then plays.
--
-- * greedy: the evaluation of this position.
-- * alpha-beta: the search score of this position at its depth. That is
--   the score 'chooseMoveScored' then reports for its own move.
-- * mcts, random: 'NoScore'. MCTS only scores the move it chose; scoring
--   a position would need a search of its own (ADR 0026).
scorePosition :: BotSpec -> B.BPosition -> BotScore
scorePosition spec p = case spec of
  RandomBot -> NoScore
  GreedyBot w -> EvalScore (forWhite p (evaluate w p))
  AlphaBetaBot d -> EvalScore (forWhite p (search d (negate inf) inf p))
  MctsBot _ -> NoScore

-- | Turn a score for the player to move in @p@ into a score for White.
forWhite :: B.BPosition -> Int -> Int
forWhite p s = if B.bWhiteToMove p then s else negate s

pick :: [a] -> Gen -> (a, Gen)
pick xs g = let (i, g') = uniformIndex (length xs) g in (xs !! i, g')

-- ---------------------------------------------------------------------------
-- Greedy

-- | Evaluate each move's result from the mover's side and keep a best one.
-- Ties are broken at random, so two greedy bots do not repeat one game.
-- Also returns the best score, for the mover.
greedy :: Weights -> [B.BMove] -> Gen -> B.BPosition -> (B.BMove, Gen, Int)
greedy w moves g p = let (m, g') = pick best g in (m, g', top)
  where
    -- The child is evaluated for the opponent (who moves next); negate it.
    scored = [(negate (evaluate w (B.applyMove m p)), m) | m <- moves]
    top = maximum (map fst scored)
    best = [m | (s, m) <- scored, s == top]

-- ---------------------------------------------------------------------------
-- Alpha-beta

-- | Negamax with alpha-beta pruning. The root moves are shuffled first, so
-- among equally good moves a random one is chosen.
--
-- Also returns the chosen move's score, for the mover. It is exact, not a
-- bound: the first move's score is always above @-inf@, and a later move
-- only replaces it when its score is higher, and then that score is
-- inside the window it was searched with.
alphaBeta :: Int -> [B.BMove] -> Gen -> B.BPosition -> (B.BMove, Gen, Int)
alphaBeta depth moves g p = (bestMove, g', bestScore)
  where
    (shuffled, g') = shuffle moves g
    (bestMove, bestScore) = foldl' step (firstOf shuffled, negate inf) (ordered shuffled)
    step (bm, alpha) m =
      let score = negate (search (depth - 1) (negate inf) (negate alpha) (B.applyMove m p))
       in if score > alpha then (m, score) else (bm, alpha)

-- | A bound beyond any score 'search' returns (those stay within
-- @winScore + depth@).
inf :: Int
inf = winScore * 2

-- | The value of a position for the player to move, searching @d@ plies.
-- @alpha@ is what we can already reach; @beta@ is what the opponent will
-- allow. Once a move reaches @beta@ the opponent will avoid this position,
-- so the other moves need not be searched.
search :: Int -> Int -> Int -> B.BPosition -> Int
search d alpha0 beta p
  | B.reserveToMove p == 0 = negate winScore - d -- lost; losing later is better
  | d <= 0 = evaluate defaultWeights p
  | otherwise = go alpha0 (ordered (B.legalMoves p))
  where
    go alpha [] = alpha
    go alpha (m : ms) =
      let score = negate (search (d - 1) (negate beta) (negate alpha) (B.applyMove m p))
          alpha' = max alpha score
       in if alpha' >= beta then alpha' else go alpha' ms

-- | Search take-backs first: they keep balls, so they are often best, and
-- a good move found early lets alpha-beta skip more of the tree.
ordered :: [B.BMove] -> [B.BMove]
ordered = sortOn (Down . popCount . B.bmTakeBack)

-- | A random permutation (Fisher-Yates on a list, which is fine here).
shuffle :: [a] -> Gen -> ([a], Gen)
shuffle [] g = ([], g)
shuffle xs g =
  let (i, g1) = uniformIndex (length xs) g
   in case splitAt i xs of
        (before, x : after) ->
          let (rest, g2) = shuffle (before ++ after) g1 in (x : rest, g2)
        (before, []) -> (before, g1) -- unreachable: i < length xs

-- | The first element of a list that is known not to be empty.
firstOf :: [a] -> a
firstOf (x : _) = x
firstOf [] = error "firstOf: empty list (a bot was called without legal moves)"

-- ---------------------------------------------------------------------------
-- MCTS

-- | A node of the search tree. @nWins@ is counted for the player who moved
-- /into/ this node, so a parent picks the child with the best ratio.
data Node = Node
  { nVisits :: !Int
  , nWins :: !Double
  , nChildren :: [(B.BMove, Node)]
  , nUntried :: [B.BMove]
  }

-- | Run @n@ iterations from the root, then play the most visited move.
--
-- One iteration: walk down the tree choosing children by UCT (good ratio,
-- plus a bonus for children seldom tried), add one new child, play a random
-- game from it, and add the result to every node on the path.
--
-- The score is the chosen child's win ratio. The child counts wins for
-- the player who moved into it, the bot, so it is turned round for White.
mcts :: Int -> [B.BMove] -> Gen -> B.BPosition -> (B.BMove, Gen, BotScore)
mcts n moves g0 p = (best, gEnd, score)
  where
    root0 = Node 0 0 [] moves
    (root, gEnd) = loop n root0 g0
    loop 0 r g = (r, g)
    loop k r g = let (r', _, g') = iterateNode g p r in loop (k - 1 :: Int) r' g'
    (best, score) = case nChildren root of
      [] -> (firstOf moves, NoScore) -- only when n < 1: an iteration always adds a child
      cs ->
        let (m, c) = foldr1 (\a b -> if nVisits (snd a) >= nVisits (snd b) then a else b) cs
            ratio = nWins c / fromIntegral (nVisits c)
         in (m, WinRate (if B.bWhiteToMove p then ratio else 1 - ratio))

-- | One iteration below a node. Returns the updated node and the result of
-- the random game for the player to move at this node (1 win, 0 loss,
-- 0.5 capped).
iterateNode :: Gen -> B.BPosition -> Node -> (Node, Double, Gen)
iterateNode g p node
  | B.reserveToMove p == 0 = (record 0, 0, g) -- the player to move has lost
  | (m : rest) <- nUntried node =
      let p' = B.applyMove m p
          (v', g') = rollout g p'
          v = 1 - v'
          child = Node 1 v [] (B.legalMoves p')
       in ((record v) {nChildren = (m, child) : nChildren node, nUntried = rest}, v, g')
  | otherwise =
      let (i, (m, child)) = selectUct (nVisits node) (nChildren node)
          (child', v', g') = iterateNode g (B.applyMove m p) child
          v = 1 - v'
          children' = replaceAt i (m, child') (nChildren node)
       in ((record v) {nChildren = children'}, v, g')
  where
    -- The node's own statistics are for the player who moved into it.
    record v = node {nVisits = nVisits node + 1, nWins = nWins node + (1 - v)}

-- | The child with the highest UCT score: win ratio + c * sqrt(ln N / n),
-- with c = sqrt 2.
selectUct :: Int -> [(B.BMove, Node)] -> (Int, (B.BMove, Node))
selectUct parentVisits cs = foldr1 better (zip [0 ..] cs)
  where
    better a b = if score a >= score b then a else b
    score (_, (_, c)) =
      nWins c / fromIntegral (nVisits c)
        + sqrt 2 * sqrt (log (fromIntegral parentVisits) / fromIntegral (nVisits c))

replaceAt :: Int -> a -> [a] -> [a]
replaceAt i x xs = take i xs ++ [x] ++ drop (i + 1) xs

-- | A random game from a position, at most 200 plies. The result is for
-- the player to move at the start.
rollout :: Gen -> B.BPosition -> (Double, Gen)
rollout g0 p0 = go (200 :: Int) g0 p0
  where
    starter = B.bWhiteToMove p0
    go !k g p
      | B.reserveToMove p == 0 = (if B.bWhiteToMove p == starter then 0 else 1, g)
      | k == 0 = (0.5, g)
      | otherwise = case B.legalMoves p of
          [] -> (0.5, g)
          ms ->
            let (w, g') = nextWord64 g
                m = ms !! fromIntegral (w `mod` fromIntegral (length ms))
             in go (k - 1) g' (B.applyMove m p)
