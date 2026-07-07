{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Data.Text.IO qualified as T
import Data.Time (Day, fromGregorian)
import System.FilePath ((<.>), (</>))
import Test.Tasty
import Test.Tasty.Golden
import Test.Tasty.HUnit

import Hledger
import Hledger.CloseCta
import Hledger.CloseCta.Rates

main :: IO ()
main =
    defaultMain $
        testGroup
            "hledger-close-cta"
            [ rateTests
            , goldenTests
            , invariantTests
            , signTests
            , sequentialTest
            ]

testdata :: FilePath
testdata = "test" </> "testdata"

yearOpts :: Integer -> CtaOpts
yearOpts y =
    CtaOpts
        { ctaPeriodStart = fromGregorian y 1 1
        , ctaPeriodNext = fromGregorian (y + 1) 1 1
        , ctaLabel = label
        , ctaBase = "USD"
        , ctaEarnedAcct = expandAcctTemplate label earnedAcctTemplate
        , ctaRevaluedAcct = expandAcctTemplate label revaluedAcctTemplate
        }
  where
    label = T.pack (show y)

readFixture :: FilePath -> IO Journal
readFixture name =
    either fail pure
        =<< runExceptT (readJournalFile definputopts (testdata </> name))

-- | Run the closing on a journal, fail the test on error.
runCta :: CtaOpts -> Journal -> IO Text
runCta opts j =
    either (fail . T.unpack . renderCtaError) (pure . renderTransactions j) $
        closeCta opts j

-- | Parse a fixture with a generated fragment appended.
withFragment :: FilePath -> Text -> IO Journal
withFragment name fragment = do
    orig <- T.readFile (testdata </> name)
    readJournal'' (orig <> "\n" <> fragment)

-- | Historical total for a query as of (i.e. strictly before) a day.
balAt :: Journal -> Query -> Day -> MixedAmount
balAt j q d = snd $ balanceReport rspec j
  where
    rspec =
        defreportspec
            { _rsReportOpts =
                defreportopts{balanceaccum_ = Historical, accountlistmode_ = ALFlat}
            , _rsQuery = And [Date (DateSpan Nothing (Just (Exact d))), q]
            }

-- | Value a balance in USD at a date using the journal's P directives.
valueAt :: Journal -> Day -> MixedAmount -> String
valueAt j d =
    showMixedAmount . mixedAmountValueAtDate oracle styles (Just "USD") d
  where
    oracle = journalPriceOracle False j
    styles = journalCommodityStyles j

usdComponent :: MixedAmount -> Quantity
usdComponent ma =
    sum [aquantity b | b <- amounts (mixedAmountStripCosts ma), acommodity b == "USD"]

-- * Rate selection

rateTests :: TestTree
rateTests =
    testGroup
        "rate selection"
        [ testCase "latest on or before cutoff wins" $
            fmap aquantity (rateOnOrBefore (d 6 30) rates) @?= Just 1.2
        , testCase "rate dated the cutoff itself counts" $
            fmap aquantity (rateOnOrBefore (d 3 1) rates) @?= Just 1.2
        , testCase "nothing before the first rate" $
            fmap aquantity (rateOnOrBefore (d 1 1) rates) @?= Nothing
        , testCase "first after cutoff" $
            fmap aquantity (rateFirstAfter (d 3 1) rates) @?= Just 1.5
        , testCase "nothing after the last rate" $
            fmap aquantity (rateFirstAfter (d 12 31) rates) @?= Nothing
        ]
  where
    d = fromGregorian 2024
    rates =
        [ (d 2 1, usdRate 1.1)
        , (d 3 1, usdRate 1.2)
        , (d 9 1, usdRate 1.5)
        ]
    usdRate q = nullamt{acommodity = "USD", aquantity = q}

-- * Golden output

goldenTests :: TestTree
goldenTests =
    testGroup "golden" $
        [ golden name (yearOpts 2024)
        | name <- ["basic", "long-rising", "long-falling", "short-rising", "short-falling"]
        ]
  where
    golden name opts =
        goldenVsString name (testdata </> name <.> "golden") $ do
            j <- readFixture (name <.> "journal")
            LBS.fromStrict . T.encodeUtf8 <$> runCta opts j

-- * Invariants on the basic fixture

invariantTests :: TestTree
invariantTests =
    testGroup
        "invariants (basic fixture)"
        [ testCase "closed layers valued identically at later dates" $ do
            j' <- closedBasic
            let layers = balAt j' (Acct (accountNameToAccountRegex "Equity:Accumulated:2024")) (fromGregorian 2025 1 2)
            valueAt j' (fromGregorian 2025 7 1) layers
                @?= valueAt j' (fromGregorian 2026 12 31) layers
        , testCase "assets and liabilities untouched" $ do
            j <- readFixture "basic.journal"
            j' <- closedBasic
            let end = fromGregorian 2026 12 31
                alq = Type [Asset, Liability]
            showMixedAmount (balAt j' alq end) @?= showMixedAmount (balAt j alq end)
        , testCase "closed year's income statement unaffected" $ do
            j <- readFixture "basic.journal"
            j' <- closedBasic
            let y2024 =
                    And
                        [ Date (DateSpan (Just (Exact (fromGregorian 2024 1 1))) (Just (Exact (fromGregorian 2025 1 1))))
                        , Type [Revenue, Expense]
                        ]
            showMixedAmount (balAt j' y2024 (fromGregorian 2025 1 1))
                @?= showMixedAmount (balAt j y2024 (fromGregorian 2025 1 1))
        ]
  where
    closedBasic = do
        j <- readFixture "basic.journal"
        fragment <- runCta (yearOpts 2024) j
        withFragment "basic.journal" fragment

-- * Sign convention: the classic trap

signTests :: TestTree
signTests =
    testGroup
        "revaluation sign convention"
        [ expect "long-rising" (< 0) "gain must credit equity (negative USD)"
        , expect "long-falling" (> 0) "loss must debit equity (positive USD)"
        , expect "short-rising" (> 0) "loss must debit equity (positive USD)"
        , expect "short-falling" (< 0) "gain must credit equity (negative USD)"
        ]
  where
    expect name predicate msg = testCase (name <> ": " <> msg) $ do
        j <- readFixture (name <.> "journal")
        fragment <- runCta (yearOpts 2024) j
        j' <- withFragment (name <.> "journal") fragment
        let reval =
                balAt
                    j'
                    (Acct (accountNameToAccountRegex "Equity:Accumulated:2024:Revalued"))
                    (fromGregorian 2025 1 2)
        assertBool msg (predicate (usdComponent reval))

-- * Sequential closing

sequentialTest :: TestTree
sequentialTest =
    goldenVsString "sequential: closing 2025 after 2024" (testdata </> "sequential-2025.golden") $ do
        j <- readFixture "sequential.journal"
        fragment2024 <- runCta (yearOpts 2024) j
        j' <- withFragment "sequential.journal" fragment2024
        LBS.fromStrict . T.encodeUtf8 <$> runCta (yearOpts 2025) j'
