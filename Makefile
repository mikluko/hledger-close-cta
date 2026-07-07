CABAL ?= cabal

.PHONY: build test lint fmt fmt-check clean

build:
	$(CABAL) build

test:
	$(CABAL) test --test-show-details=direct

lint:
	hlint src app test

fmt:
	fourmolu --mode inplace src app test

fmt-check:
	fourmolu --mode check src app test

clean:
	$(CABAL) clean
