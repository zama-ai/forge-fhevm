---
title: InputProofHelper
description: Library for computing input handles and EIP-712 input verification proofs.
---

# InputProofHelper

Library that computes deterministic encrypted handles and assembles EIP-712 signed input proofs for the `InputVerifier` contract.

You typically don't need this library directly — [`FhevmTest.encrypt*`](/api/fhevm-test#encryption-functions) calls it internally. Use it when you need custom proof construction.

## Import

```solidity
import {InputProofHelper} from "forge-fhevm/InputProofHelper.sol";
```

## Functions

### computeInputHandle

```solidity
function computeInputHandle(
    bytes memory mockCiphertext,
    uint8 index,
    FheType fheType,
    address aclAddress,
    uint64 chainId
) internal pure returns (bytes32 handle)
```

Computes the deterministic 32-byte handle for an encrypted input. The handle encodes the FHE type at byte 30, the chain ID, and the index — matching the on-chain handle format expected by the FHEVMExecutor.

#### mockCiphertext

`bytes memory`

Arbitrary ciphertext bytes used for handle derivation. In tests, this is typically a hash of the plaintext value and a nonce.

#### index

`uint8`

Position of this handle within a multi-handle input proof. Use `0` for single-handle proofs.

#### fheType

`FheType`

The FHE type encoded into the handle (`FheType.Bool`, `FheType.Uint8`, ..., `FheType.Uint256`).

#### aclAddress

`address`

The ACL contract address embedded in the handle hash.

#### chainId

`uint64`

The chain ID embedded in the handle.

```solidity
bytes32 handle = InputProofHelper.computeInputHandle( // [!code focus]
    mockCiphertext, 0, FheType.Uint64, aclAddress, 31337 // [!code focus]
); // [!code focus]
```

---

### computeInputVerifierDomainSeparator

```solidity
function computeInputVerifierDomainSeparator(
    address verifyingContract,
    uint256 chainId
) internal pure returns (bytes32)
```

Computes the EIP-712 domain separator for the `InputVerifier` contract. Uses `"InputVerification"` as the domain name and `"1"` as the version.

#### verifyingContract

`address`

The InputVerifier contract address.

#### chainId

`uint256`

The chain ID for the domain.

---

### computeInputVerificationDigest

```solidity
function computeInputVerificationDigest(
    bytes32[] memory handles,
    address userAddress,
    address contractAddress,
    uint256 contractChainId,
    bytes memory extraData,
    bytes32 domainSeparator
) internal pure returns (bytes32)
```

Computes the EIP-712 typed-data digest for input verification. This is the digest signed by the input signer to authorize a set of encrypted handles for a specific user/contract pair.

#### handles

`bytes32[] memory`

The ciphertext handles being verified.

#### userAddress

`address`

The user who encrypted the input.

#### contractAddress

`address`

The contract authorized to consume the input.

#### contractChainId

`uint256`

The chain ID included in the signed payload.

#### extraData

`bytes memory`

Additional bytes included in the signature. Use `EMPTY_EXTRA_DATA` (`hex"00"`) for the default.

#### domainSeparator

`bytes32`

The EIP-712 domain separator from [`computeInputVerifierDomainSeparator`](#computeinputverifierdomainseparator).

---

### assembleInputProof

```solidity
function assembleInputProof(
    bytes32[] memory handles,
    bytes[] memory signatures,
    bytes memory extraData
) internal pure returns (bytes memory proof)
```

Assembles handles, ECDSA signatures, and extra data into the wire format consumed by `InputVerifier.verifyInput()`.

The wire format is: `[handleCount (1 byte)][sigCount (1 byte)][handles...][signatures...][extraData]`.

#### handles

`bytes32[] memory`

The ciphertext handles included in the proof.

#### signatures

`bytes[] memory`

The ECDSA signatures from input signers (65 bytes each: `r || s || v`).

#### extraData

`bytes memory`

Extra bytes appended after signatures.

## Constants

### EIP712_DOMAIN_TYPEHASH

```solidity
bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
```

### EIP712_INPUT_VERIFICATION_TYPEHASH

```solidity
bytes32 internal constant EIP712_INPUT_VERIFICATION_TYPEHASH = keccak256(
    "CiphertextVerification(bytes32[] ctHandles,address userAddress,address contractAddress,uint256 contractChainId,bytes extraData)"
);
```
