// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {aclAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {InputProofHelper} from "../../src/InputProofHelper.sol";
import {InputVerifierDeployer} from "./InputVerifierDeployer.sol";

abstract contract InputProofTestHelper is InputVerifierDeployer {
    function _mockCiphertext(uint256 value, FheType fheType, uint256 nonce) internal pure returns (bytes memory) {
        return abi.encodePacked(keccak256(abi.encodePacked(value, uint8(fheType), nonce)));
    }

    function _signatureBytes(uint256 signerPk, bytes32 digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return InputProofHelper.computeInputVerifierDomainSeparator(address(inputVerifierContract), block.chainid);
    }

    function _digest(bytes32[] memory handles, address userAddress, address contractAddress, bytes memory extraData)
        internal
        view
        returns (bytes32)
    {
        return InputProofHelper.computeInputVerificationDigest(
            handles, userAddress, contractAddress, block.chainid, extraData, _domainSeparator()
        );
    }

    function _proofSingleSigner(
        bytes32[] memory handles,
        address userAddress,
        address contractAddress,
        bytes memory extraData,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 digest = _digest(handles, userAddress, contractAddress, extraData);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signatureBytes(signerPk, digest);
        return InputProofHelper.assembleInputProof(handles, signatures, extraData);
    }

    function _proofWithSignatures(bytes32[] memory handles, bytes[] memory signatures, bytes memory extraData)
        internal
        pure
        returns (bytes memory)
    {
        return InputProofHelper.assembleInputProof(handles, signatures, extraData);
    }

    function _inputHandle(uint256 value, FheType fheType, uint8 index, uint256 nonce, uint64 chainId)
        internal
        pure
        returns (bytes32)
    {
        bytes memory ciphertext = _mockCiphertext(value, fheType, nonce);
        return InputProofHelper.computeInputHandle(ciphertext, index, fheType, aclAdd, chainId);
    }
}
