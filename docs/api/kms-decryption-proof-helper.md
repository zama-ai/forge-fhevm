---
title: KMSDecryptionProofHelper
description: Library for building EIP-712 signed KMS decryption proofs.
---

# KMSDecryptionProofHelper

Library that computes EIP-712 decryption digests and assembles wire-format proofs for the `KMSVerifier` contract.

You typically don't need this library directly — [`FhevmTest.publicDecrypt`](/api/fhevm-test#publicdecrypt) and [`FhevmTest.buildDecryptionProof`](/api/fhevm-test#builddecryptionproof) call it internally. Use it when you need custom proof construction.

## Import

```solidity
import {KMSDecryptionProofHelper} from "forge-fhevm/KMSDecryptionProofHelper.sol";
```

## Functions

### computeKMSDecryptionDomainSeparator

```solidity
function computeKMSDecryptionDomainSeparator(
    string memory name,
    string memory version,
    uint256 chainId,
    address verifyingContract
) internal pure returns (bytes32)
```

Computes the EIP-712 domain separator used by the KMSVerifier contract.

#### name

`string memory`

The EIP-712 domain name (typically `"KMSVerifier"`).

#### version

`string memory`

The EIP-712 domain version (typically `"1"`).

#### chainId

`uint256`

The chain ID encoded in the domain.

#### verifyingContract

`address`

The KMSVerifier contract address.

---

### computeDecryptionDigest

```solidity
function computeDecryptionDigest(
    bytes32[] memory handlesList,
    bytes memory decryptedResult,
    bytes memory extraData,
    bytes32 domainSeparator
) internal pure returns (bytes32)
```

Computes the EIP-712 typed-data digest for decryption result verification. This is the digest signed by KMS signers to attest that a set of ciphertext handles decrypt to the given cleartext values.

#### handlesList

`bytes32[] memory`

The ciphertext handles included in the decryption request.

#### decryptedResult

`bytes memory`

ABI-encoded cleartext values returned by decryption.

#### extraData

`bytes memory`

Extra trailing proof bytes included in the signed payload.

#### domainSeparator

`bytes32`

The EIP-712 domain separator from [`computeKMSDecryptionDomainSeparator`](#computekmsdecryptiondomainseparator).

---

### assembleDecryptionProof

```solidity
function assembleDecryptionProof(
    bytes[] memory signatures,
    bytes memory extraData
) internal pure returns (bytes memory proof)
```

Builds the serialized proof wire format consumed by `KMSVerifier.verifyDecryptionEIP712KMSSignatures()`.

The wire format is: `[sigCount (1 byte)][signatures...][extraData]`.

#### signatures

`bytes[] memory`

The concatenated set of 65-byte ECDSA signatures (`r || s || v`).

#### extraData

`bytes memory`

Extra data bytes appended after signatures.

## Constants

### EIP712_DOMAIN_TYPEHASH

```solidity
bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
```

### DECRYPTION_RESULT_TYPEHASH

```solidity
bytes32 internal constant DECRYPTION_RESULT_TYPEHASH =
    keccak256("PublicDecryptVerification(bytes32[] ctHandles,bytes decryptedResult,bytes extraData)");
```
