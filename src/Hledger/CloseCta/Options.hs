{-# LANGUAGE OverloadedStrings #-}

-- | Options for the close-cta command and their defaults.
module Hledger.CloseCta.Options (
    CtaOpts (..),
    defaultBase,
    earnedAcctTemplate,
    revaluedAcctTemplate,
    expandAcctTemplate,
    defaultPeriod,
) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day, toGregorian)
import Hledger (AccountName, CommoditySymbol, Period (YearPeriod))

-- | Fully resolved options: period bounds computed, account templates expanded.
data CtaOpts = CtaOpts
    { ctaPeriodStart :: Day
    -- ^ first day of the closed period
    , ctaPeriodNext :: Day
    -- ^ first day after the closed period; closing entries carry this date
    , ctaLabel :: Text
    -- ^ period label used in account names and descriptions (@2024@, @2024Q3@, ...)
    , ctaBase :: CommoditySymbol
    -- ^ base (functional) currency layers are pinned to
    , ctaEarnedAcct :: AccountName
    -- ^ equity account receiving the retained-earnings sweep
    , ctaRevaluedAcct :: AccountName
    -- ^ equity account receiving the CTA revaluation
    }
    deriving (Show, Eq)

defaultBase :: CommoditySymbol
defaultBase = "USD"

earnedAcctTemplate :: Text
earnedAcctTemplate = "Equity:Accumulated:{period}:Earned"

revaluedAcctTemplate :: Text
revaluedAcctTemplate = "Equity:Accumulated:{period}:Revalued"

-- | Substitute @{period}@ in an account name template.
expandAcctTemplate :: Text -> Text -> AccountName
expandAcctTemplate = T.replace "{period}"

-- | Default period to close: the last complete calendar year.
defaultPeriod :: Day -> Period
defaultPeriod d = let (y, _, _) = toGregorian d in YearPeriod (y - 1)
