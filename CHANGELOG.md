# Changelog

## 0.1.0.0 — 2026-07-07

Initial release.

- `hledger close-cta`: period-end closing fragment for multi-currency
  ledgers — retained-earnings sweep, layer pinning to a base currency at
  period-end rates, CTA revaluation of live positions (IAS 21 / ASC 830
  style).
- Closing period from the standard `-b`/`-e`/`-p` options (any bounded
  period; defaults to the last complete calendar year).
- `--base` currency (default USD), `--earned-acct`/`--revalued-acct`
  templates with a `{period}` placeholder.
- `--infer-market-prices`: rates from transaction costs in addition to
  `P` directives; declared prices win on the same day.
- Tested against hledger-lib 1.52: golden outputs, sign-convention
  matrix (long/short positions × rising/falling rates), layer-constancy
  invariants, sequential multi-period closing.
