// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {inputVerifierAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {InputVerifier} from "@fhevm/host-contracts/contracts/InputVerifier.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";
import {InputProofHelper} from "../src/InputProofHelper.sol";
import {InputProofTestHelper} from "./helpers/InputProofTestHelper.sol";

contract InputVerifierTest is InputProofTestHelper {
    uint256 internal constant MOCK_KMS_SIGNER_PK = 0x388b7680e4e1afa06efbfd45cdd1fe39f3c6af381df6555a19661f283b97de91;
    address internal constant USER = address(0xA11CE);
    bytes internal constant EXTRA_DATA = hex"00";

    function setUp() public {
        _deployInputVerifierStack();
    }

    function test_deployment_atKnownAddress() public view {
        assertEq(address(inputVerifierContract), inputVerifierAdd);
    }

    function test_deployment_signerRegistered() public view {
        assertTrue(inputVerifierContract.isSigner(mockInputSigner));
    }

    function test_deployment_thresholdIs1() public view {
        assertEq(inputVerifierContract.getThreshold(), 1);
    }

    function test_deployment_handleVersionIs0() public view {
        assertEq(inputVerifierContract.getHandleVersion(), 0);
    }

    function test_deployment_eip712Domain() public view {
        (bytes1 fields, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            inputVerifierContract.eip712Domain();
        assertEq(uint8(fields), uint8(0x0f));
        assertEq(name, "InputVerification");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, inputVerifierAdd);
    }

    function test_verifyInput_happyPath_allTypes() public {
        FheType[] memory types = new FheType[](9);
        types[0] = FheType.Bool;
        types[1] = FheType.Uint4;
        types[2] = FheType.Uint8;
        types[3] = FheType.Uint16;
        types[4] = FheType.Uint32;
        types[5] = FheType.Uint64;
        types[6] = FheType.Uint128;
        types[7] = FheType.Uint160;
        types[8] = FheType.Uint256;

        bytes32[] memory handles = new bytes32[](types.length);
        for (uint8 i = 0; i < types.length; i++) {
            handles[i] = _inputHandle(uint256(i) + 1, types[i], i, i + 1, uint64(block.chainid));
            _seedInputPlaintext(handles[i], uint256(i) + 1);
        }

        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);
        for (uint8 i = 0; i < types.length; i++) {
            bytes32 verified = executor.verifyInput(handles[i], USER, proof, types[i]);
            assertEq(verified, handles[i]);
            assertTrue(aclContract.allowedTransient(verified, address(this)));
        }
    }

    function test_verifyInput_happyPath_batchHandles() public {
        bytes32[] memory handles = new bytes32[](3);
        handles[0] = _inputHandle(11, FheType.Uint8, 0, 11, uint64(block.chainid));
        handles[1] = _inputHandle(22, FheType.Uint64, 1, 11, uint64(block.chainid));
        handles[2] = _inputHandle(33, FheType.Bool, 2, 11, uint64(block.chainid));

        _seedInputPlaintext(handles[0], 11);
        _seedInputPlaintext(handles[1], 22);
        _seedInputPlaintext(handles[2], 1);

        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        assertEq(executor.verifyInput(handles[2], USER, proof, FheType.Bool), handles[2]);
        assertEq(executor.verifyInput(handles[0], USER, proof, FheType.Uint8), handles[0]);
    }

    function test_verifyInput_cachedProof_secondCall() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(7, FheType.Uint64, 0, 77, uint64(block.chainid));
        _seedInputPlaintext(handles[0], 7);

        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);
        assertEq(executor.verifyInput(handles[0], USER, proof, FheType.Uint64), handles[0]);
        assertEq(executor.verifyInput(handles[0], USER, proof, FheType.Uint64), handles[0]);
    }

    function test_verifyInput_revert_emptyInputProof() public {
        bytes32 handle = _inputHandle(9, FheType.Uint8, 0, 99, uint64(block.chainid));
        vm.expectRevert(InputVerifier.EmptyInputProof.selector);
        executor.verifyInput(handle, USER, new bytes(0), FheType.Uint8);
    }

    function test_verifyInput_revert_deserializingInputProofFail() public {
        bytes32 handle = _inputHandle(5, FheType.Uint8, 0, 1, uint64(block.chainid));
        bytes memory badProof = abi.encodePacked(uint8(1), uint8(1), handle);

        vm.expectRevert(InputVerifier.DeserializingInputProofFail.selector);
        executor.verifyInput(handle, USER, badProof, FheType.Uint8);
    }

    function test_verifyInput_revert_invalidChainId() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(1, FheType.Uint16, 0, 123, uint64(block.chainid + 1));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        vm.expectRevert(InputVerifier.InvalidChainId.selector);
        executor.verifyInput(handles[0], USER, proof, FheType.Uint16);
    }

    function test_verifyInput_revert_invalidIndex_tooLarge() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(2, FheType.Uint32, 1, 456, uint64(block.chainid));
        bytes memory proof = _proofWithSignatures(handles, new bytes[](0), EXTRA_DATA);

        vm.expectRevert(InputVerifier.InvalidIndex.selector);
        executor.verifyInput(handles[0], USER, proof, FheType.Uint32);
    }

    function test_verifyInput_revert_invalidIndex_above254() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(2, FheType.Uint32, 255, 457, uint64(block.chainid));
        bytes memory proof = _proofWithSignatures(handles, new bytes[](0), EXTRA_DATA);

        vm.expectRevert(InputVerifier.InvalidIndex.selector);
        executor.verifyInput(handles[0], USER, proof, FheType.Uint32);
    }

    function test_verifyInput_revert_invalidHandleVersion() public {
        bytes32 validHandle = _inputHandle(9, FheType.Uint64, 0, 77, uint64(block.chainid));
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = bytes32((uint256(validHandle) & ~uint256(0xff)) | uint256(1));
        bytes memory proof = _proofWithSignatures(handles, new bytes[](0), EXTRA_DATA);

        vm.expectRevert(InputVerifier.InvalidHandleVersion.selector);
        executor.verifyInput(validHandle, USER, proof, FheType.Uint64);
    }

    function test_verifyInput_revert_invalidInputHandle() public {
        bytes32 inputHandle = _inputHandle(9, FheType.Uint64, 0, 77, uint64(block.chainid));
        bytes32[] memory proofHandles = new bytes32[](1);
        proofHandles[0] = _inputHandle(10, FheType.Uint64, 0, 78, uint64(block.chainid));
        bytes memory proof = _proofSingleSigner(proofHandles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        vm.expectRevert(InputVerifier.InvalidInputHandle.selector);
        executor.verifyInput(inputHandle, USER, proof, FheType.Uint64);
    }

    function test_verifyInput_revert_invalidSigner() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(1, FheType.Uint8, 0, 91, uint64(block.chainid));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_KMS_SIGNER_PK);

        vm.expectRevert(abi.encodeWithSelector(InputVerifier.InvalidSigner.selector, vm.addr(MOCK_KMS_SIGNER_PK)));
        executor.verifyInput(handles[0], USER, proof, FheType.Uint8);
    }

    function test_verifyInput_revert_signatureThresholdNotReached() public {
        address[] memory signers = new address[](2);
        signers[0] = mockInputSigner;
        signers[1] = vm.addr(MOCK_KMS_SIGNER_PK);
        vm.prank(OWNER);
        inputVerifierContract.defineNewContext(signers, 2);

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(3, FheType.Uint16, 0, 20, uint64(block.chainid));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        vm.expectRevert(abi.encodeWithSelector(InputVerifier.SignatureThresholdNotReached.selector, 1));
        executor.verifyInput(handles[0], USER, proof, FheType.Uint16);
    }

    function test_verifyInput_revert_invalidType() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(4, FheType.Uint32, 0, 21, uint64(block.chainid));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        vm.expectRevert(FHEVMExecutor.InvalidType.selector);
        executor.verifyInput(handles[0], USER, proof, FheType.Uint16);
    }

    function test_verifyInput_revert_zeroSignature() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(2, FheType.Uint32, 0, 457, uint64(block.chainid));
        bytes memory proof = _proofWithSignatures(handles, new bytes[](0), EXTRA_DATA);

        vm.expectRevert(InputVerifier.ZeroSignature.selector);
        executor.verifyInput(handles[0], USER, proof, FheType.Uint32);
    }

    function test_helper_domainSeparator_matchesDeployedDomain() public view {
        (,,,, address verifyingContract,,) = inputVerifierContract.eip712Domain();
        bytes32 helperDomain = InputProofHelper.computeInputVerifierDomainSeparator(verifyingContract, block.chainid);
        bytes32 deployedDomain = _domainSeparator();
        assertEq(helperDomain, deployedDomain);
    }
}
