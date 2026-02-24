// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {KMSDecryptionProofHelper} from "../../src/KMSDecryptionProofHelper.sol";
import {KMSVerifierDeployer} from "./KMSVerifierDeployer.sol";

abstract contract KMSDecryptionProofTestHelper is KMSVerifierDeployer {
    bytes internal constant DEFAULT_EXTRA_DATA = hex"00";

    /// @notice Reads the deployed KMSVerifier domain and computes the EIP-712 separator.
    /// @return The current domain separator for decryption signatures.
    function _kmsDomainSeparator() internal view returns (bytes32) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            kmsVerifierContract.eip712Domain();
        return KMSDecryptionProofHelper.computeKMSDecryptionDomainSeparator(name, version, chainId, verifyingContract);
    }

    /// @notice Computes the EIP-712 digest for a decryption payload.
    /// @param handlesList Ciphertext handles being decrypted.
    /// @param decryptedResult ABI-encoded clear values.
    /// @param extraData Extra payload bytes included in the proof.
    /// @return The digest used for signer signatures.
    function _decryptionDigest(bytes32[] memory handlesList, bytes memory decryptedResult, bytes memory extraData)
        internal
        view
        returns (bytes32)
    {
        return KMSDecryptionProofHelper.computeDecryptionDigest(
            handlesList, decryptedResult, extraData, _kmsDomainSeparator()
        );
    }

    /// @notice Signs an EIP-712 digest and returns the compact 65-byte signature encoding.
    /// @param signerPk The private key used to sign.
    /// @param digest The digest to sign.
    /// @return signature Packed signature bytes in r||s||v format.
    function _signatureBytes(uint256 signerPk, bytes32 digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    /// @notice Creates a full proof payload signed by a single signer key.
    /// @param handlesList Ciphertext handles included in the signed payload.
    /// @param decryptedResult ABI-encoded clear values included in the signed payload.
    /// @param extraData Extra payload bytes appended to the proof.
    /// @param signerPk Private key used for the proof signature.
    /// @return The serialized decryption proof.
    function _decryptionProofSingleSigner(
        bytes32[] memory handlesList,
        bytes memory decryptedResult,
        bytes memory extraData,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 digest = _decryptionDigest(handlesList, decryptedResult, extraData);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signatureBytes(signerPk, digest);
        return KMSDecryptionProofHelper.assembleDecryptionProof(signatures, extraData);
    }

    /// @notice Assembles a proof payload from explicit signatures and extra data.
    /// @param signatures Signature list in proof order.
    /// @param extraData Extra payload bytes appended after signatures.
    /// @return The serialized decryption proof.
    function _decryptionProofWithSignatures(bytes[] memory signatures, bytes memory extraData)
        internal
        pure
        returns (bytes memory)
    {
        return KMSDecryptionProofHelper.assembleDecryptionProof(signatures, extraData);
    }

    /// @notice ABI-encodes decrypted clear values as expected by verifier checks.
    /// @param clearValues Clear values to encode.
    /// @return The ABI-encoded byte payload.
    function _abiEncodeClearValues(uint256[] memory clearValues) internal pure returns (bytes memory) {
        return abi.encode(clearValues);
    }
}
