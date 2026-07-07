-- | Selection of market rates from the journal's P directives.
--
-- Only direct FROM->BASE price directives are considered; chained or
-- reverse rates are out of scope for now.
module Hledger.CloseCta.Rates (
    directRates,
    rateOnOrBefore,
    rateFirstAfter,
) where

import Data.List (sortOn)
import Data.Time (Day)
import Hledger (
    Amount (..),
    CommoditySymbol,
    Journal (..),
    PriceDirective (..),
 )

-- | All declared FROM->TO price directives, ascending by date.
-- The returned amounts are the P directives' rate amounts, styled and
-- sized exactly as written in the journal.
directRates :: Journal -> CommoditySymbol -> CommoditySymbol -> [(Day, Amount)]
directRates j from to =
    sortOn
        fst
        [ (pddate pd, pdamount pd)
        | pd <- jpricedirectives j
        , pdcommodity pd == from
        , acommodity (pdamount pd) == to
        ]

-- | Latest rate dated on or before the given day.
rateOnOrBefore :: Day -> [(Day, Amount)] -> Maybe Amount
rateOnOrBefore d = fmap snd . lastMaybe . takeWhile ((<= d) . fst)

-- | Earliest rate dated strictly after the given day.
rateFirstAfter :: Day -> [(Day, Amount)] -> Maybe Amount
rateFirstAfter d = fmap snd . firstMaybe . dropWhile ((<= d) . fst)

firstMaybe :: [a] -> Maybe a
firstMaybe = foldr (\x _ -> Just x) Nothing

lastMaybe :: [a] -> Maybe a
lastMaybe = foldl (\_ x -> Just x) Nothing
