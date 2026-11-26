-- | Command-line parsing for @pylos-web@, kept pure so it can be tested
-- (E05-S01, D20), and the choice of the web folder (E07-S01, D26).
--
-- > pylos-web [--lan] [PORT] [WEB_DIR]
--
-- The positional arguments keep their old meaning. @--lan@ may stand
-- anywhere among them. When WEB_DIR is left out, 'resolveWebDir' picks the
-- folder (D26).
module WebArgs
  ( Options (..)
  , Bind (..)
  , parseArgs
  , bindHost
  , webDirCandidates
  , resolveWebDir
  ) where

import Data.List (intercalate, partition)
import System.FilePath ((</>))
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
  , optWebDir :: Maybe FilePath
  -- ^ The WEB_DIR argument, or 'Nothing' when it was left out. Then
  -- 'resolveWebDir' chooses the folder (D26).
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
                [] -> mk 8080 Nothing
                [p] -> mk (portOf p) Nothing
                [p, d] -> mk (portOf p) (Just d)
                _ -> Left "too many arguments"
  where
    isFlag a = take 2 a == "--"

-- | Where @pylos-web@ looks for its web files when WEB_DIR is left out, in
-- order (D26). The argument is the folder that holds the running executable.
--
-- 1. @web@ in the current folder: a source checkout, as before E07-S01.
-- 2. @web@ next to the executable: the unpacked @.tar.gz@.
-- 3. @/usr/share/pylos/web@: where the @.deb@ package installs it.
webDirCandidates :: FilePath -> [FilePath]
webDirCandidates exeDir = ["web", exeDir </> "web", "/usr/share/pylos/web"]

-- | Choose the web folder (D26). An explicit WEB_DIR is used as given, even
-- when it does not exist, as before. Otherwise the first of
-- 'webDirCandidates' that exists wins. When none exists, the error names
-- every folder that was tried.
--
-- The folder check is passed in, so the order is tested without touching
-- the disk; @Main@ passes @doesDirectoryExist@.
resolveWebDir :: Monad m => (FilePath -> m Bool) -> FilePath -> Maybe FilePath -> m (Either String FilePath)
resolveWebDir _ _ (Just dir) = pure (Right dir)
resolveWebDir exists exeDir Nothing = go candidates
  where
    candidates = webDirCandidates exeDir
    go [] =
      pure (Left ("no web folder found; tried " ++ intercalate ", " candidates ++ ". Pass WEB_DIR, for example: pylos-web 8080 path/to/web"))
    go (d : ds) = do
      ok <- exists d
      if ok then pure (Right d) else go ds
