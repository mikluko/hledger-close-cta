module Main (main) where

import Hledger.CloseCta qualified as CloseCta

main :: IO ()
main = putStrLn ("hledger-close-cta " <> CloseCta.version <> " (not implemented yet)")
