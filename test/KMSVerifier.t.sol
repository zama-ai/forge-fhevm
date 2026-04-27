// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {KMSVerifier} from "@fhevm/host-contracts/contracts/KMSVerifier.sol";
import {kmsVerifierAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {KMSDecryptionProofTestHelper} from "./helpers/KMSDecryptionProofTestHelper.sol";

contract KMSVerifierTest is KMSDecryptionProofTestHelper {
    uint256 internal constant WRONG_SIGNER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function setUp() public {
        _deployKMSVerifierStack();
    }

    function test_deployment_atKnownAddress() public view {
        assertEq(address(kmsVerifierContract), kmsVerifierAdd);
    }

    function test_deployment_signerRegistered() public view {
        assertTrue(kmsVerifierContract.isSigner(mockKmsSigner));
    }

    function test_deployment_thresholdIs1() public view {
        assertEq(kmsVerifierContract.getThreshold(), 1);
    }

    function test_deployment_eip712Domain() public view {
        (bytes1 fields, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            kmsVerifierContract.eip712Domain();
        assertEq(uint8(fields), uint8(0x0f));
        assertEq(name, "Decryption");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, kmsVerifierAdd);
    }

    function test_deployment_version() public view {
        assertEq(kmsVerifierContract.getVersion(), "KMSVerifier v0.2.0");
    }

    function test_verify_happyPath_singleHandle() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(11));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 12345;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory proof =
            _decryptionProofSingleSigner(handles, decryptedResult, DEFAULT_EXTRA_DATA, MOCK_KMS_SIGNER_PK);
        bool isVerified = kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
        assertTrue(isVerified);
    }

    function test_verify_happyPath_multipleHandles() public {
        bytes32[] memory handles = new bytes32[](3);
        handles[0] = bytes32(uint256(100));
        handles[1] = bytes32(uint256(200));
        handles[2] = bytes32(uint256(300));

        uint256[] memory clearValues = new uint256[](3);
        clearValues[0] = 7;
        clearValues[1] = 42;
        clearValues[2] = type(uint256).max;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory proof =
            _decryptionProofSingleSigner(handles, decryptedResult, DEFAULT_EXTRA_DATA, MOCK_KMS_SIGNER_PK);
        bool isVerified = kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
        assertTrue(isVerified);
    }

    function test_verify_happyPath_emptyExtraData() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(77));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 88;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory proof = _decryptionProofSingleSigner(handles, decryptedResult, hex"", MOCK_KMS_SIGNER_PK);
        bool isVerified = kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
        assertTrue(isVerified);
    }

    function test_verify_digestMatchesOnChainHashFormula() public view {
        bytes32[] memory handles = new bytes32[](2);
        handles[0] = bytes32(uint256(1));
        handles[1] = bytes32(uint256(2));

        uint256[] memory clearValues = new uint256[](2);
        clearValues[0] = 55;
        clearValues[1] = 66;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes32 helperDigest = _decryptionDigest(handles, decryptedResult, DEFAULT_EXTRA_DATA);
        bytes32 structHash = keccak256(
            abi.encode(
                kmsVerifierContract.DECRYPTION_RESULT_TYPEHASH(),
                keccak256(abi.encodePacked(handles)),
                keccak256(decryptedResult),
                keccak256(abi.encodePacked(DEFAULT_EXTRA_DATA))
            )
        );
        bytes32 expectedDigest = MessageHashUtils.toTypedDataHash(_kmsDomainSeparator(), structHash);
        assertEq(helperDigest, expectedDigest);
    }

    function test_verify_revert_emptyDecryptionProof() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(1));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 1;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        vm.expectRevert(KMSVerifier.EmptyDecryptionProof.selector);
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, new bytes(0));
    }

    function test_verify_revert_deserializingDecryptionProofFail() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(1));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 1;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory badProof = abi.encodePacked(uint8(1));
        vm.expectRevert(KMSVerifier.DeserializingDecryptionProofFail.selector);
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, badProof);
    }

    function test_verify_revert_kmsZeroSignature() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(1));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 99;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes[] memory signatures = new bytes[](0);
        bytes memory proof = _decryptionProofWithSignatures(signatures, DEFAULT_EXTRA_DATA);
        vm.expectRevert(KMSVerifier.KMSZeroSignature.selector);
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
    }

    function test_verify_revert_kmsSignatureThresholdNotReached() public {
        address[] memory signers = new address[](2);
        signers[0] = mockKmsSigner;
        signers[1] = vm.addr(WRONG_SIGNER_PK);

        vm.prank(OWNER);
        kmsVerifierContract.defineNewContext(signers, 2);

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(11));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 9;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory proof =
            _decryptionProofSingleSigner(handles, decryptedResult, DEFAULT_EXTRA_DATA, MOCK_KMS_SIGNER_PK);
        vm.expectRevert(abi.encodeWithSelector(KMSVerifier.KMSSignatureThresholdNotReached.selector, 1));
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
    }

    function test_verify_revert_kmsInvalidSigner() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(11));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 5;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory proof = _decryptionProofSingleSigner(handles, decryptedResult, DEFAULT_EXTRA_DATA, WRONG_SIGNER_PK);
        vm.expectRevert(abi.encodeWithSelector(KMSVerifier.KMSInvalidSigner.selector, vm.addr(WRONG_SIGNER_PK)));
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
    }

    function test_verify_revert_corruptedSignature() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(9));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 10;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes32 digest = _decryptionDigest(handles, decryptedResult, DEFAULT_EXTRA_DATA);
        bytes memory validSignature = _signatureBytes(MOCK_KMS_SIGNER_PK, digest);
        bytes memory truncatedSignature = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            truncatedSignature[i] = validSignature[i];
        }

        bytes memory corruptedProof = abi.encodePacked(uint8(1), truncatedSignature, bytes1(0x00));
        vm.expectRevert();
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, corruptedProof);
    }

    function test_verify_revert_wrongHandles() public {
        bytes32[] memory signedHandles = new bytes32[](1);
        signedHandles[0] = bytes32(uint256(111));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 222;
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);
        bytes memory proof =
            _decryptionProofSingleSigner(signedHandles, decryptedResult, DEFAULT_EXTRA_DATA, MOCK_KMS_SIGNER_PK);

        bytes32[] memory wrongHandles = new bytes32[](1);
        wrongHandles[0] = bytes32(uint256(999));

        vm.expectPartialRevert(KMSVerifier.KMSInvalidSigner.selector);
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(wrongHandles, decryptedResult, proof);
    }

    function test_verify_revert_wrongDecryptedResult() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32(uint256(321));

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = 654;
        bytes memory signedDecryptedResult = _abiEncodeClearValues(clearValues);
        bytes memory proof =
            _decryptionProofSingleSigner(handles, signedDecryptedResult, DEFAULT_EXTRA_DATA, MOCK_KMS_SIGNER_PK);

        uint256[] memory wrongClearValues = new uint256[](1);
        wrongClearValues[0] = 655;
        bytes memory wrongDecryptedResult = _abiEncodeClearValues(wrongClearValues);

        vm.expectPartialRevert(KMSVerifier.KMSInvalidSigner.selector);
        kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, wrongDecryptedResult, proof);
    }

    function test_integration_trivialEncryptThenDecryptionProof() public {
        bytes32 handle = _trivialEncrypt(777, FheType.Uint64);

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = _readPlaintext(handle);
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory proof =
            _decryptionProofSingleSigner(handles, decryptedResult, DEFAULT_EXTRA_DATA, MOCK_KMS_SIGNER_PK);
        bool isVerified = kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
        assertTrue(isVerified);
    }

    function test_integration_multipleHandlesDecryptionProof() public {
        bytes32 handle0 = _trivialEncrypt(1, FheType.Uint8);
        bytes32 handle1 = _trivialEncrypt(2, FheType.Uint16);
        bytes32 handle2 = _trivialEncrypt(3, FheType.Uint256);

        bytes32[] memory handles = new bytes32[](3);
        handles[0] = handle0;
        handles[1] = handle1;
        handles[2] = handle2;

        uint256[] memory clearValues = new uint256[](3);
        clearValues[0] = _readPlaintext(handle0);
        clearValues[1] = _readPlaintext(handle1);
        clearValues[2] = _readPlaintext(handle2);
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes memory proof =
            _decryptionProofSingleSigner(handles, decryptedResult, DEFAULT_EXTRA_DATA, MOCK_KMS_SIGNER_PK);
        bool isVerified = kmsVerifierContract.verifyDecryptionEIP712KMSSignatures(handles, decryptedResult, proof);
        assertTrue(isVerified);
    }

    function test_integration_proofFormatMatchesWireSpec() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _trivialEncrypt(99, FheType.Uint32);

        uint256[] memory clearValues = new uint256[](1);
        clearValues[0] = _readPlaintext(handles[0]);
        bytes memory decryptedResult = _abiEncodeClearValues(clearValues);

        bytes32 digest = _decryptionDigest(handles, decryptedResult, DEFAULT_EXTRA_DATA);
        bytes memory signature = _signatureBytes(MOCK_KMS_SIGNER_PK, digest);

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        bytes memory proof = _decryptionProofWithSignatures(signatures, DEFAULT_EXTRA_DATA);

        assertEq(uint8(proof[0]), 1);
        assertEq(proof.length, 1 + 65 + DEFAULT_EXTRA_DATA.length);

        bytes memory proofSignature = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            proofSignature[i] = proof[1 + i];
        }
        assertEq(keccak256(proofSignature), keccak256(signature));
        assertEq(proof[66], DEFAULT_EXTRA_DATA[0]);
    }
}
