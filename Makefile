# fhevm version (tag/branch) or commit to pull host contracts from
FHEVM_VERSION ?= v0.11.0
FHEVM_COMMIT  ?=
FHEVM_REPO    := https://github.com/zama-ai/fhevm.git

# Where vendored contracts live
VENDOR_DIR := src/fhevm-host/contracts
TEMP_DIR   := .fhevm-tmp

.PHONY: update-host-contracts clean-tmp

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
	@echo "Done. Vendored host contracts updated."
	@echo "Note: src/fhevm-host/addresses/FHEVMHostAddresses.sol is maintained locally and was NOT overwritten."

clean-tmp:
	@rm -rf $(TEMP_DIR)
