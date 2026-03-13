#!/usr/bin/env bash
# Validates that all FHEVM host contracts are deployed and initialized at
# the addresses declared in FHEVMHostAddresses.sol.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/script/lib/deploy-common.sh"

if [[ -z "${RPC_URL:-}" ]]; then
    load_dotenv_if_present "$REPO_ROOT/.env"
fi

: "${RPC_URL:?RPC_URL is required}"

ERC1967_IMPL_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

errors=0

assert_has_code() {
    local label="$1" address="$2"
    local code
    code="$(cast code "$address" --rpc-url "$RPC_URL")"
    if [[ "$code" == "0x" || -z "$code" ]]; then
        echo "FAIL: $label ($address) has no runtime code" >&2
        errors=$((errors + 1))
        return
    fi
    echo "OK:   $label ($address) has code"
}

assert_has_impl() {
    local label="$1" address="$2"
    local slot_value impl
    slot_value="$(cast storage "$address" "$ERC1967_IMPL_SLOT" --rpc-url "$RPC_URL")"
    impl="$(printf '0x%s\n' "${slot_value:26:40}")"
    if [[ "$impl" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "FAIL: $label ($address) ERC-1967 impl slot is zero" >&2
        errors=$((errors + 1))
        return
    fi
    echo "OK:   $label ($address) impl=$impl"
}

echo "=== Validating deployed addresses (FHEVMHostAddresses.sol) ==="

ACL_ADD="$(extract_address_constant_from_file aclAdd)"
EXECUTOR_ADD="$(extract_address_constant_from_file fhevmExecutorAdd)"
KMS_ADD="$(extract_address_constant_from_file kmsVerifierAdd)"
IV_ADD="$(extract_address_constant_from_file inputVerifierAdd)"
HCU_ADD="$(extract_address_constant_from_file hcuLimitAdd)"
PAUSER_ADD="$(extract_address_constant_from_file pauserSetAdd)"

for pair in \
    "ACL:$ACL_ADD" \
    "FHEVMExecutor:$EXECUTOR_ADD" \
    "KMSVerifier:$KMS_ADD" \
    "InputVerifier:$IV_ADD" \
    "HCULimit:$HCU_ADD" \
    "PauserSet:$PAUSER_ADD"; do
    label="${pair%%:*}"
    addr="${pair#*:}"
    assert_has_code "$label" "$addr"
    if [[ "$label" != "PauserSet" ]]; then
        assert_has_impl "$label" "$addr"
    fi
done

echo ""
if [[ "$errors" -gt 0 ]]; then
    echo "FAILED: $errors check(s) failed" >&2
    exit 1
fi
echo "All checks passed."
