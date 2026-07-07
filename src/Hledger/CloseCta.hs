-- | Year-end closing with currency translation adjustment.
--
-- Generates a closing journal fragment: retained-earnings sweep,
-- layer pinning to a base currency at closing rates, and CTA
-- revaluation of live positions.
module Hledger.CloseCta (
    version,
) where

-- | Package version string, reported by the executable.
version :: String
version = "0.1.0.0"
