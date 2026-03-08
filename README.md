# forge-fhevm

Foundry-native testing library for [fhEVM](https://github.com/zama-ai/fhevm) confidential smart contracts. Write Forge tests that encrypt, compute, decrypt, and assert -- using real production host contracts, no mocks.

## How it works

forge-fhevm deploys the actual fhEVM host contracts (FHEVMExecutor, ACL, InputVerifier, KMSVerifier) as UUPS upgradeable proxies inside Foundry's test environment. When the executor processes an FHE operation, it emits an event. forge-fhevm intercepts these events via `vm.getRecordedLogs()` and maintains a local plaintext database that maps encrypted handles to their cleartext values. This lets tests exercise the exact same contract code paths as production while computing results in the clear.

The only deviation from mainnet is the use of mock private keys for the input signer and KMS signer, enabling deterministic EIP-712 proof generation in tests.

## Quick start

Install and add the remapping:

```bash
forge install zama-ai/forge-fhevm
```

```
# remappings.txt
forge-fhevm/=path/to/forge-fhevm/src/
```

> **Requires** Solidity `^0.8.27` and `evm_version = "cancun"` in your `foundry.toml`.

Inherit from `FhevmTest` and start testing:

```solidity
import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {FHE} from "@fhevm/solidity/lib/FHE.sol";
import "encrypted-types/EncryptedTypes.sol";

contract MyTest is FhevmTest {
    function test_encryptAndDecrypt() public {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(42, address(this));

        euint64 verified = euint64.wrap(
            _executor.verifyInput(externalEuint64.unwrap(handle), address(this), proof, FheType.Uint64)
        );

        assertEq(decrypt(verified), 42);
    }
}
```

```bash
forge test
```

## API overview

`FhevmTest` provides three groups of helpers:

**Encryption** -- `encryptBool`, `encryptUint8` through `encryptUint256`, and `encryptAddress`. Each returns an external handle and a signed input proof ready for `FHE.fromExternal`.

**Decryption** -- Three modes depending on what you need to test:

- `decrypt(handle)` reads the plaintext directly (no ACL checks, fastest for unit tests).
- `publicDecrypt(handles)` checks the ACL decryption flag and returns cleartexts with a KMS-signed proof, matching the on-chain public decryption flow.
- `userDecrypt(handle, user, contract, signature)` performs the full user-facing flow with persistent ACL checks and EIP-712 signature verification.

**Proof helpers** -- `buildDecryptionProof` for callback-style decryption flows, and `signUserDecrypt` for generating EIP-712 user decrypt signatures.

## What `setUp()` deploys

Calling `super.setUp()` deploys all fhEVM host contracts at their canonical deterministic addresses:

| Contract          | Role                                                                        |
| ----------------- | --------------------------------------------------------------------------- |
| **FHEVMExecutor** | Processes FHE operations, emits events intercepted by the plaintext tracker |
| **ACL**           | Per-handle access control (transient and persistent permissions)            |
| **InputVerifier** | Verifies EIP-712 signed input proofs (threshold: 1 mock signer)             |
| **KMSVerifier**   | Verifies EIP-712 signed decryption proofs (threshold: 1 mock signer)        |

## Documentation

Full guides and API reference are available in the [docs](./docs/) directory (VitePress site):

- [Getting Started](./docs/getting-started.md)
- [Encrypt Inputs](./docs/guides/encrypt-inputs.md)
- [Decrypt Results](./docs/guides/decrypt-results.md)
- [Testing Patterns](./docs/guides/testing-patterns.md)
- [FhevmTest API Reference](./docs/api/fhevm-test.md)

## Vendored host contracts

The fhEVM host contracts are vendored in `src/fhevm-host/` because the upstream `fhevm` package generates `FHEVMHostAddresses.sol` at compile time, making it impossible to build as a regular dependency. Run `make update-host-contracts` (or `make update-host-contracts FHEVM_VERSION=v0.12.0`) to pull a new version.

## Deploying a cleartext FHEVM stack

Two deployment paths exist depending on the target network. Both deploy a cleartext FHEVM where encrypted values are stored as plaintexts on-chain (nothing is actually encrypted). Copy `.env.example` to `.env` and fill in the required values first.

**Remote chains (testnets, private chains)** — `BROADCAST=--broadcast ./deploy.sh`. Contracts are deployed at deterministic addresses based on the deployer's nonce, and `FHEVMHostAddresses.sol` is updated accordingly.

**Local dev nodes (Anvil/Hardhat, chain ID 31337)** — `./deploy-local.sh`. Reads the committed addresses from `FHEVMHostAddresses.sol` and materializes the contracts directly at those fixed addresses via `setCode`/`setStorageAt` RPC calls. Use this when you need contracts at the canonical Zama local addresses so `ZamaConfig._getLocalConfig()` works out of the box.

## License

BSD-3-Clause-Clear
