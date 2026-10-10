.PHONY: install check

install:
	npm ci --ignore-scripts

check:
	forge fmt --check
	forge clean
	forge build
	forge test
