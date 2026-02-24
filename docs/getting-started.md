---
title: Getting Started
description: Install forge-fhevm and write your first confidential contract test.
---

# Getting Started

forge-fhevm is a Foundry-native testing library for FHEVM confidential smart contracts. It deploys real host contracts (FHEVMExecutor, ACL, InputVerifier, KMSVerifier) with mock signer keys and tracks plaintext values through event interception — giving you full FHE testing without mocks.

## Installation

Install forge-fhevm:

```bash
forge install zama-ai/forge-fhevm
```

Add the remapping to your `remappings.txt`:

```
forge-fhevm/=path/to/forge-fhevm/src/
```

::: warning
forge-fhevm requires Solidity `^0.8.27` and the `cancun` EVM version. Make sure your `foundry.toml` is configured accordingly:

```toml
[profile.default]
solc = "0.8.27"
evm_version = "cancun"
```
:::

## Write Your First Test

Inherit from `FhevmTest` in your test contract. The `setUp()` function deploys all FHEVM host contracts automatically.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {FHE} from "@fhevm/solidity/lib/FHE.sol";

import "encrypted-types/EncryptedTypes.sol";

contract MyFirstTest is FhevmTest {
    function test_encryptAndDecrypt() public {
        // 1. Encrypt a value — returns a handle and an input proof
        (externalEuint64 handle, bytes memory proof) = encryptUint64(42, address(this));

        // 2. Verify the input through the real executor (as a contract would)
        euint64 verified = euint64.wrap(
            _executor.verifyInput(externalEuint64.unwrap(handle), address(this), proof, FheType.Uint64)
        );

        // 3. Decrypt and assert
        assertEq(decrypt(verified), 42);
    }
}
```

Run it:

```bash
forge test --match-test test_encryptAndDecrypt -vv
```

## What `setUp()` Deploys

When your test inherits `FhevmTest`, the `setUp()` function:

1. Sets the chain ID to `31337`
2. Derives two mock signers from hardcoded private keys (`MOCK_INPUT_SIGNER` and `MOCK_KMS_SIGNER`)
3. Deploys real UPGRADEABLE proxies for all FHEVM host contracts:
   - **FHEVMExecutor** — processes FHE operations and emits events
   - **ACL** — manages per-handle access control (transient and persistent)
   - **InputVerifier** — verifies EIP-712 signed input proofs (threshold: 1 signer)
   - **KMSVerifier** — verifies EIP-712 signed decryption proofs (threshold: 1 signer)
4. Starts the Foundry log recorder (`vm.recordLogs()`) for plaintext tracking

All deployed contracts are real production code — no mocks. The only difference from mainnet is the use of known private keys for the input and KMS signers.

## Next Steps

- [**Encrypt Inputs**](/guides/encrypt-inputs) Learn how to encrypt values for contract interactions.
- [**Decrypt Results**](/guides/decrypt-results) Understand the three decryption modes: `decrypt()`, `publicDecrypt()`, and `userDecrypt()`.
- [**Testing Patterns**](/guides/testing-patterns) See end-to-end patterns for testing confidential tokens and FHE arithmetic.
- [**FhevmTest API**](/api/fhevm-test) Full API reference for the `FhevmTest` base contract.
