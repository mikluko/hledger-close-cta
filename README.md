# hledger-close-cta

An [hledger](https://hledger.org) add-on that closes the books for a period
in a multi-currency ledger the way accountants do it: realized flows are
fixed in the base currency at closing rates, and unrealized FX movement on
live positions is booked as a cumulative translation adjustment
(IAS 21 / ASC 830 style).

## The problem

hledger's `close --retain` sweeps a period's revenues and expenses into a
retained-earnings equity account, keeping the original commodities. In a
single-currency ledger that is fine. In a multi-currency ledger it quietly
breaks the balance sheet:

1. A retained layer like `{−122 082 USD, +8 512 400 JPY, +3 150 000 MNT}` is
   a record of closed, realized flows. The yen were spent, the dollars were
   earned; nothing about that history can change anymore. Yet every valued
   report (`-V`, `-X USD`) re-converts those dead components at *today's*
   rates. The layer "breathes": a layer worth $19 440 in January can display
   as $4 503 by December with zero transactions touching it.

2. The noise is unbounded. Each closed period adds another breathing layer,
   so equity-section volatility grows with the ledger's age, drowning the
   signal (current performance) in revaluation of history.

3. Standard accounting solved this long ago: translate closed flows at
   closing rates once, keep a cumulative translation adjustment for live
   positions. But hledger has no built-in support, and doing it by hand
   every period is error-prone; the sign convention on revaluation pairs is
   a classic trap.

## The principle

Only things you still *hold* have a current market value. Things that
already *happened* have the value they had when the books were closed.

- **Realized flows** (the period's income and expenses) are swept into a
  per-period equity layer and immediately converted ("pinned") to the base
  currency at the period-end rates. From then on the layer is a
  base-currency constant: it shows the same number in a valued report at
  any later date, forever.
- **Live positions** (assets and liabilities in foreign currencies) are the
  only thing legitimately exposed to FX movement. Their unrealized
  gain/loss over the period is booked once, to a separate per-period
  equity layer, as a revaluation pair: the position at the new rate minus
  the same position at the old rate.

The resulting equity model:

```
Equity:Accumulated:2024:Earned     realized flows, base-currency constant
Equity:Accumulated:2024:Revalued   unrealized FX on live positions, constant
```

Dead flows are never revalued again. The only line that moves in a valued
balance sheet is the current period's not-yet-closed net, as it should be.

## What it generates

Given a period and a base currency, the tool prints three journal entries
to stdout, dated on the first day after the period:

1. **Retain sweep**: the period's revenues and expenses moved into the
   `...:Earned` layer (like `hledger close --retain`, but dated after the
   period and without balance assertions).
2. **Layer pinning**: every non-base commodity in the swept layer converted
   to the base currency at the period-end market price, using `@` cost
   notation.
3. **CTA revaluation**: for each foreign currency with a non-zero net
   position across assets and liabilities, a pair of legs on the
   `...:Revalued` layer: the position at the period-end rate minus the same
   position at the period-start rate. The implicit base-currency leg is the
   unrealized gain or loss.

Market prices come from the journal's `P` directives: the latest one on or
before the period end (respectively period start) for each currency.

## Installation

Requires the `hledger` executable (tested with 1.52) and, to build, GHC
9.10 with cabal (easiest via [ghcup](https://www.haskell.org/ghcup/)):

```sh
git clone https://github.com/mikluko/hledger-close-cta
cd hledger-close-cta
cabal install
```

`cabal install` puts `hledger-close-cta` on your PATH (`~/.cabal/bin` or
`~/.local/bin`; make sure it is in `$PATH`). hledger discovers any
`hledger-*` executable as an add-on command, so both forms work:

```sh
hledger-close-cta --help
hledger close-cta -- --help     # note the -- before add-on flags
```

## Usage

```
hledger close-cta [-f FILE] [-b/-e/-p PERIOD] [--base CUR]
                  [--earned-acct TPL] [--revalued-acct TPL]
```

- Period: the standard hledger `-b`/`-e`/`-p` options; close a year, a
  quarter, any bounded period. Default: the last complete calendar year.
- `--base`: base currency, default `USD`.
- Account templates default to `Equity:Accumulated:{period}:Earned` and
  `Equity:Accumulated:{period}:Revalued`, where `{period}` is hledger's
  period label (`2024`, `2024Q3`, ...).

### Example

[`examples/personal.journal`](examples/personal.journal) is a year of
multi-currency activity: salary in USD, freelance income and expenses in
JPY, cash savings in HKD, travel money in MNT, with `P` rates at the
start and end of 2024.

```sh
hledger close-cta -f examples/personal.journal -p 2024 --base USD
```

prints ([`examples/closing-2024.journal`](examples/closing-2024.journal)):

```ledger
2025-01-01 retain earnings  ; retain:
    Expenses:Rent                      -400000 JPY
    Expenses:Groceries                  -80000 JPY
    Expenses:Travel                    -900000 MNT
    Income:Salary                      3000.00 USD
    Income:Freelance                   1200000 JPY
    Equity:Accumulated:2024:Earned

2025-01-01 * Pin 2024 layer to base currency
    Equity:Accumulated:2024:Earned     720000 JPY @ 0.006400 USD
    Equity:Accumulated:2024:Earned    -900000 MNT @ 0.000285 USD
    Equity:Accumulated:2024:Earned

2025-01-01 * Currency translation of live positions, 2024 (unrealized)
    Equity:Accumulated:2024:Revalued     4000.00 HKD @ 0.128500 USD
    Equity:Accumulated:2024:Revalued    -4000.00 HKD @ 0.128000 USD
    Equity:Accumulated:2024:Revalued      720000 JPY @ 0.006400 USD
    Equity:Accumulated:2024:Revalued     -720000 JPY @ 0.007100 USD
    Equity:Accumulated:2024:Revalued      600000 MNT @ 0.000285 USD
    Equity:Accumulated:2024:Revalued     -600000 MNT @ 0.000290 USD
    Equity:Accumulated:2024:Revalued
```

Reading it back:

- The sweep zeroes the year's income and expenses; the layer receives
  their net: 720 000 JPY and 3 000 USD earned, 900 000 MNT spent.
- The pin converts the layer's yen and tugrik to dollars at the closing
  rates; the implicit leg makes the layer a constant −7 351.50 USD from
  now on.
- The revaluation books the year's FX movement on what is still held:
  720 000 JPY weakened (rate 0.0071 → 0.0064), 4 000 HKD firmed a touch
  (0.1280 → 0.1285), the leftover 600 000 MNT slipped (0.000290 →
  0.000285); net unrealized loss 505 USD, debited to the `Revalued`
  layer by the implicit leg.

Append the output to the journal (or include it as a separate file) and
valued reports become stable:

```sh
hledger -f examples/personal.journal -f examples/closing-2024.journal \
    bal Equity:Accumulated -X USD --infer-market-prices -e 2025-06-30
# same numbers at -e 2025-12-31, or any later date
```

**The sign convention trap this tool exists to avoid:** in the revaluation
pair, the position goes *positive at the new rate, negative at the old
rate*. Reversing the pair silently books currency gains as losses. Covered
by tests here; one reason not to write these entries by hand.

## Simplifications

The whole period-end position is revalued from the period-start rate;
intra-period acquisitions are not date-weighted. The residual imprecision
stays in the balance sheet's unexplained net line, which is acceptable for
personal-ledger use.

## Status

Working: sweep, pin, and revaluation generation with golden, invariant,
and sign-convention tests. Interface may still change.

## References

- [hledger: close command](https://hledger.org/1.52/hledger.html#close)
- [hledger: add-on commands](https://hledger.org/1.52/hledger.html#addons)
- [hledger: valuation](https://hledger.org/1.52/hledger.html#valuation)
- [IAS 21: The Effects of Changes in Foreign Exchange Rates](https://www.ifrs.org/issued-standards/list-of-standards/ias-21-the-effects-of-changes-in-foreign-exchange-rates/)
- [plaintextaccounting.org: Closing the books](https://plaintextaccounting.org/#closing-the-books)
