# fhevm version (tag/branch) or commit to pull host contracts from
FHEVM_VERSION ?= v0.11.0
FHEVM_COMMIT  ?=
FHEVM_REPO    := https://github.com/zama-ai/fhevm.git

VENDOR_DIR := src/fhevm-host/contracts
TEMP_DIR   := .fhevm-tmp
GEN_DIR    := src/generated

.PHONY: update-host-contracts clean-tmp generate check-generated check-consumer-fixture check

## Pull host contracts from the fhevm repository
## Usage:
##   make update-host-contracts                              # uses default version
##   make update-host-contracts FHEVM_VERSION=v0.12.0        # specific tag/branch
##   make update-host-contracts FHEVM_COMMIT=abc123          # specific commit
update-host-contracts: clean-tmp
ifdef FHEVM_COMMIT
	@echo "Cloning fhevm and checking out $(FHEVM_COMMIT)..."
	@GIT_TERMINAL_PROMPT=0 git -c advice.detachedHead=false \
		clone --filter=blob:none --sparse \
		$(FHEVM_REPO) $(TEMP_DIR) 2>/dev/null
	@cd $(TEMP_DIR) && git sparse-checkout set host-contracts/contracts && \
		git checkout $(FHEVM_COMMIT) 2>/dev/null
else
	@echo "Cloning fhevm@$(FHEVM_VERSION) (sparse checkout)..."
	@GIT_TERMINAL_PROMPT=0 git -c advice.detachedHead=false \
		clone --depth 1 --branch $(FHEVM_VERSION) --filter=blob:none --sparse \
		$(FHEVM_REPO) $(TEMP_DIR) 2>/dev/null
	@cd $(TEMP_DIR) && git sparse-checkout set host-contracts/contracts
endif
	@echo "Copying contracts to $(VENDOR_DIR)..."
	@rm -rf $(VENDOR_DIR)
	@cp -r $(TEMP_DIR)/host-contracts/contracts $(VENDOR_DIR)
	@$(MAKE) clean-tmp --no-print-directory
	@$(MAKE) generate --no-print-directory
	@echo "Done. Vendored host contracts updated and $(GEN_DIR) regenerated."
	@echo "Note: src/fhevm-host/addresses/FHEVMHostAddresses.sol is maintained locally and was NOT overwritten."

clean-tmp:
	@rm -rf $(TEMP_DIR)

## Regenerate the OZ-free surface (bytecode blobs + interfaces) from the vendored source.
## Always run this after touching anything under $(VENDOR_DIR), and commit the result.
## The skips are required, not an optimization: those sources import the files this target
## produces, so a clean tree could never build them first.
generate:
	@forge build --skip 'src/FhevmTest.sol' --skip 'test/**'
	@python3 script/gen/generate.py

## CI gate: the committed generated files must match what the vendored source produces.
## Without this, the ~180 KB of hex in $(GEN_DIR) would be unreviewable and unverifiable.
check-generated:
	@$(MAKE) generate --no-print-directory >/dev/null
	@git diff --quiet -- $(GEN_DIR) || { \
		echo "ERROR: $(GEN_DIR) is stale — it does not match $(VENDOR_DIR)."; \
		echo "Run 'make generate' and commit the result."; \
		git --no-pager diff --stat -- $(GEN_DIR); \
		exit 1; }
	@echo "OK: $(GEN_DIR) matches the vendored source."

## CI gate: a downstream project pinning a NEWER OpenZeppelin must still build and pass.
## Populates the fixture's dependencies/forge-fhevm/ the way soldeer would install it.
FIXTURE := fixtures/consumer
check-consumer-fixture:
	@rm -rf $(FIXTURE)/dependencies/forge-fhevm
	@mkdir -p $(FIXTURE)/dependencies/forge-fhevm
	@cp -r src $(FIXTURE)/dependencies/forge-fhevm/src
	@cd $(FIXTURE) && forge soldeer install --config-location foundry >/dev/null
	@forge test --root $(FIXTURE)

check: check-generated check-consumer-fixture
	@forge test
