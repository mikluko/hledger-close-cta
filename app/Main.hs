{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text qualified as T
import Data.Text.IO qualified as T
import Hledger
import Hledger.Cli.Script

import Hledger.CloseCta

cmdmode :: Mode RawOpts
cmdmode =
    hledgerCommandMode
        ( unlines
            [ "close-cta"
            , "Print period-end closing entries with currency translation"
            , "adjustment: retained-earnings sweep, layer pinning to the base"
            , "currency, and CTA revaluation of live positions."
            , ""
            , "The closed period comes from the standard -b/-e/-p options and"
            , "must be bounded; default is the last complete calendar year."
            , ""
            , "Usage: hledger-close-cta [OPTS]"
            , "or:    hledger close-cta -- [OPTS]"
            ]
        )
        [ flagReq
            ["base"]
            (\v o -> Right $ setopt "base" v o)
            "CUR"
            ("base currency layers are pinned to (default: " <> T.unpack defaultBase <> ")")
        , flagReq
            ["earned-acct"]
            (\v o -> Right $ setopt "earned-acct" v o)
            "TPL"
            ("earned layer account template (default: " <> T.unpack earnedAcctTemplate <> ")")
        , flagReq
            ["revalued-acct"]
            (\v o -> Right $ setopt "revalued-acct" v o)
            "TPL"
            ("revalued layer account template (default: " <> T.unpack revaluedAcctTemplate <> ")")
        ]
        [generalflagsgroup1]
        []
        ([], Nothing)

main :: IO ()
main = do
    opts@CliOpts{rawopts_ = raw, reportspec_ = rspec} <- getHledgerCliOpts cmdmode
    withJournal opts $ \j -> do
        ctaopts <- either bail pure (resolveOpts raw rspec)
        case closeCta ctaopts j of
            Left e -> bail (T.unpack (renderCtaError e))
            Right ts -> T.putStr (renderTransactions j ts)
  where
    bail msg = hPutStr stderr msg >> exitFailure

-- | Resolve the closed period and account names from CLI options.
resolveOpts :: RawOpts -> ReportSpec -> Either String CtaOpts
resolveOpts raw rspec = do
    let closedp = case period_ (_rsReportOpts rspec) of
            PeriodAll -> defaultPeriod (_rsDay rspec)
            p -> p
        span' = periodAsDateSpan closedp
        label = showPeriod closedp
        base = maybe defaultBase T.pack (maybestringopt "base" raw)
        earnedT = maybe earnedAcctTemplate T.pack (maybestringopt "earned-acct" raw)
        revaluedT = maybe revaluedAcctTemplate T.pack (maybestringopt "revalued-acct" raw)
    (start, next) <- case (spanStart span', spanEnd span') of
        (Just s, Just e) -> Right (s, e)
        _ ->
            Left
                "close-cta: the closed period must be bounded on both sides\n\
                \(use -p PERIOD, or -b and -e together)\n"
    Right
        CtaOpts
            { ctaPeriodStart = start
            , ctaPeriodNext = next
            , ctaLabel = label
            , ctaBase = base
            , ctaEarnedAcct = expandAcctTemplate label earnedT
            , ctaRevaluedAcct = expandAcctTemplate label revaluedT
            , ctaInferRates = infer_prices_ (_rsReportOpts rspec)
            }
