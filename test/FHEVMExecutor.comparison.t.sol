// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ExecutorDeployer} from "./helpers/ExecutorDeployer.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";

contract FHEVMExecutorComparisonTest is ExecutorDeployer {
    function setUp() public {
        _deployExecutorStack();
    }

    // ──────────────────────────────────────────────
    //  fheEq
    // ──────────────────────────────────────────────

    function test_fheEq_true() public {
        bytes32 lhs = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.fheEq(lhs, bytes32(uint256(42)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
        // Result handle should have Bool type
        assertEq(uint8(result[30]), uint8(FheType.Bool));
    }

    function test_fheEq_scalar_truncates_rhs() public {
        // Scalar 261 truncates to 5 for euint8, so 5 == 5.
        bytes32 lhs = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheEq(lhs, bytes32(uint256(261)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheEq_false() public {
        bytes32 lhs = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.fheEq(lhs, bytes32(uint256(43)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheEq_uint160() public {
        // eaddress support for fheEq
        bytes32 lhs = _trivialEncrypt(uint256(uint160(address(0xdead))), FheType.Uint160);
        bytes32 result = executor.fheEq(lhs, bytes32(uint256(uint160(address(0xdead)))), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheEq_bool() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 rhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheEq(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheEq_bool_scalar_high_byte_nonzero_is_true() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheEq(lhs, bytes32(uint256(0x0100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    // ──────────────────────────────────────────────
    //  fheNe
    // ──────────────────────────────────────────────

    function test_fheNe_true() public {
        bytes32 lhs = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.fheNe(lhs, bytes32(uint256(43)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheNe_false() public {
        bytes32 lhs = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.fheNe(lhs, bytes32(uint256(42)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheNe_uint160() public {
        bytes32 lhs = _trivialEncrypt(uint256(uint160(address(0xdead))), FheType.Uint160);
        bytes32 result = executor.fheNe(lhs, bytes32(uint256(uint160(address(0xbeef)))), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheNe_bool_scalar_high_byte_nonzero_is_true() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheNe(lhs, bytes32(uint256(0x0100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    // ──────────────────────────────────────────────
    //  fheGe
    // ──────────────────────────────────────────────

    function test_fheGe_greater() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheGe(lhs, bytes32(uint256(5)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheGe_equal() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheGe(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheGe_less() public {
        bytes32 lhs = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheGe(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheGe_revert_uint160() public {
        bytes32 lhs = _trivialEncrypt(uint256(uint160(address(0xdead))), FheType.Uint160);
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.fheGe(lhs, bytes32(uint256(1)), bytes1(0x01));
    }

    // ──────────────────────────────────────────────
    //  fheGt
    // ──────────────────────────────────────────────

    function test_fheGt_true() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheGt(lhs, bytes32(uint256(5)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheGt_equal() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheGt(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheGt_truncated_input() public {
        // trivialEncrypt(300, u8) truncates to 44. scalar 100 truncates to 100.
        // 44 > 100 → false
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheGt(lhs, bytes32(uint256(100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    // ──────────────────────────────────────────────
    //  fheLe
    // ──────────────────────────────────────────────

    function test_fheLe_true() public {
        bytes32 lhs = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheLe(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheLe_equal() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheLe(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    // ──────────────────────────────────────────────
    //  fheLt
    // ──────────────────────────────────────────────

    function test_fheLt_true() public {
        bytes32 lhs = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheLt(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheLt_equal() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheLt(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    // ──────────────────────────────────────────────
    //  fheMin / fheMax
    // ──────────────────────────────────────────────

    function test_fheMin_scalar() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheMin(lhs, bytes32(uint256(5)), bytes1(0x01));
        assertEq(_readPlaintext(result), 5);
        // Min returns input type, not Bool
        assertEq(uint8(result[30]), uint8(FheType.Uint8));
    }

    function test_fheMax_scalar() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheMax(lhs, bytes32(uint256(5)), bytes1(0x01));
        assertEq(_readPlaintext(result), 10);
        assertEq(uint8(result[30]), uint8(FheType.Uint8));
    }

    function test_fheMin_encEnc() public {
        bytes32 lhs = _trivialEncrypt(100, FheType.Uint64);
        bytes32 rhs = _trivialEncrypt(200, FheType.Uint64);
        bytes32 result = executor.fheMin(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 100);
    }

    function test_fheMin_truncated_input() public {
        // trivialEncrypt(300, u8) truncates to 44. scalar 100 truncates to 100.
        // min(44, 100) = 44
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheMin(lhs, bytes32(uint256(100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 44);
    }

    function test_fheMax_encEnc() public {
        bytes32 lhs = _trivialEncrypt(100, FheType.Uint64);
        bytes32 rhs = _trivialEncrypt(200, FheType.Uint64);
        bytes32 result = executor.fheMax(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 200);
    }

    function test_fheMax_truncated_input() public {
        // trivialEncrypt(300, u8) truncates to 44. scalar 100 truncates to 100.
        // max(44, 100) = 100
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheMax(lhs, bytes32(uint256(100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 100);
    }

    // ──────────────────────────────────────────────
    //  Comparison type checks
    // ──────────────────────────────────────────────

    function test_comparison_returnsBoolType() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint64);
        bytes32 result = executor.fheGt(lhs, bytes32(uint256(5)), bytes1(0x01));
        assertEq(uint8(result[30]), uint8(FheType.Bool), "Comparison should return Bool type");
    }

    // ──────────────────────────────────────────────
    //  Fuzz tests
    // ──────────────────────────────────────────────

    function testFuzz_fheGt(uint64 a, uint64 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint64);
        bytes32 result = executor.fheGt(lhs, bytes32(uint256(b)), bytes1(0x01));
        assertEq(_readPlaintext(result), (a > b) ? 1 : 0);
    }

    function testFuzz_fheMin(uint64 a, uint64 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint64);
        bytes32 rhs = _trivialEncrypt(uint256(b), FheType.Uint64);
        bytes32 result = executor.fheMin(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), (a < b) ? uint256(a) : uint256(b));
    }
}
