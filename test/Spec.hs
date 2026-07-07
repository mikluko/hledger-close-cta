module Main (main) where

import Hledger.CloseCta qualified as CloseCta
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
    testGroup
        "hledger-close-cta"
        [ testCase "version is set" $
            assertBool "non-empty version" (not (null CloseCta.version))
        ]
