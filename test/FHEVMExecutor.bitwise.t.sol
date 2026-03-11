// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ExecutorDeployer} from "./helpers/ExecutorDeployer.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";

contract FHEVMExecutorBitwiseTest is ExecutorDeployer {
    function setUp() public {
        _deployExecutorStack();
    }

    // ──────────────────────────────────────────────
    //  fheBitAnd
    // ──────────────────────────────────────────────

    function test_fheBitAnd_scalar_uint8() public {
        bytes32 lhs = _trivialEncrypt(0xF0, FheType.Uint8);
        bytes32 result = executor.fheBitAnd(lhs, bytes32(uint256(0x0F)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0x00);
    }

    function test_fheBitAnd_scalar_truncates_rhs() public {
        // Scalar 0x1FF truncates to 0xFF for euint8, so 0xF0 & 0xFF = 0xF0.
        bytes32 lhs = _trivialEncrypt(0xF0, FheType.Uint8);
        bytes32 result = executor.fheBitAnd(lhs, bytes32(uint256(0x1FF)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0xF0);
    }

    function test_fheBitAnd_encEnc_uint8() public {
        bytes32 lhs = _trivialEncrypt(0xFF, FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(0x0F, FheType.Uint8);
        bytes32 result = executor.fheBitAnd(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 0x0F);
    }

    function test_fheBitAnd_bool() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 rhs = _trivialEncrypt(0, FheType.Bool);
        bytes32 result = executor.fheBitAnd(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheBitAnd_bool_scalar_high_byte_nonzero_is_true() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheBitAnd(lhs, bytes32(uint256(0x0100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheBitAnd_uint256() public {
        bytes32 lhs = _trivialEncrypt(type(uint256).max, FheType.Uint256);
        bytes32 result = executor.fheBitAnd(lhs, bytes32(uint256(0xFF)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0xFF);
    }

    // ──────────────────────────────────────────────
    //  fheBitOr
    // ──────────────────────────────────────────────

    function test_fheBitOr_scalar_uint8() public {
        bytes32 lhs = _trivialEncrypt(0xF0, FheType.Uint8);
        bytes32 result = executor.fheBitOr(lhs, bytes32(uint256(0x0F)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0xFF);
    }

    function test_fheBitOr_bool() public {
        bytes32 lhs = _trivialEncrypt(0, FheType.Bool);
        bytes32 rhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheBitOr(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheBitOr_bool_scalar_high_byte_nonzero_is_true() public {
        bytes32 lhs = _trivialEncrypt(0, FheType.Bool);
        bytes32 result = executor.fheBitOr(lhs, bytes32(uint256(0x0100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    // ──────────────────────────────────────────────
    //  fheBitXor
    // ──────────────────────────────────────────────

    function test_fheBitXor_scalar_uint8() public {
        bytes32 lhs = _trivialEncrypt(0xFF, FheType.Uint8);
        bytes32 result = executor.fheBitXor(lhs, bytes32(uint256(0xFF)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0x00);
    }

    function test_fheBitXor_bool() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 rhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheBitXor(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheBitXor_bool_scalar_high_byte_nonzero_is_true() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheBitXor(lhs, bytes32(uint256(0x0100)), bytes1(0x01));
        assertEq(_readPlaintext(result), 0);
    }

    // ──────────────────────────────────────────────
    //  fheShl
    // ──────────────────────────────────────────────

    function test_fheShl_scalar_uint8() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Uint8);
        bytes32 result = executor.fheShl(lhs, bytes32(uint256(4)), bytes1(0x01));
        assertEq(_readPlaintext(result), 16);
    }

    function test_fheShl_bounded_shift() public {
        // Shift amount bounded to bitWidth: shift 10 on uint8 → shift 10%8 = 2
        bytes32 lhs = _trivialEncrypt(1, FheType.Uint8);
        bytes32 result = executor.fheShl(lhs, bytes32(uint256(10)), bytes1(0x01));
        // 1 << 2 = 4
        assertEq(_readPlaintext(result), 4);
    }

    function test_fheShl_shift_zero() public {
        bytes32 lhs = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.fheShl(lhs, bytes32(uint256(0)), bytes1(0x01));
        assertEq(_readPlaintext(result), 42);
    }

    function test_fheShl_revert_unsupportedType_bool() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.fheShl(lhs, bytes32(uint256(1)), bytes1(0x01));
    }

    // ──────────────────────────────────────────────
    //  fheShr
    // ──────────────────────────────────────────────

    function test_fheShr_scalar_uint8() public {
        bytes32 lhs = _trivialEncrypt(128, FheType.Uint8);
        bytes32 result = executor.fheShr(lhs, bytes32(uint256(4)), bytes1(0x01));
        assertEq(_readPlaintext(result), 8);
    }

    function test_fheShr_bounded_shift() public {
        bytes32 lhs = _trivialEncrypt(255, FheType.Uint8);
        // shift 9 on uint8 → shift 9%8 = 1
        bytes32 result = executor.fheShr(lhs, bytes32(uint256(9)), bytes1(0x01));
        assertEq(_readPlaintext(result), 127);
    }

    function test_fheShr_truncated_input() public {
        // trivialEncrypt(300, u8) truncates to 44. 44 >> 1 = 22
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheShr(lhs, bytes32(uint256(1)), bytes1(0x01));
        assertEq(_readPlaintext(result), 22);
    }

    // ──────────────────────────────────────────────
    //  fheRotl
    // ──────────────────────────────────────────────

    function test_fheRotl_uint8() public {
        // 0b10000001 rotated left by 1 = 0b00000011
        bytes32 lhs = _trivialEncrypt(0x81, FheType.Uint8);
        bytes32 result = executor.fheRotl(lhs, bytes32(uint256(1)), bytes1(0x01));
        // 0x81 = 129 = 10000001, rotl(1) = 00000011 = 3
        assertEq(_readPlaintext(result), 3);
    }

    function test_fheRotl_fullRotation() public {
        // Rotating by bitWidth should return the same value
        bytes32 lhs = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.fheRotl(lhs, bytes32(uint256(8)), bytes1(0x01));
        // 8 % 8 = 0, so no rotation
        assertEq(_readPlaintext(result), 42);
    }

    function test_fheRotl_truncated_input() public {
        // trivialEncrypt(300, u8) truncates to 44 = 0b00101100
        // rotl(1) = 0b01011000 = 88
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheRotl(lhs, bytes32(uint256(1)), bytes1(0x01));
        assertEq(_readPlaintext(result), 88);
    }

    // ──────────────────────────────────────────────
    //  fheRotr
    // ──────────────────────────────────────────────

    function test_fheRotr_uint8() public {
        // 0b00000011 rotated right by 1 = 0b10000001
        bytes32 lhs = _trivialEncrypt(3, FheType.Uint8);
        bytes32 result = executor.fheRotr(lhs, bytes32(uint256(1)), bytes1(0x01));
        // 3 = 00000011, rotr(1) = 10000001 = 129
        assertEq(_readPlaintext(result), 129);
    }

    function test_fheRotr_fullRotation() public {
        bytes32 lhs = _trivialEncrypt(42, FheType.Uint8);
        bytes32 result = executor.fheRotr(lhs, bytes32(uint256(8)), bytes1(0x01));
        assertEq(_readPlaintext(result), 42);
    }

    function test_fheRotr_truncated_input() public {
        // trivialEncrypt(300, u8) truncates to 44 = 0b00101100
        // rotr(1) = 0b00010110 = 22
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheRotr(lhs, bytes32(uint256(1)), bytes1(0x01));
        assertEq(_readPlaintext(result), 22);
    }

    // ──────────────────────────────────────────────
    //  Fuzz tests
    // ──────────────────────────────────────────────

    function testFuzz_fheBitAnd(uint8 a, uint8 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(uint256(b), FheType.Uint8);
        bytes32 result = executor.fheBitAnd(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), uint256(a & b));
    }

    function testFuzz_fheBitOr(uint8 a, uint8 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(uint256(b), FheType.Uint8);
        bytes32 result = executor.fheBitOr(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), uint256(a | b));
    }

    function testFuzz_fheBitXor(uint8 a, uint8 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(uint256(b), FheType.Uint8);
        bytes32 result = executor.fheBitXor(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), uint256(a ^ b));
    }
}
