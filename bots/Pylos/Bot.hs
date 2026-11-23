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
module Pylos.Bot
  ( chooseMove
  , module Pylos.Bot.Spec
  ) where

import Data.Bits (popCount)
import Data.List (sortOn)
import Data.Ord (Down (..))

import qualified Pylos.Bitboard as B
import Pylos.Bot.Eval
import Pylos.Bot.Spec
import Pylos.Reference.Random (Gen, nextWord64, uniformIndex)

-- | The bot's move, or 'Nothing' when the game is over.
chooseMove :: BotSpec -> Gen -> B.BPosition -> Maybe (B.BMove, Gen)
chooseMove spec g p = case B.legalMoves p of
  [] -> Nothing
  moves -> Just $ case spec of
    RandomBot -> pick moves g
    GreedyBot w -> greedy w moves g p
    AlphaBetaBot d -> alphaBeta d moves g p
    MctsBot n -> mcts n moves g p

pick :: [a] -> Gen -> (a, Gen)
pick xs g = let (i, g') = uniformIndex (length xs) g in (xs !! i, g')

-- ---------------------------------------------------------------------------
-- Greedy

-- | Evaluate each move's result from the mover's side and keep a best one.
-- Ties are broken at random, so two greedy bots do not repeat one game.
greedy :: Weights -> [B.BMove] -> Gen -> B.BPosition -> (B.BMove, Gen)
greedy w moves g p = pick best g
  where
    -- The child is evaluated for the opponent (who moves next); negate it.
    scored = [(negate (evaluate w (B.applyMove m p)), m) | m <- moves]
    top = maximum (map fst scored)
    best = [m | (s, m) <- scored, s == top]

-- ---------------------------------------------------------------------------
-- Alpha-beta

-- | Negamax with alpha-beta pruning. The root moves are shuffled first, so
-- among equally good moves a random one is chosen.
alphaBeta :: Int -> [B.BMove] -> Gen -> B.BPosition -> (B.BMove, Gen)
alphaBeta depth moves g p = (bestMove, g')
  where
    (shuffled, g') = shuffle moves g
    (bestMove, _) = foldl' step (firstOf shuffled, negate inf) (ordered shuffled)
    step (bm, alpha) m =
      let score = negate (search (depth - 1) (negate inf) (negate alpha) (B.applyMove m p))
       in if score > alpha then (m, score) else (bm, alpha)
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
mcts :: Int -> [B.BMove] -> Gen -> B.BPosition -> (B.BMove, Gen)
mcts n moves g0 p = (best, gEnd)
  where
    root0 = Node 0 0 [] moves
    (root, gEnd) = loop n root0 g0
    loop 0 r g = (r, g)
    loop k r g = let (r', _, g') = iterateNode g p r in loop (k - 1 :: Int) r' g'
    best = case nChildren root of
      [] -> firstOf moves
      cs -> fst (foldr1 (\a b -> if nVisits (snd a) >= nVisits (snd b) then a else b) cs)

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
