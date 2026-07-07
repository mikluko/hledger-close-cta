-- | Selection of market rates for a commodity pair.
--
-- Rates come from declared P directives and, optionally, from market
-- prices inferred from transaction costs (hledger's
-- @--infer-market-prices@). Only direct FROM->BASE rates are considered;
-- chained or reverse rates are out of scope for now.
module Hledger.CloseCta.Rates (
    directRates,
    rateOnOrBefore,
    rateFirstAfter,
) where

import Data.Map.Strict qualified as M
import Data.Time (Day)
import Hledger (
    Amount (..),
    CommoditySymbol,
    MarketPrice (..),
    PriceDirective (..),
    amountSetFullPrecisionUpTo,
    nullamt,
 )

-- | All FROM->TO rates from the given P directives and inferred market
-- prices, ascending by date, at most one per day. A declared rate takes
-- precedence over an inferred one on the same day; among declared rates
-- of one day the last one wins, as in hledger.
--
-- Declared amounts keep the style and precision they were written with;
-- inferred ones display at full precision.
directRates ::
    [PriceDirective] ->
    [MarketPrice] ->
    CommoditySymbol ->
    CommoditySymbol ->
    [(Day, Amount)]
directRates declared inferred from to =
    M.toAscList (M.union (byDate declaredRates) (byDate inferredRates))
  where
    -- left-biased union; fromList keeps the last duplicate
    byDate = M.fromList
    declaredRates =
        [ (pddate pd, pdamount pd)
        | pd <- declared
        , pdcommodity pd == from
        , acommodity (pdamount pd) == to
        ]
    inferredRates =
        [ (mpdate mp, inferredAmount mp)
        | mp <- inferred
        , mpfrom mp == from
        , mpto mp == to
        ]
    inferredAmount mp =
        amountSetFullPrecisionUpTo
            Nothing
            nullamt{acommodity = mpto mp, aquantity = mprate mp}

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
