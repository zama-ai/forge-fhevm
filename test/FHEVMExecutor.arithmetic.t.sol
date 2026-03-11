// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ExecutorDeployer} from "./helpers/ExecutorDeployer.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";

contract FHEVMExecutorArithmeticTest is ExecutorDeployer {
    function setUp() public {
        _deployExecutorStack();
    }

    // ──────────────────────────────────────────────
    //  fheAdd
    // ──────────────────────────────────────────────

    function test_fheAdd_scalar_basic() public {
        bytes32 lhs = _trivialEncrypt(100, FheType.Uint8);
        bytes32 result = executor.fheAdd(lhs, bytes32(uint256(50)), bytes1(0x01));
        assertEq(_readPlaintext(result), 150);
    }

    function test_fheAdd_scalar_overflow_uint8() public {
        bytes32 lhs = _trivialEncrypt(200, FheType.Uint8);
        bytes32 result = executor.fheAdd(lhs, bytes32(uint256(100)), bytes1(0x01));
        // (200 + 100) % 256 = 44
        assertEq(_readPlaintext(result), 44);
    }

    function test_fheAdd_scalar_truncates_rhs() public {
        // Scalar 261 truncates to 5 for euint8, so 5 + 5 = 10.
        bytes32 lhs = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheAdd(lhs, bytes32(uint256(261)), bytes1(0x01));
        assertEq(_readPlaintext(result), 10);
    }

    function test_fheAdd_scalar_truncates_rhs_uint16() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint16);
        bytes32 result = executor.fheAdd(lhs, bytes32(uint256(0x01_0005)), bytes1(0x01));
        assertEq(_readPlaintext(result), 15);
    }

    function test_fheAdd_encEnc_uint16() public {
        bytes32 lhs = _trivialEncrypt(30000, FheType.Uint16);
        bytes32 rhs = _trivialEncrypt(40000, FheType.Uint16);
        bytes32 result = executor.fheAdd(lhs, rhs, bytes1(0x00));
        // (30000 + 40000) % 65536 = 70000 % 65536 = 4464
        assertEq(_readPlaintext(result), 4464);
    }

    function test_fheAdd_revert_unsupportedType_bool() public {
        bytes32 lhs = _trivialEncrypt(1, FheType.Bool);
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.fheAdd(lhs, bytes32(uint256(1)), bytes1(0x01));
    }

    function test_fheAdd_revert_scalarByteNotBoolean() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.ScalarByteIsNotBoolean.selector);
        executor.fheAdd(lhs, bytes32(uint256(5)), bytes1(0x02));
    }

    // ──────────────────────────────────────────────
    //  fheSub
    // ──────────────────────────────────────────────

    function test_fheSub_scalar_basic() public {
        bytes32 lhs = _trivialEncrypt(100, FheType.Uint8);
        bytes32 result = executor.fheSub(lhs, bytes32(uint256(30)), bytes1(0x01));
        assertEq(_readPlaintext(result), 70);
    }

    function test_fheSub_scalar_underflow_uint8() public {
        bytes32 lhs = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheSub(lhs, bytes32(uint256(10)), bytes1(0x01));
        // (5 - 10 + 256) % 256 = 251
        assertEq(_readPlaintext(result), 251);
    }

    function test_fheSub_encEnc_uint32() public {
        bytes32 lhs = _trivialEncrypt(1000, FheType.Uint32);
        bytes32 rhs = _trivialEncrypt(500, FheType.Uint32);
        bytes32 result = executor.fheSub(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 500);
    }

    // ──────────────────────────────────────────────
    //  fheMul
    // ──────────────────────────────────────────────

    function test_fheMul_scalar_basic() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheMul(lhs, bytes32(uint256(20)), bytes1(0x01));
        assertEq(_readPlaintext(result), 200);
    }

    function test_fheMul_scalar_overflow_uint8() public {
        bytes32 lhs = _trivialEncrypt(20, FheType.Uint8);
        bytes32 result = executor.fheMul(lhs, bytes32(uint256(20)), bytes1(0x01));
        // (20 * 20) % 256 = 400 % 256 = 144
        assertEq(_readPlaintext(result), 144);
    }

    function test_fheMul_encEnc_uint64() public {
        bytes32 lhs = _trivialEncrypt(1000000, FheType.Uint64);
        bytes32 rhs = _trivialEncrypt(2000000, FheType.Uint64);
        bytes32 result = executor.fheMul(lhs, rhs, bytes1(0x00));
        assertEq(_readPlaintext(result), 2000000000000);
    }

    // ──────────────────────────────────────────────
    //  fheDiv
    // ──────────────────────────────────────────────

    function test_fheDiv_scalar_basic() public {
        bytes32 lhs = _trivialEncrypt(100, FheType.Uint8);
        bytes32 result = executor.fheDiv(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 10);
    }

    function test_fheDiv_scalar_integerDivision() public {
        bytes32 lhs = _trivialEncrypt(7, FheType.Uint8);
        bytes32 result = executor.fheDiv(lhs, bytes32(uint256(2)), bytes1(0x01));
        assertEq(_readPlaintext(result), 3);
    }

    function test_fheDiv_revert_isNotScalar() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(5, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.IsNotScalar.selector);
        executor.fheDiv(lhs, rhs, bytes1(0x00));
    }

    function test_fheDiv_revert_divisionByZero() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.DivisionByZero.selector);
        executor.fheDiv(lhs, bytes32(uint256(0)), bytes1(0x01));
    }

    // ──────────────────────────────────────────────
    //  fheRem
    // ──────────────────────────────────────────────

    function test_fheRem_scalar_basic() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 result = executor.fheRem(lhs, bytes32(uint256(3)), bytes1(0x01));
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheRem_revert_isNotScalar() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        bytes32 rhs = _trivialEncrypt(3, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.IsNotScalar.selector);
        executor.fheRem(lhs, rhs, bytes1(0x00));
    }

    function test_fheRem_revert_divisionByZero() public {
        bytes32 lhs = _trivialEncrypt(10, FheType.Uint8);
        vm.expectRevert(FHEVMExecutor.DivisionByZero.selector);
        executor.fheRem(lhs, bytes32(uint256(0)), bytes1(0x01));
    }

    function test_fheDiv_scalar_truncated_input() public {
        // trivialEncrypt(300, u8) truncates to 44, scalar 10 fits in u8
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheDiv(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 4); // 44 / 10 = 4
    }

    function test_fheDiv_scalar_truncates_rhs() public {
        // Scalar 266 truncates to 10 for euint8, so 44 / 10 = 4.
        bytes32 lhs = _trivialEncrypt(44, FheType.Uint8);
        bytes32 result = executor.fheDiv(lhs, bytes32(uint256(266)), bytes1(0x01));
        assertEq(_readPlaintext(result), 4);
    }

    function test_fheRem_scalar_truncated_input() public {
        bytes32 lhs = _trivialEncrypt(300, FheType.Uint8);
        bytes32 result = executor.fheRem(lhs, bytes32(uint256(10)), bytes1(0x01));
        assertEq(_readPlaintext(result), 4); // 44 % 10 = 4
    }

    function test_fheRem_scalar_truncates_rhs() public {
        // Scalar 266 truncates to 10 for euint8, so 44 % 10 = 4.
        bytes32 lhs = _trivialEncrypt(44, FheType.Uint8);
        bytes32 result = executor.fheRem(lhs, bytes32(uint256(266)), bytes1(0x01));
        assertEq(_readPlaintext(result), 4);
    }

    // ──────────────────────────────────────────────
    //  Fuzz tests
    // ──────────────────────────────────────────────

    function testFuzz_fheAdd_uint64(uint64 a, uint64 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint64);
        bytes32 rhs = _trivialEncrypt(uint256(b), FheType.Uint64);
        bytes32 result = executor.fheAdd(lhs, rhs, bytes1(0x00));

        uint256 expected;
        unchecked {
            expected = uint256(uint64(a + b));
        }
        assertEq(_readPlaintext(result), expected);
    }

    function testFuzz_fheSub_uint64(uint64 a, uint64 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint64);
        bytes32 rhs = _trivialEncrypt(uint256(b), FheType.Uint64);
        bytes32 result = executor.fheSub(lhs, rhs, bytes1(0x00));

        uint256 expected;
        unchecked {
            expected = uint256(uint64(a - b));
        }
        assertEq(_readPlaintext(result), expected);
    }

    function testFuzz_fheMul_uint32(uint32 a, uint32 b) public {
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint32);
        bytes32 rhs = _trivialEncrypt(uint256(b), FheType.Uint32);
        bytes32 result = executor.fheMul(lhs, rhs, bytes1(0x00));

        uint256 expected;
        unchecked {
            expected = uint256(uint32(a * b));
        }
        assertEq(_readPlaintext(result), expected);
    }

    function testFuzz_fheDiv_scalar(uint64 a, uint64 b) public {
        vm.assume(b > 0);
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint64);
        bytes32 result = executor.fheDiv(lhs, bytes32(uint256(b)), bytes1(0x01));
        assertEq(_readPlaintext(result), uint256(a) / uint256(b));
    }

    function testFuzz_fheRem_scalar(uint64 a, uint64 b) public {
        vm.assume(b > 0);
        bytes32 lhs = _trivialEncrypt(uint256(a), FheType.Uint64);
        bytes32 result = executor.fheRem(lhs, bytes32(uint256(b)), bytes1(0x01));
        assertEq(_readPlaintext(result), uint256(a) % uint256(b));
    }
}
