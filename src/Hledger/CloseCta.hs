{-# LANGUAGE OverloadedStrings #-}

-- | Period-end closing with currency translation adjustment.
--
-- Generates a closing journal fragment: retained-earnings sweep,
-- layer pinning to a base currency at period-end rates, and CTA
-- revaluation of live positions (IAS 21 / ASC 830 style).
module Hledger.CloseCta (
    module Hledger.CloseCta.Options,
    CtaError (..),
    renderCtaError,
    closeCta,
    renderTransactions,
) where

import Control.Applicative ((<|>))
import Data.Maybe (fromMaybe, maybeToList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day, addDays)
import Hledger

import Hledger.CloseCta.Options
import Hledger.CloseCta.Rates

-- | Why a closing fragment could not be generated.
newtype CtaError
    = -- | commodities lacking a direct P rate to base on or before the day
      MissingRates [(CommoditySymbol, Day)]
    deriving (Show, Eq)

renderCtaError :: CtaError -> Text
renderCtaError (MissingRates pairs) =
    T.unlines $
        "close-cta: missing market prices (P directives):"
            : [ "  " <> c <> ": no rate on or before " <> T.pack (show d)
              | (c, d) <- pairs
              ]

-- | Generate the closing fragment for a period: sweep, pin, revaluation.
-- Transactions that would have no postings are omitted.
closeCta :: CtaOpts -> Journal -> Either CtaError [Transaction]
closeCta opts j
    | not (null missing) = Left (MissingRates missing)
    | otherwise =
        Right . concat $
            [ maybeToList sweepTxn
            , maybeToList pinTxn
            , maybeToList revalueTxn
            ]
  where
    base = ctaBase opts
    earned = ctaEarnedAcct opts
    revalued = ctaRevaluedAcct opts
    nextday = ctaPeriodNext opts
    -- rate cutoffs: last day of the period, and the day before it starts
    newCutoff = addDays (-1) nextday
    oldCutoff = addDays (-1) (ctaPeriodStart opts)

    -- Sweep: net RX balances through the period end, one posting per
    -- account and commodity, balanced implicitly by the earned layer.
    -- Prior periods' closing entries (dated inside this period) cancel
    -- earlier history, so the sweep captures this period's flows alone.
    sweepBals =
        [ (a, mixedAmountStripCosts b)
        | (a, _, _, b) <- fst (balancesAt (Type [Revenue, Expense]))
        ]
    sweepTxn
        | null sweepBals = Nothing
        | otherwise =
            Just
                nulltransaction
                    { tdate = nextday
                    , tdescription = "retain earnings"
                    , tcomment = "retain:"
                    , tpostings =
                        [ post a (amountSetFullPrecision (negate b))
                        | (a, mb) <- sweepBals
                        , b <- amounts mb
                        ]
                            ++ [implicitPost earned]
                    }

    -- The earned layer receives the negation of the sweep's explicit
    -- postings, i.e. the RX totals themselves.
    layerBal = maSum (map snd sweepBals)
    pinComponents = foreignNonZero layerBal
    pinTxn
        | null pinComponents = Nothing
        | otherwise =
            Just
                nulltransaction
                    { tdate = nextday
                    , tstatus = Cleared
                    , tdescription =
                        "Pin " <> ctaLabel opts <> " layer to base currency"
                    , tpostings =
                        [ post earned (amountSetFullPrecision (negate b) `at` newRate (acommodity b))
                        | b <- pinComponents
                        ]
                            ++ [implicitPost earned]
                    }

    -- Revaluation: each foreign net AL position at the new rate minus the
    -- same position at the old rate. Positive leg at the new rate,
    -- negative at the old; reversing the pair flips gains into losses.
    positions = foreignNonZero (snd (balancesAt (Type [Asset, Liability])))
    revaluePairs =
        [ (b, newRate c, old)
        | b <- positions
        , let c = acommodity b
        , old <- maybeToList (oldRate c)
        , aquantity old /= aquantity (newRate c)
        ]
    revalueTxn
        | null revaluePairs = Nothing
        | otherwise =
            Just
                nulltransaction
                    { tdate = nextday
                    , tstatus = Cleared
                    , tdescription =
                        "Currency translation of live positions, "
                            <> ctaLabel opts
                            <> " (unrealized)"
                    , tpostings =
                        concat
                            [ [ post revalued (amountSetFullPrecision b `at` new)
                              , post revalued (amountSetFullPrecision (negate b) `at` old)
                              ]
                            | (b, new, old) <- revaluePairs
                            ]
                            ++ [implicitPost revalued]
                    }

    -- Historical balances by account through the period end, restricted
    -- to the given account types; the earned layer itself is excluded.
    balancesAt typeq = balanceReport rspec j
      where
        rspec =
            defreportspec
                { _rsReportOpts =
                    defreportopts
                        { balanceaccum_ = Historical
                        , accountlistmode_ = ALFlat
                        }
                , _rsQuery =
                    And
                        [ Date (DateSpan Nothing (Just (Exact nextday)))
                        , typeq
                        , Not (Acct (accountNameToAccountOnlyRegex earned))
                        ]
                }

    foreignNonZero ma =
        [ b
        | b <- amounts (mixedAmountStripCosts ma)
        , acommodity b /= base
        , aquantity b /= 0
        ]

    -- Rate lookups. Every needed commodity must have a rate on or before
    -- the period end; the old rate falls back to the first rate seen
    -- after the previous period, for commodities that appeared during
    -- this one.
    ratesFor c = directRates (jpricedirectives j) inferred c base
      where
        inferred
            | ctaInferRates opts = jinferredmarketprices j
            | otherwise = []
    newRateMay c = rateOnOrBefore newCutoff (ratesFor c)
    newRate c =
        fromMaybe
            (error "closeCta: missing rate slipped past validation")
            (newRateMay c)
    oldRate c =
        rateOnOrBefore oldCutoff rs
            <|> rateFirstAfter oldCutoff (takeWhile ((<= newCutoff) . fst) rs)
      where
        rs = ratesFor c

    needed = map acommodity pinComponents <> map acommodity positions
    missing =
        [ (c, newCutoff)
        | c <- dedup needed
        , Nothing <- [newRateMay c]
        ]

    post a amt = posting{paccount = a, pamount = mixedAmount amt}
    implicitPost a = posting{paccount = a, pamount = missingmixedamt}

dedup :: (Eq a) => [a] -> [a]
dedup = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

-- | Render transactions as journal text, applying the journal's
-- commodity display styles.
renderTransactions :: Journal -> [Transaction] -> Text
renderTransactions j =
    T.concat . map (showTransaction . styleAmounts styles)
  where
    styles = journalCommodityStyles j
