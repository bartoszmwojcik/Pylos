-- | Command-line parsing for @pylos-web@, kept pure so it can be tested
-- (E05-S01, D20).
--
-- > pylos-web [--lan] [PORT] [WEB_DIR]
--
-- The positional arguments keep their old meaning. @--lan@ may stand
-- anywhere among them.
module WebArgs
  ( Options (..)
  , Bind (..)
  , parseArgs
  , bindHost
  ) where

import Data.List (partition)
import Text.Read (readMaybe)

-- | Where the server listens.
data Bind
  = -- | 127.0.0.1 only: the default (N05).
    LoopbackOnly
  | -- | 0.0.0.0: every interface, so the home network can reach it (D20).
    HomeNetwork
  deriving (Eq, Show)

data Options = Options
  { optPort :: Int
  , optWebDir :: FilePath
  , optBind :: Bind
  }
  deriving (Eq, Show)

-- | The host string handed to warp.
bindHost :: Bind -> String
bindHost LoopbackOnly = "127.0.0.1"
bindHost HomeNetwork = "0.0.0.0"

-- | Parse the arguments. An unknown @--flag@ or too many positionals is an
-- error message. As before this change, a PORT that is not a number falls
-- back to 8080 instead of failing.
parseArgs :: [String] -> Either String Options
parseArgs args =
  case partition isFlag args of
    (flags, positional)
      | (bad : _) <- filter (/= "--lan") flags -> Left ("unknown option " ++ bad)
      | otherwise ->
          let bind = if "--lan" `elem` flags then HomeNetwork else LoopbackOnly
              mk port dir = Right (Options port dir bind)
              portOf p = maybe 8080 id (readMaybe p)
           in case positional of
                [] -> mk 8080 "web"
                [p] -> mk (portOf p) "web"
                [p, d] -> mk (portOf p) d
                _ -> Left "too many arguments"
  where
    isFlag a = take 2 a == "--"
