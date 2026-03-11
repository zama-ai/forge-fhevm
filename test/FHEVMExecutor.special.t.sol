// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ExecutorDeployer} from "./helpers/ExecutorDeployer.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";

contract FHEVMExecutorSpecialTest is ExecutorDeployer {
    function setUp() public {
        _deployExecutorStack();
    }

    // ──────────────────────────────────────────────
    //  trivialEncrypt
    // ──────────────────────────────────────────────

    function test_trivialEncrypt_basic() public {
        bytes32 handle = executor.trivialEncrypt(42, FheType.Uint8);
        assertEq(_readPlaintext(handle), 42);
        assertEq(uint8(handle[30]), uint8(FheType.Uint8));
    }

    function test_trivialEncrypt_deterministic() public {
        // Same plaintext + type → same handle
        bytes32 handle1 = executor.trivialEncrypt(42, FheType.Uint8);
        bytes32 handle2 = executor.trivialEncrypt(42, FheType.Uint8);
        assertEq(handle1, handle2);
    }

    function test_trivialEncrypt_truncates() public {
        // Real coprocessor truncates plaintext to target type's bit-width.
        // 300 = 0x012C → last byte = 0x2C = 44
        bytes32 handle = executor.trivialEncrypt(300, FheType.Uint8);
        assertEq(_readPlaintext(handle), 44, "Should truncate 300 to 44 for euint8");
    }

    function test_trivialEncrypt_bool_nonzero_is_true() public {
        // tfhe-rs trivial bool encryption uses `last_byte > 0`, not `value & 1`.
        bytes32 handle = executor.trivialEncrypt(2, FheType.Bool);
        assertEq(_readPlaintext(handle), 1, "Non-zero bool plaintext should normalize to true");
    }

    function test_trivialEncrypt_bool_high_byte_only_is_false() public {
        bytes32 handle = executor.trivialEncrypt(0x0100, FheType.Bool);
        assertEq(_readPlaintext(handle), 0, "Bool trivialEncrypt should only inspect the low byte");
    }

    function test_trivialEncrypt_allTypes() public {
        executor.trivialEncrypt(1, FheType.Bool);
        executor.trivialEncrypt(42, FheType.Uint8);
        executor.trivialEncrypt(1000, FheType.Uint16);
        executor.trivialEncrypt(100000, FheType.Uint32);
        executor.trivialEncrypt(1e18, FheType.Uint64);
        executor.trivialEncrypt(1e30, FheType.Uint128);
        executor.trivialEncrypt(uint256(uint160(address(0xdead))), FheType.Uint160);
        executor.trivialEncrypt(type(uint256).max, FheType.Uint256);
    }

    function test_trivialEncrypt_revert_unsupportedType() public {
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.trivialEncrypt(42, FheType.Uint4); // Uint4 not supported
    }

    // ──────────────────────────────────────────────
    //  cast
    // ──────────────────────────────────────────────

    function test_cast_upcast() public {
        bytes32 ct = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.cast(ct, FheType.Uint64);
        assertEq(_readPlaintext(result), 42);
        assertEq(uint8(result[30]), uint8(FheType.Uint64));
    }

    function test_cast_downcast_clamps() public {
        bytes32 ct = _trivialEncrypt(300, FheType.Uint16);
        bytes32 result = executor.cast(ct, FheType.Uint8);
        // 300 % 256 = 44
        assertEq(_readPlaintext(result), 44);
        assertEq(uint8(result[30]), uint8(FheType.Uint8));
    }

    /// @dev The real coprocessor supports cast-to-Bool (via inp.gt(0)), but the
    ///      Solidity host contract intentionally blocks it (use fheNe instead).
    ///      When using public `cast` this should revert.
    function test_cast_revert_toBool() public {
        bytes32 ct = _trivialEncrypt(42, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.cast(ct, FheType.Bool);
    }

    function test_cast_revert_sameType() public {
        bytes32 ct = _trivialEncrypt(42, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.InvalidType.selector);
        executor.cast(ct, FheType.Uint8);
    }

    function test_cast_fromBool() public {
        bytes32 ct = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.cast(ct, FheType.Uint8);
        assertEq(_readPlaintext(result), 1);
    }

    // ──────────────────────────────────────────────
    //  fheIfThenElse
    // ──────────────────────────────────────────────

    function test_fheIfThenElse_true() public {
        bytes32 control = _trivialEncrypt(1, FheType.Bool);
        bytes32 ifTrue = _trivialEncrypt(42, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(99, FheType.Uint8);
        bytes32 result = executor.fheIfThenElse(control, ifTrue, ifFalse);
        assertEq(_readPlaintext(result), 42);
        assertEq(uint8(result[30]), uint8(FheType.Uint8), "Result should be ifTrue type, not Bool");
    }

    function test_fheIfThenElse_false() public {
        bytes32 control = _trivialEncrypt(0, FheType.Bool);
        bytes32 ifTrue = _trivialEncrypt(42, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(99, FheType.Uint8);
        bytes32 result = executor.fheIfThenElse(control, ifTrue, ifFalse);
        assertEq(_readPlaintext(result), 99);
    }

    function test_fheIfThenElse_revert_controlNotBool() public {
        bytes32 control = _trivialEncrypt(1, FheType.Uint8);
        bytes32 ifTrue = _trivialEncrypt(42, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(99, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.fheIfThenElse(control, ifTrue, ifFalse);
    }

    function test_fheIfThenElse_revert_typeMismatch() public {
        bytes32 control = _trivialEncrypt(1, FheType.Bool);
        bytes32 ifTrue = _trivialEncrypt(42, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(99, FheType.Uint16);
        vm.expectRevert(FHEVMExecutor.IncompatibleTypes.selector);
        executor.fheIfThenElse(control, ifTrue, ifFalse);
    }

    function test_fheIfThenElse_uint160() public {
        bytes32 control = _trivialEncrypt(1, FheType.Bool);
        bytes32 ifTrue = _trivialEncrypt(uint256(uint160(address(0xdead))), FheType.Uint160);
        bytes32 ifFalse = _trivialEncrypt(uint256(uint160(address(0xbeef))), FheType.Uint160);
        bytes32 result = executor.fheIfThenElse(control, ifTrue, ifFalse);
        assertEq(_readPlaintext(result), uint256(uint160(address(0xdead))));
    }

    function test_fheIfThenElse_noncanonical_bool_normalized_by_trivialEncrypt() public {
        // tfhe-rs trivialEncrypt(Bool) uses `last_byte > 0`, so 2 maps to true.
        bytes32 control = _trivialEncrypt(2, FheType.Bool);
        bytes32 ifTrue = _trivialEncrypt(11, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(22, FheType.Uint8);

        bytes32 result = executor.fheIfThenElse(control, ifTrue, ifFalse);
        assertEq(_readPlaintext(result), 11);
    }

    function test_fheIfThenElse_bool_high_byte_only_selects_false_branch() public {
        bytes32 control = _trivialEncrypt(0x0100, FheType.Bool);
        bytes32 ifTrue = _trivialEncrypt(11, FheType.Uint8);
        bytes32 ifFalse = _trivialEncrypt(22, FheType.Uint8);

        bytes32 result = executor.fheIfThenElse(control, ifTrue, ifFalse);
        assertEq(_readPlaintext(result), 22);
    }

    // ──────────────────────────────────────────────
    //  fheRand
    // ──────────────────────────────────────────────

    function test_fheRand_uint8() public {
        bytes32 result = executor.fheRand(FheType.Uint8);
        assertEq(uint8(result[30]), uint8(FheType.Uint8));
        assertLe(_readPlaintext(result), 255);
    }

    function test_fheRand_bool() public {
        bytes32 result = executor.fheRand(FheType.Bool);
        assertEq(uint8(result[30]), uint8(FheType.Bool));
        assertLe(_readPlaintext(result), 1);
    }

    function test_fheRand_differentValues() public {
        bytes32 r1 = executor.fheRand(FheType.Uint64);
        bytes32 r2 = executor.fheRand(FheType.Uint64);
        // Different handles (different seeds)
        assertTrue(r1 != r2, "Successive fheRand calls should produce different handles");
    }

    function test_fheRand_revert_unsupportedType() public {
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.fheRand(FheType.Uint160); // Uint160 not supported for rand
    }

    // ──────────────────────────────────────────────
    //  fheRandBounded
    // ──────────────────────────────────────────────

    function test_fheRandBounded_basic() public {
        bytes32 result = executor.fheRandBounded(16, FheType.Uint8);
        assertLt(_readPlaintext(result), 16);
    }

    function test_fheRandBounded_revert_notPowerOfTwo() public {
        vm.expectRevert(FHEVMExecutor.NotPowerOfTwo.selector);
        executor.fheRandBounded(7, FheType.Uint8);
    }

    function test_fheRandBounded_revert_zero() public {
        vm.expectRevert(FHEVMExecutor.NotPowerOfTwo.selector);
        executor.fheRandBounded(0, FheType.Uint8);
    }

    function test_fheRandBounded_revert_upperBoundExceedsType() public {
        vm.expectRevert(FHEVMExecutor.UpperBoundAboveMaxTypeValue.selector);
        executor.fheRandBounded(512, FheType.Uint8); // 512 > 256 = 2^8
    }

    function test_fheRandBounded_revert_bool() public {
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.fheRandBounded(1, FheType.Bool);
    }

    function test_fheRandBounded_maxBound() public {
        // upperBound = 256 = 2^8, which equals the max representable+1 for Uint8
        bytes32 result = executor.fheRandBounded(256, FheType.Uint8);
        assertLt(_readPlaintext(result), 256);
    }
}
