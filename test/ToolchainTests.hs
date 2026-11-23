-- | E01-S01 (#5): the toolchain runs QuickCheck properties and HUnit tests.
module ToolchainTests (tests) where

import Data.Version (showVersion)
import System.Info (compilerName, fullCompilerVersion)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

-- | The toolchain tests. With @demoFailure@ set (environment variable
-- @PYLOS_DEMO_FAILURE=1@) a deliberately false property is added, to show
-- that a failing property makes @cabal test@ exit non-zero and print the
-- counterexample.
tests :: Bool -> TestTree
tests demoFailure =
  testGroup "E01-S01 toolchain" $
    [ testProperty "QuickCheck runs: reversing twice is the identity" $
        \xs -> reverse (reverse xs) === (xs :: [Int])
    , testCase "HUnit runs: the compiler is the pinned GHC 9.10.1" $
        (compilerName, showVersion fullCompilerVersion) @?= ("ghc", "9.10.1")
    ]
      ++ [ testProperty "DEMO (deliberately false): every list is its own reverse" $
             \xs -> xs === reverse (xs :: [Int])
         | demoFailure
         ]
