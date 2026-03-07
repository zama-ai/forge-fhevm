#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Two-phase FHEVM host deployment
#
# Phase 1: Compute proxy addresses and write FHEVMHostAddresses.sol
# Phase 2: Deploy proxies, PauserSet, and upgrade to implementations
#
# Required env vars:
#   DEPLOYER_PRIVATE_KEY
#   RPC_URL
#   DECRYPTION_ADDRESS
#   INPUT_VERIFICATION_ADDRESS
#   CHAIN_ID_GATEWAY
#   KMS_SIGNER_ADDRESS_0 or KMS_SIGNER_PRIVATE_KEY_0
#   PUBLIC_DECRYPTION_THRESHOLD
#   COPROCESSOR_SIGNER_ADDRESS_0 or COPROCESSOR_SIGNER_PRIVATE_KEY_0
#   COPROCESSOR_THRESHOLD
#
# Optional:
#   PAUSER_ADDRESS_0
#   BROADCAST (set to "--broadcast" to send live transactions)
#   VERIFY    (set to "--verify" to verify on Etherscan)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if present
if [[ -f ".env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

: "${DEPLOYER_PRIVATE_KEY:?DEPLOYER_PRIVATE_KEY is required}"
: "${RPC_URL:?RPC_URL is required}"
: "${DECRYPTION_ADDRESS:?DECRYPTION_ADDRESS is required}"
: "${INPUT_VERIFICATION_ADDRESS:?INPUT_VERIFICATION_ADDRESS is required}"
: "${CHAIN_ID_GATEWAY:?CHAIN_ID_GATEWAY is required}"
: "${PUBLIC_DECRYPTION_THRESHOLD:?PUBLIC_DECRYPTION_THRESHOLD is required}"
: "${COPROCESSOR_THRESHOLD:?COPROCESSOR_THRESHOLD is required}"

# KMS and coprocessor signers: require address OR private key (validated inside Forge script)
if [[ -z "${KMS_SIGNER_ADDRESS_0:-}" && -z "${KMS_SIGNER_PRIVATE_KEY_0:-}" ]]; then
    echo "Error: set KMS_SIGNER_ADDRESS_0 or KMS_SIGNER_PRIVATE_KEY_0" >&2
    exit 1
fi
if [[ -z "${COPROCESSOR_SIGNER_ADDRESS_0:-}" && -z "${COPROCESSOR_SIGNER_PRIVATE_KEY_0:-}" ]]; then
    echo "Error: set COPROCESSOR_SIGNER_ADDRESS_0 or COPROCESSOR_SIGNER_PRIVATE_KEY_0" >&2
    exit 1
fi

BROADCAST="${BROADCAST:-}"
VERIFY="${VERIFY:-}"

echo "============================================================"
echo "Phase 1: Computing proxy addresses"
echo "============================================================"
forge script script/ComputeAddresses.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY"

echo ""
echo "============================================================"
echo "Phase 2: Deploying FHEVM host contracts"
echo "============================================================"
# Clear the compilation cache so forge picks up the rewritten FHEVMHostAddresses.sol.
# Without this, forge reuses the cached artifacts from Phase 1 compilation, which
# were built against the OLD addresses (before vm.writeFile ran).
forge clean
forge script script/DeployFHEVMHost.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    ${BROADCAST} \
    ${VERIFY}

echo ""
echo "Deployment complete."
