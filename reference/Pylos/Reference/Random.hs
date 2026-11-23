-- | A tiny seeded random number generator (SplitMix64).
--
-- Golden playout files (D11) store the outcome of games played with a
-- given seed. If the random numbers changed, those files would silently
-- go stale. A library generator can change between versions, so the
-- engine carries its own: about 20 lines whose output can never change.
-- See @docs/adr/0018-own-random-generator.md@.
module Pylos.Reference.Random
  ( Gen
  , mkGen
  , nextWord64
  , uniformIndex
  ) where

import Data.Bits (shiftR, xor)
import Data.Word (Word64)

-- | The generator state.
newtype Gen = Gen Word64
  deriving (Eq, Show)

-- | A generator from a seed.
mkGen :: Word64 -> Gen
mkGen = Gen

-- | The next 64 random bits and the new state (SplitMix64, Steele et al.
-- 2014, the same constants as Java's @SplittableRandom@).
nextWord64 :: Gen -> (Word64, Gen)
nextWord64 (Gen s) = (mix s', Gen s')
  where
    s' = s + 0x9e3779b97f4a7c15
    mix z0 =
      let z1 = (z0 `xor` (z0 `shiftR` 30)) * 0xbf58476d1ce4e5b9
          z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94d049bb133111eb
       in z2 `xor` (z2 `shiftR` 31)

-- | A number from 0 to @n - 1@ (for @n > 0@). Uses the remainder, which is
-- very slightly uneven for large @n@. That does not matter for random play.
uniformIndex :: Int -> Gen -> (Int, Gen)
uniformIndex n g = (fromIntegral (w `mod` fromIntegral n), g')
  where
    (w, g') = nextWord64 g
