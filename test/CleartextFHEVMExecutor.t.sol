// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {fhevmExecutorAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {CleartextArithmetic} from "../src/cleartext/CleartextArithmetic.sol";
import {CleartextFHEVMExecutor} from "../src/cleartext/CleartextFHEVMExecutor.sol";
import {InputProofTestHelper} from "./helpers/InputProofTestHelper.sol";

contract CleartextFHEVMExecutorTest is InputProofTestHelper {
    address internal constant USER = address(0xA11CE);

    CleartextFHEVMExecutor internal clearExecutor;

    function setUp() public {
        _deployInputVerifierStack();

        address clearExecutorImpl = address(new CleartextFHEVMExecutor());
        vm.prank(OWNER);
        EmptyUUPSProxy(fhevmExecutorAdd).upgradeToAndCall(clearExecutorImpl, bytes(""));

        clearExecutor = CleartextFHEVMExecutor(fhevmExecutorAdd);
    }

    // ──────────────────────────────────────────────
    //  Exhaustiveness — every op branch is wired
    // ──────────────────────────────────────────────

    function test_allBinaryOps_store_plaintext() public {
        bytes32 lhs = clearExecutor.trivialEncrypt(10, FheType.Uint8);
        bytes32 rhs = clearExecutor.trivialEncrypt(3, FheType.Uint8);
        bytes1 ct = bytes1(0x00);
        bytes1 sc = bytes1(0x01);

        // Arithmetic
        _assertStored(clearExecutor.fheAdd(lhs, rhs, ct));
        _assertStored(clearExecutor.fheSub(lhs, rhs, ct));
        _assertStored(clearExecutor.fheMul(lhs, rhs, ct));
        _assertStored(clearExecutor.fheDiv(lhs, bytes32(uint256(3)), sc));
        _assertStored(clearExecutor.fheRem(lhs, bytes32(uint256(3)), sc));

        // Bitwise
        _assertStored(clearExecutor.fheBitAnd(lhs, rhs, ct));
        _assertStored(clearExecutor.fheBitOr(lhs, rhs, ct));
        _assertStored(clearExecutor.fheBitXor(lhs, rhs, ct));
        _assertStored(clearExecutor.fheShl(lhs, rhs, ct));
        _assertStored(clearExecutor.fheShr(lhs, rhs, ct));
        _assertStored(clearExecutor.fheRotl(lhs, rhs, ct));
        _assertStored(clearExecutor.fheRotr(lhs, rhs, ct));

        // Comparison
        _assertStored(clearExecutor.fheEq(lhs, rhs, ct));
        _assertStored(clearExecutor.fheNe(lhs, rhs, ct));
        _assertStored(clearExecutor.fheGe(lhs, rhs, ct));
        _assertStored(clearExecutor.fheGt(lhs, rhs, ct));
        _assertStored(clearExecutor.fheLe(lhs, rhs, ct));
        _assertStored(clearExecutor.fheLt(lhs, rhs, ct));

        // Min/Max
        _assertStored(clearExecutor.fheMin(lhs, rhs, ct));
        _assertStored(clearExecutor.fheMax(lhs, rhs, ct));
    }

    function test_allUnaryOps_store_plaintext() public {
        bytes32 ct = clearExecutor.trivialEncrypt(5, FheType.Uint8);

        _assertStored(clearExecutor.fheNeg(ct));
        _assertStored(clearExecutor.fheNot(ct));
    }

    function test_ternaryOp_stores_plaintext() public {
        bytes32 control = clearExecutor.trivialEncrypt(1, FheType.Bool);
        bytes32 ifTrue = clearExecutor.trivialEncrypt(11, FheType.Uint8);
        bytes32 ifFalse = clearExecutor.trivialEncrypt(22, FheType.Uint8);

        bytes32 result = clearExecutor.fheIfThenElse(control, ifTrue, ifFalse);
        assertEq(clearExecutor.plaintexts(result), 11);
    }

    // ──────────────────────────────────────────────
    //  Rand
    // ──────────────────────────────────────────────

    function test_fheRand_stores_plaintext() public {
        bytes32 result = clearExecutor.fheRand(FheType.Uint8);
        _assertStored(result);
    }

    function test_fheRandBounded_stores_plaintext() public {
        bytes32 result = clearExecutor.fheRandBounded(16, FheType.Uint8);
        _assertStored(result);
    }

    // ──────────────────────────────────────────────
    //  Cast & trivialEncrypt
    // ──────────────────────────────────────────────

    function test_cast_and_trivialEncrypt_normalize_plaintext() public {
        bytes32 boolCt = clearExecutor.trivialEncrypt(0x0100, FheType.Bool);
        bytes32 casted = clearExecutor.cast(boolCt, FheType.Uint8);

        assertEq(clearExecutor.plaintexts(boolCt), 0);
        assertEq(clearExecutor.plaintexts(casted), 0);
    }

    function test_cleartextArithmetic_cast_to_bool_uses_gt_zero_semantics() public pure {
        assertEq(CleartextArithmetic.fheCast(0, uint8(FheType.Bool)), 0);
        assertEq(CleartextArithmetic.fheCast(2, uint8(FheType.Bool)), 1);
        assertEq(CleartextArithmetic.fheCast(0x0100, uint8(FheType.Bool)), 1);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _assertStored(bytes32 handle) internal view {
        // A missing branch in _computeBinaryResult/_computeUnaryResult
        // reverts with UnsupportedCleartext*Op — reaching here = wired.
        clearExecutor.plaintexts(handle);
    }

    // ──────────────────────────────────────────────
    //  verifyInput
    // ──────────────────────────────────────────────

    function test_verifyInput_stores_plaintext_from_proof() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(2, FheType.Bool, 0, 201, uint64(block.chainid));

        bytes memory extraData = abi.encodePacked(bytes32(uint256(2)));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), extraData, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = clearExecutor.verifyInput(handles[0], USER, proof, FheType.Bool);

        assertEq(verified, handles[0]);
        assertEq(clearExecutor.plaintexts(verified), 1);
    }

    function test_verifyInput_normalizes_bool_cleartext() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(2, FheType.Bool, 0, 201, uint64(block.chainid));

        bytes memory extraData = abi.encodePacked(bytes32(uint256(0x0100)));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), extraData, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = clearExecutor.verifyInput(handles[0], USER, proof, FheType.Bool);

        assertEq(verified, handles[0]);
        assertEq(clearExecutor.plaintexts(verified), 0);
    }

    function test_verifyInput_reads_correct_handle_index() public {
        bytes32[] memory handles = new bytes32[](2);
        handles[0] = _inputHandle(1, FheType.Bool, 0, 201, uint64(block.chainid));
        handles[1] = _inputHandle(0, FheType.Bool, 1, 202, uint64(block.chainid));

        bytes memory extraData = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(0x0100)));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), extraData, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = clearExecutor.verifyInput(handles[1], USER, proof, FheType.Bool);

        assertEq(verified, handles[1]);
        assertEq(clearExecutor.plaintexts(verified), 0);
    }

    function test_verifyInput_without_cleartext_suffix_leaves_plaintext_zero() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(1, FheType.Uint8, 0, 203, uint64(block.chainid));

        bytes memory proof = _proofSingleSigner(handles, USER, address(this), hex"", MOCK_INPUT_SIGNER_PK);

        bytes32 verified = clearExecutor.verifyInput(handles[0], USER, proof, FheType.Uint8);

        assertEq(verified, handles[0]);
        assertEq(clearExecutor.plaintexts(verified), 0);
    }
}
