{-# LANGUAGE OverloadedStrings #-}

-- | Tests of the reference engine, grouped by backlog story.
module ReferenceTests (tests) where

import Data.List (isInfixOf, nub, sort)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import Gen
import Pylos.Reference.Board
import Pylos.Reference.Move
import Pylos.Reference.Notation
import Pylos.Reference.Perft
import Pylos.Reference.Playout
import Pylos.Reference.Random (mkGen)
import Pylos.Reference.Record
import Pylos.Reference.Rules
import Pylos.Reference.Symmetry

tests :: TestTree
tests =
  testGroup
    "Reference engine"
    [boardTests, moveTests, shapeTests, notationTests, perftTests]

-- ---------------------------------------------------------------------------
-- E02-S01 (#7): board and positions

boardTests :: TestTree
boardTests =
  testGroup
    "E02-S01 board (R08)"
    [ testCase "there are 30 squares: 16 + 9 + 4 + 1" $ do
        length allPositions @?= 30
        map (length . positionsOn) [A, B, C, D] @?= [16, 9, 4, 1]
    , testProperty "supports of a b-d square are the 4 squares beneath it" $
        forAll (elements [p | p <- allPositions, posLevel p /= A]) $ \p ->
          -- The geometry formula, written independently: the squares one
          -- level down whose row and column are within (r..r+1, c..c+1).
          let expected =
                [ q
                | q <- allPositions
                , posLevel q == pred (posLevel p)
                , posRow q `elem` [posRow p, posRow p + 1]
                , posCol q `elem` [posCol p, posCol p + 1]
                ]
           in sort (supports p) === expected .&&. length expected === 4
    , testCase "level a squares have no supports" $
        all (null . supports) (positionsOn A) @? "a level-a square has a support"
    , testCase "negative: placing on b11 on an empty board is rejected" $ do
        let m = noTakeBack (Place (pos "b11"))
        isLegal m startPosition @?= False
        playMove m startPosition @?= Left "illegal move"
    , testCase "a position is printed level by level" $ do
        let out = renderPosition (afterMoves ["a11", "a12"])
        lines out
          @?= [ "Level a  Level b  Level c  Level d"
              , "W B . .  . . .    . .      ."
              , ". . . .  . . .    . ."
              , ". . . .  . . ."
              , ". . . ."
              , "White to move. Reserve: White 14, Black 14."
              ]
    ]

-- ---------------------------------------------------------------------------
-- E02-S02 (#8): placements, raises, end of game

moveTests :: TestTree
moveTests =
  testGroup
    "E02-S02 moves (R03, R05, D08)"
    [ testProperty "balls on the board plus reserve stay 15 per colour" $
        \(Reachable _ p) -> conjoin [conserved (applyMove m p) | m <- legalMoves p]
    , testProperty "every ball on levels b-d has 4 occupied supports" $
        \(Reachable _ p) -> conjoin [noFloating (applyMove m p) | m <- legalMoves p]
    , testProperty "generated moves have no duplicates (D08)" $
        \(Reachable _ p) -> let ms = legalMoves p in length (nub ms) === length ms
    , testProperty "a game that is not over always has a legal move" $
        \(Reachable _ p) -> isGameOver p || not (null (legalMoves p))
    , testCase "raise a33-b11 is present and leaves the reserve unchanged (R03)" $ do
        let p = afterMoves ["a11", "a12", "a21", "a22", "a33", "a44"]
            m = noTakeBack (Raise (pos "a33") (pos "b11"))
        isLegal m p @? "raise a33-b11 missing"
        whiteReserve (applyMove m p) @?= whiteReserve p
    , testCase "negative: a free ball cannot be raised onto a square it supports (R03)" $ do
        -- a11 is White's, free, and one of b11's supports.
        let p = afterMoves ["a11", "a12", "a21", "a22", "a33", "a44"]
        isFree (board p) (pos "a11") @? "a11 should be free"
        [m | m@(Move (Raise f t) _) <- legalMoves p, f == pos "a11", t == pos "b11"] @?= []
    , testProperty "negative: raises go strictly up, from a free ball, never onto a square it supports" $
        \(Reachable _ p) ->
          conjoin
            [ counterexample (show (from, to)) $
                posLevel to > posLevel from
                  && isFree (board p) from
                  && from `notElem` supports to
            | Move (Raise from to) _ <- legalMoves p
            ]
    , testCase "the player to move with an empty reserve has lost (R05)" $ do
        let p = (mkPosition ["a11"] ["a12"] White) {whiteReserve = 0}
        winner p @?= Just Black
        legalMoves p @?= []
    , testCase "placing the apex ends the game (R05)" $ do
        -- Fill the whole pyramid except d11, White to move with 1 ball left.
        let squaresBelow = filter ((/= D) . posLevel) allPositions
            (ws, bs) = splitAt 14 squaresBelow
            p =
              Position
                (Map.fromList ([(q, White) | q <- ws] ++ [(q, Black) | q <- bs]))
                1
                0
                White
            -- Black's reserve is empty but it is White's turn, so the game is on.
            m = noTakeBack (Place (pos "d11"))
        winner p @?= Nothing
        isLegal m p @? "apex placement missing"
        winner (applyMove m p) @?= Just White
    ]
  where
    conserved p =
      conjoin
        [ ballsOnBoard c p + reserveOf c p === ballsPerPlayer
        | c <- [White, Black]
        ]
    noFloating p =
      conjoin
        [ counterexample (show q) (all (`Map.member` board p) (supports q))
        | q <- Map.keys (board p)
        ]

-- ---------------------------------------------------------------------------
-- E02-S05 (#15): shapes and take-backs

-- | The take-back sets offered with a given action.
takeBacksFor :: Action -> Position -> [Set Pos]
takeBacksFor a p = sort [t | Move a' t <- legalMoves p, a' == a]

-- | Nothing, every single ball, every pair: for balls that are all free.
allUpToTwo :: [String] -> [Set Pos]
allUpToTwo names =
  sort $
    Set.empty
      : [Set.singleton (pos x) | x <- names]
      ++ [Set.fromList [pos x, pos y] | x <- names, y <- names, x < y]

shapeTests :: TestTree
shapeTests =
  testGroup
    "E02-S05 shapes and take-backs (R04, R07, D08, D14)"
    [ testCase "completing a 2x2 square by placing offers 0, 1 or 2 take-backs" $ do
        let p = afterMoves ["a11", "a33", "a12", "a34", "a21", "a43"]
        takeBacksFor (Place (pos "a22")) p @?= allUpToTwo ["a11", "a12", "a21", "a22"]
    , testCase "completing a horizontal row of 4 on level a offers 0-2 take-backs (D14)" $ do
        let p = afterMoves ["a11", "a21", "a12", "a22", "a13", "a23"]
        takeBacksFor (Place (pos "a14")) p @?= allUpToTwo ["a11", "a12", "a13", "a14"]
    , testCase "completing a vertical row of 4 on level a offers 0-2 take-backs (D14)" $ do
        let p = mkPosition ["a12", "a22", "a32"] ["a14", "a24", "a34"] White
        takeBacksFor (Place (pos "a42")) p @?= allUpToTwo ["a12", "a22", "a32", "a42"]
    , testCase "completing a square on level b by raising offers 0-2 take-backs" $ do
        let blackA = ["a11", "a12", "a13", "a21", "a22", "a23", "a31", "a32", "a33"]
            p = mkPosition ["b11", "b12", "b21", "a44"] blackA White
        takeBacksFor (Raise (pos "a44") (pos "b22")) p
          @?= allUpToTwo ["b11", "b12", "b21", "b22"]
    , testCase "completing two shapes at once still allows at most 2 take-backs" $ do
        -- a14 completes the row a11..a14 and the square a13 a14 a23 a24.
        let p = mkPosition ["a11", "a12", "a13", "a23", "a24"] ["a31", "a32", "a33", "a34", "a41"] White
            offered = takeBacksFor (Place (pos "a14")) p
        offered @?= allUpToTwo ["a11", "a12", "a13", "a14", "a23", "a24"]
        all ((<= 2) . Set.size) offered @? "more than 2 take-backs"
    , testCase "taking back x can free y, so {x, y} is offered (R04)" $ do
        -- b11 (White) rests on a11 (White). a11 is free once b11 is gone.
        let p = mkPosition ["a11", "b11", "a33", "a34", "a43"] ["a12", "a21", "a22"] White
            offered = takeBacksFor (Place (pos "a44")) p
        Set.fromList [pos "b11", pos "a11"] `elem` offered @? "{b11, a11} missing"
        Set.singleton (pos "a11") `elem` offered @?= False
    , testCase "negative: a diagonal of 4 on level a is not a shape" $ do
        let p = mkPosition ["a11", "a22", "a33"] ["a12", "a21", "a34"] White
        takeBacksFor (Place (pos "a44")) p @?= [Set.empty]
    , testCase "negative: a row of 3 on level b is not a shape" $ do
        let p =
              mkPosition
                ["a11", "a13", "a22", "a24", "b11", "b12"]
                ["a12", "a14", "a21", "a23"]
                White
        takeBacksFor (Place (pos "b13")) p @?= [Set.empty]
    , testProperty "negative: take-backs are own balls removable in some order" $
        \(Reachable _ p) ->
          conjoin
            [ counterexample (renderMove m) (removableInSomeOrder (toMove p) b' (Set.toList t))
            | m@(Move a t) <- legalMoves p
            , not (Set.null t)
            , let b' = applyAction (toMove p) a (board p)
            ]
    , testProperty "a move with take-backs grows the reserve by their number" $
        \(Reachable _ p) ->
          conjoin
            [ counterexample (renderMove m) $
                reserveOf me (applyMove m p)
                  === reserveOf me p - used a + Set.size t
            | m@(Move a t) <- legalMoves p
            , let me = toMove p
            ]
    , testCase "a take-back without a completed shape is not legal" $ do
        let p = afterMoves ["a11", "a12"]
        isLegal (Move (Place (pos "a13")) (Set.singleton (pos "a11"))) p @?= False
    ]
  where
    used (Place _) = 1
    used (Raise _ _) = 0
    removableInSomeOrder col b balls =
      any (ok col b) (orders balls)
    orders [x, y] = [[x, y], [y, x]]
    orders xs = [xs]
    ok _ _ [] = True
    ok col b (x : xs) =
      Map.lookup x b == Just col && isFree b x && ok col (Map.delete x b) xs

-- ---------------------------------------------------------------------------
-- E02-S03 (#9): notation and game records

notationTests :: TestTree
notationTests =
  testGroup
    "E02-S03 notation and records (D09)"
    [ testProperty "every legal move survives render then parse" $
        \(Reachable _ p) ->
          conjoin [parseMove (renderMove m) === Right m | m <- legalMoves p]
    , testProperty "a playout record replays to the same position and result" $
        \seed -> do
          let (res, ms) = playoutMoves 200 (mkGen seed) startPosition
              record = recordFromPlayout "random" "random" res ms
              expectedFinal = foldl (flip applyMove) startPosition ms
          case decodeRecord (encodeRecord record) of
            Left err -> counterexample err False
            Right back ->
              back === record
                .&&. case replay back of
                  Left err -> counterexample err False
                  Right (final, replayed) ->
                    final === expectedFinal
                      .&&. replayed
                        === ( case recordResult record of
                                ResultCapped -> ResultUnfinished
                                r -> r
                            )
    , testCase "notation examples from D09" $ do
        renderMove (noTakeBack (Place (pos "a23"))) @?= "a23"
        renderMove (noTakeBack (Raise (pos "a11") (pos "b22"))) @?= "a11-b22"
        renderMove (Move (Place (pos "a23")) (Set.fromList [pos "a24", pos "a23"])) @?= "a23 x a23 a24"
        parseMove "a23 x a24 a23" @?= Right (Move (Place (pos "a23")) (Set.fromList [pos "a23", pos "a24"]))
    , testCase "negative: a55 is a parse error naming the token" $
        assertBadToken "a55" (parseMove "a55")
    , testCase "negative: a11-a12 is a parse error naming the token" $
        assertBadToken "a11-a12" (parseMove "a11-a12")
    , testCase "negative: three take-backs are a parse error" $
        assertLeft (parseMove "a11 x a12 a13 a14")
    , testCase "negative: an illegal move in a list names the move and ply" $
        case parseMoves ["a11", "b11"] >>= playMoves startPosition of
          Left err -> ("ply 2" `isInfixOf` err && "b11" `isInfixOf` err) @? err
          Right _ -> assertFailure "accepted an illegal move"
    ]
  where
    assertBadToken tok r = case r of
      Left err -> ("\"" ++ tok ++ "\"") `isInfixOf` err @? err
      Right m -> assertFailure ("parsed as " ++ show m)
    assertLeft r = case r of
      Left _ -> pure ()
      Right m -> assertFailure ("parsed as " ++ show m)

-- ---------------------------------------------------------------------------
-- E02-S04 (#10): perft, symmetry, playouts

perftTests :: TestTree
perftTests =
  testGroup
    "E02-S04 perft and playouts (D08, D12)"
    [ testCase "perft from the start: 16, 240, 3360, 43680 (D08)" $
        [perft d startPosition | d <- [1 .. 4]] @?= [16, 240, 3360, 43680]
    , testCase "divide sums to perft" $
        sum (map snd (divide 3 startPosition)) @?= perft 3 startPosition
    , testProperty "the move count is the same under all 8 symmetries" $
        \(Reachable _ p) ->
          let n = length (legalMoves p)
           in conjoin [length (legalMoves (transformPosition s p)) === n | s <- symmetries]
    , testProperty "symmetric positions have symmetric move sets" $
        \(Reachable _ p) ->
          conjoin
            [ sort (map (transformMove s) (legalMoves p))
                === sort (legalMoves (transformPosition s p))
            | s <- symmetries
            ]
    , testProperty "a bounded playout returns an outcome or Capped within the bound" $
        \seed (Small b) ->
          let bound = b `mod` 400
           in case playout bound (mkGen seed) startPosition of
                Finished _ n -> property (n <= bound)
                Capped n -> n === bound
    ]
  where
    transformMove s (Move a t) = Move (tAction a) (Set.map (transformPos s) t)
      where
        tAction (Place q) = Place (transformPos s q)
        tAction (Raise f q) = Raise (transformPos s f) (transformPos s q)
