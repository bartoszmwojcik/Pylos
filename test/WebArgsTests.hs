-- | E05-S01 (#31): the @pylos-web@ argument parser, and E07-S01 (#44):
-- how it finds its web folder (D26).
module WebArgsTests (tests) where

import Data.Functor.Identity (runIdentity)
import Data.List (isInfixOf)
import Test.Tasty
import Test.Tasty.HUnit

import WebArgs

tests :: TestTree
tests =
  testGroup
    "E05-S01 pylos-web arguments"
    [ testCase "no arguments: loopback, port 8080, no WEB_DIR" $
        parseArgs [] @?= Right (Options 8080 Nothing LoopbackOnly)
    , testCase "positional PORT and WEB_DIR still work" $ do
        parseArgs ["9000"] @?= Right (Options 9000 Nothing LoopbackOnly)
        parseArgs ["9000", "static"] @?= Right (Options 9000 (Just "static") LoopbackOnly)
    , testCase "--lan alone switches to the home network" $
        parseArgs ["--lan"] @?= Right (Options 8080 Nothing HomeNetwork)
    , testCase "--lan may come before, between or after the positionals" $ do
        let want = Right (Options 9000 (Just "static") HomeNetwork)
        parseArgs ["--lan", "9000", "static"] @?= want
        parseArgs ["9000", "--lan", "static"] @?= want
        parseArgs ["9000", "static", "--lan"] @?= want
    , testCase "an unparsable port falls back to 8080 as before" $
        parseArgs ["abc"] @?= Right (Options 8080 Nothing LoopbackOnly)
    , testCase "an unknown option is rejected" $
        parseArgs ["--wan"] @?= Left "unknown option --wan"
    , testCase "too many positionals are rejected" $
        parseArgs ["1", "d", "x"] @?= Left "too many arguments"
    , testCase "bind hosts" $ do
        bindHost LoopbackOnly @?= "127.0.0.1"
        bindHost HomeNetwork @?= "0.0.0.0"
    , webDirTests
    ]

-- | D26: without WEB_DIR, @./web@ wins, then @web@ next to the executable,
-- then @/usr/share/pylos/web@. The folder check is a pure list of the
-- folders that exist, so no test touches the disk.
webDirTests :: TestTree
webDirTests =
  testGroup
    "E07-S01 pylos-web web folder (D26)"
    [ testCase "the candidates, in order" $
        webDirCandidates "/opt/pylos" @?= ["web", "/opt/pylos/web", "/usr/share/pylos/web"]
    , testCase "a source checkout: ./web is served, as before" $
        resolve ["web", "/opt/pylos/web", "/usr/share/pylos/web"] Nothing @?= Right "web"
    , testCase "the unpacked .tar.gz: web next to the executable" $
        resolve ["/opt/pylos/web", "/usr/share/pylos/web"] Nothing @?= Right "/opt/pylos/web"
    , testCase "the .deb: /usr/share/pylos/web" $
        resolve ["/usr/share/pylos/web"] Nothing @?= Right "/usr/share/pylos/web"
    , testCase "an explicit WEB_DIR is used as given, even when it is missing" $ do
        resolve ["web"] (Just "static") @?= Right "static"
        resolve [] (Just "static") @?= Right "static"
    , testCase "no folder found: the error names every folder tried" $
        case resolve [] Nothing of
          Right d -> assertFailure ("expected an error, got " ++ d)
          Left err ->
            mapM_
              (\d -> assertBool ("error should name " ++ d ++ ": " ++ err) (d `isInfixOf` err))
              (webDirCandidates "/opt/pylos")
    ]
  where
    resolve existing = runIdentity . resolveWebDir (pure . (`elem` existing)) "/opt/pylos"
