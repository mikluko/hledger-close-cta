# hledger-close-cta

hledger add-on for year-end closing with currency translation adjustment
(IAS 21 / ASC 830 style) in multi-currency ledgers.

Given a year and a base currency, prints a closing journal fragment:

1. **Retain sweep**: revenues and expenses into a per-year retained-earnings
   equity layer.
2. **Layer pinning**: the swept layer converted to the base currency at
   year-end rates, making it a base-currency constant.
3. **CTA revaluation**: unrealized FX gain/loss on live asset/liability
   positions booked to a per-year revaluation layer.

Dead flows are never revalued again; valued balance sheets stop "breathing"
on historical equity layers.

## Status

Early development. Not usable yet.

## Usage (planned)

```
hledger close-cta --year 2026 --base USD [-f journal]
```

## Build

```
cabal build
cabal test
```
