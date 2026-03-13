// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ExecutorDeployer} from "./helpers/ExecutorDeployer.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";
import {aclAdd, fhevmExecutorAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";

contract FHEVMExecutorIntegrationTest is ExecutorDeployer {
    function setUp() public {
        _deployExecutorStack();
    }

    // ──────────────────────────────────────────────
    //  Handle determinism
    // ──────────────────────────────────────────────

    function test_handleDeterminism_sameInputs_sameHandle() public {
        // trivialEncrypt is deterministic: same pt + type → same handle
        bytes32 h1 = executor.trivialEncrypt(42, FheType.Uint8);
        bytes32 h2 = executor.trivialEncrypt(42, FheType.Uint8);
        assertEq(h1, h2, "Same inputs should produce same handle");
    }

    function test_handleUniqueness_differentOps() public {
        bytes32 h1 = executor.trivialEncrypt(42, FheType.Uint8);
        bytes32 h2 = executor.trivialEncrypt(43, FheType.Uint8);
        assertTrue(h1 != h2, "Different inputs should produce different handles");
    }

    function test_handleUniqueness_differentTypes() public {
        bytes32 h1 = executor.trivialEncrypt(42, FheType.Uint8);
        bytes32 h2 = executor.trivialEncrypt(42, FheType.Uint16);
        assertTrue(h1 != h2, "Different types should produce different handles");
    }

    // ──────────────────────────────────────────────
    //  ACL auto-grant
    // ──────────────────────────────────────────────

    function test_aclAutoGrant_trivialEncrypt() public {
        bytes32 handle = executor.trivialEncrypt(42, FheType.Uint8);
        // After trivialEncrypt, this test contract should have transient permission
        assertTrue(
            aclContract.allowedTransient(handle, address(this)), "Should have transient permission after trivialEncrypt"
        );
    }

    function test_aclAutoGrant_binaryOp() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(20, FheType.Uint8);
        bytes32 result = executor.fheAdd(lhs, rhs, bytes1(0x00));
        assertTrue(aclContract.allowedTransient(result, address(this)), "Should have transient permission on result");
    }

    function test_aclAutoGrant_unaryOp() public {
        bytes32 ct = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheNeg(ct);
        assertTrue(
            aclContract.allowedTransient(result, address(this)), "Should have transient permission on negation result"
        );
    }

    // ──────────────────────────────────────────────
    //  Type tracking
    // ──────────────────────────────────────────────

    function test_typeTracking_trivialEncrypt() public {
        bytes32 handle = executor.trivialEncrypt(42, FheType.Uint64);
        assertEq(uint8(handle[30]), uint8(FheType.Uint64), "Handle byte 30 should encode Uint64");
    }

    function test_typeTracking_comparison_returnsBool() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint64);
        bytes32 result = executor.fheGt(lhs, bytes32(uint256(5)), bytes1(0x01));
        assertEq(uint8(result[30]), uint8(FheType.Bool), "Comparison should return Bool type");
    }

    function test_typeTracking_minMax_returnsInputType() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint128);
        bytes32 rhs = _trivialEncrypt(20, FheType.Uint128);
        bytes32 result = executor.fheMin(lhs, rhs, bytes1(0x00));
        assertEq(uint8(result[30]), uint8(FheType.Uint128), "fheMin should return input type");
    }

    function test_typeTracking_cast_changesType() public {
        bytes32 ct = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.cast(ct, FheType.Uint64);
        assertEq(uint8(result[30]), uint8(FheType.Uint64), "Cast should change handle type");
    }

    // ──────────────────────────────────────────────
    //  Truncation at encrypt time (real coprocessor semantics)
    // ──────────────────────────────────────────────

    function test_truncation_atEncryptTime() public {
        // Real coprocessor truncates at trivialEncrypt: 300 → 44 for euint8
        bytes32 lhs = executor.trivialEncrypt(300, FheType.Uint8);
        assertEq(_readPlaintext(lhs), 44, "trivialEncrypt should truncate to type width");

        // fheAdd operates on already-in-range value: 44 + 1 = 45
        bytes32 result = executor.fheAdd(lhs, bytes32(uint256(1)), bytes1(0x01));
        assertEq(_readPlaintext(result), 45, "fheAdd on truncated input");
    }

    // ──────────────────────────────────────────────
    //  Chained operations
    // ──────────────────────────────────────────────

    function test_chainedOperations() public {
        // Chain: trivialEncrypt(200, uint8) → fheAdd(+100) → fheMul(*2)
        bytes32 h1 = _trivialEncrypt(200, FheType.Uint8);
        // 200 + 100 = 300 → clamped to 44
        bytes32 h2 = executor.fheAdd(h1, bytes32(uint256(100)), bytes1(0x01));
        assertEq(_readPlaintext(h2), 44, "200 + 100 should wrap to 44 for uint8");

        // 44 * 2 = 88
        bytes32 h3 = executor.fheMul(h2, bytes32(uint256(2)), bytes1(0x01));
        assertEq(_readPlaintext(h3), 88, "44 * 2 should be 88");
    }

    function test_chainedOperations_comparison() public {
        bytes32 a = _trivialEncrypt(100, FheType.Uint8);
        bytes32 b = _trivialEncrypt(50, FheType.Uint8);

        // a + b = 150
        bytes32 sum = executor.fheAdd(a, b, bytes1(0x00));
        assertEq(_readPlaintext(sum), 150);

        // sum > 100 → true
        bytes32 gt = executor.fheGt(sum, bytes32(uint256(100)), bytes1(0x01));
        assertEq(_readPlaintext(gt), 1);

        // use the comparison result in fheIfThenElse
        bytes32 ifTrue = _trivialEncrypt(1, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(0, FheType.Uint8);
        bytes32 selected = executor.fheIfThenElse(gt, ifTrue, ifFalse);
        assertEq(_readPlaintext(selected), 1);
    }

    // ──────────────────────────────────────────────
    //  Handle format
    // ──────────────────────────────────────────────

    function test_handleFormat_byte21_0xff() public {
        bytes32 handle = executor.trivialEncrypt(42, FheType.Uint8);
        // Byte 21 should be 0xff (computed handle marker)
        assertEq(uint8(handle[21]), 0xff, "Byte 21 should be 0xff for computed handles");
    }

    function test_handleFormat_chainId() public {
        bytes32 handle = executor.trivialEncrypt(42, FheType.Uint8);
        // Extract chainId from bytes 22-29 (big-endian uint64)
        uint64 chainIdFromHandle;
        for (uint256 i = 22; i < 30; i++) {
            chainIdFromHandle = (chainIdFromHandle << 8) | uint64(uint8(handle[i]));
        }
        assertEq(chainIdFromHandle, uint64(block.chainid), "ChainId in handle should match block.chainid");
    }

    function test_handleFormat_version() public {
        bytes32 handle = executor.trivialEncrypt(42, FheType.Uint8);
        assertEq(uint8(handle[31]), 0, "Version byte should be 0");
    }

    // ──────────────────────────────────────────────
    //  ACL validation order
    // ──────────────────────────────────────────────

    function test_aclValidation_binaryOp_lhs() public {
        // Create a handle that msg.sender does NOT have permission on
        bytes32 fakeHandle = bytes32(uint256(0xdead));
        // Append valid metadata so type extraction works
        fakeHandle = fakeHandle & 0xffffffffffffffffffffffffffffffffffffffffff0000000000000000000000;
        fakeHandle = fakeHandle | (bytes32(uint256(0xff)) << 80);
        fakeHandle = fakeHandle | (bytes32(uint256(uint64(block.chainid))) << 16);
        fakeHandle = fakeHandle | (bytes32(uint256(uint8(FheType.Uint8))) << 8);

        vm.expectRevert(abi.encodeWithSelector(FHEVMExecutor.ACLNotAllowed.selector, fakeHandle, address(this)));
        executor.fheAdd(fakeHandle, bytes32(uint256(1)), bytes1(0x01));
    }

    function test_aclValidation_binaryOp_rhs() public {
        // LHS: this contract has permission (via trivialEncrypt)
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);

        // RHS: create a handle from a different sender so `this` has no permission on it
        address otherSender = address(0xCAFE);
        vm.prank(otherSender);
        bytes32 rhs = executor.trivialEncrypt(20, FheType.Uint8);

        // enc-enc mode (scalar=0x00): should revert with ACLNotAllowed on rhs
        vm.expectRevert(abi.encodeWithSelector(FHEVMExecutor.ACLNotAllowed.selector, rhs, address(this)));
        executor.fheAdd(lhs, rhs, bytes1(0x00));
    }

    function test_aclValidation_encEnc_incompatibleTypes() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(20, FheType.Uint16);
        vm.expectRevert(FHEVMExecutor.IncompatibleTypes.selector);
        executor.fheAdd(lhs, rhs, bytes1(0x00));
    }

    function test_aclValidation_binaryOp_rhs_nonExistentHandle() public {
        // LHS: this contract has permission
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);

        // RHS: fabricate a handle that doesn't exist in the DB (never created by any operation)
        bytes32 fakeRhs = bytes32(uint256(0xdeadbeef));
        fakeRhs = fakeRhs & 0xffffffffffffffffffffffffffffffffffffffffff0000000000000000000000;
        fakeRhs = fakeRhs | (bytes32(uint256(0xff)) << 80);
        fakeRhs = fakeRhs | (bytes32(uint256(uint64(block.chainid))) << 16);
        fakeRhs = fakeRhs | (bytes32(uint256(uint8(FheType.Uint8))) << 8);

        // enc-enc mode: should revert with ACLNotAllowed on rhs (no one has permission on a fabricated handle)
        vm.expectRevert(abi.encodeWithSelector(FHEVMExecutor.ACLNotAllowed.selector, fakeRhs, address(this)));
        executor.fheAdd(lhs, fakeRhs, bytes1(0x00));
    }

    function test_aclValidation_cast_revert() public {
        // Create a handle from a different sender so `this` has no permission
        address otherSender = address(0xCAFE);
        vm.prank(otherSender);
        bytes32 ct = executor.trivialEncrypt(42, FheType.Uint8);

        vm.expectRevert(abi.encodeWithSelector(FHEVMExecutor.ACLNotAllowed.selector, ct, address(this)));
        executor.cast(ct, FheType.Uint64);
    }

    function test_aclValidation_fheIfThenElse_revert_control() public {
        // control: no permission for this contract
        address otherSender = address(0xCAFE);
        vm.prank(otherSender);
        bytes32 control = executor.trivialEncrypt(1, FheType.Bool);

        bytes32 ifTrue = _trivialEncrypt(42, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(99, FheType.Uint8);

        vm.expectRevert(abi.encodeWithSelector(FHEVMExecutor.ACLNotAllowed.selector, control, address(this)));
        executor.fheIfThenElse(control, ifTrue, ifFalse);
    }

    function test_aclValidation_fheIfThenElse_revert_ifTrue() public {
        bytes32 control = _trivialEncrypt(1, FheType.Bool);

        // ifTrue: no permission for this contract
        address otherSender = address(0xCAFE);
        vm.prank(otherSender);
        bytes32 ifTrue = executor.trivialEncrypt(42, FheType.Uint8);

        bytes32 ifFalse = _trivialEncrypt(99, FheType.Uint8);

        vm.expectRevert(abi.encodeWithSelector(FHEVMExecutor.ACLNotAllowed.selector, ifTrue, address(this)));
        executor.fheIfThenElse(control, ifTrue, ifFalse);
    }

    function test_aclValidation_fheIfThenElse_revert_ifFalse() public {
        bytes32 control = _trivialEncrypt(1, FheType.Bool);
        bytes32 ifTrue = _trivialEncrypt(42, FheType.Uint8);

        // ifFalse: no permission for this contract
        address otherSender = address(0xCAFE);
        vm.prank(otherSender);
        bytes32 ifFalse = executor.trivialEncrypt(99, FheType.Uint8);

        vm.expectRevert(abi.encodeWithSelector(FHEVMExecutor.ACLNotAllowed.selector, ifFalse, address(this)));
        executor.fheIfThenElse(control, ifTrue, ifFalse);
    }

    // ──────────────────────────────────────────────
    //  Executor address and ACL wiring
    // ──────────────────────────────────────────────

    function test_executorDeployedAtKnownAddress() public view {
        assertEq(address(executor), fhevmExecutorAdd, "Executor should be at known address");
    }

    function test_aclDeployedAtKnownAddress() public view {
        assertEq(address(aclContract), aclAdd, "ACL should be at known address");
    }

    function test_executorReportsCorrectACL() public view {
        assertEq(executor.getACLAddress(), aclAdd, "Executor should report correct ACL address");
    }

    // ──────────────────────────────────────────────
    //  fheRand ACL auto-grant
    // ──────────────────────────────────────────────

    function test_aclAutoGrant_fheRand() public {
        bytes32 result = executor.fheRand(FheType.Uint8);
        assertTrue(
            aclContract.allowedTransient(result, address(this)), "fheRand should grant transient permission on result"
        );
    }

    function test_aclAutoGrant_fheRandBounded() public {
        bytes32 result = executor.fheRandBounded(16, FheType.Uint8);
        assertTrue(
            aclContract.allowedTransient(result, address(this)),
            "fheRandBounded should grant transient permission on result"
        );
    }

    // ──────────────────────────────────────────────
    //  All-types support verification
    // ──────────────────────────────────────────────

    function test_allTypes_fheAdd_uint128() public {
        bytes32 lhs = _trivialEncrypt(type(uint128).max, FheType.Uint128);
        bytes32 result = executor.fheAdd(lhs, bytes32(uint256(1)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0, "uint128 max + 1 should wrap to 0");
    }
}
