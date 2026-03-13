// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ExecutorDeployer} from "./helpers/ExecutorDeployer.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";

contract FHEVMExecutorUnaryTest is ExecutorDeployer {
    function setUp() public {
        _deployExecutorStack();
    }

    // ──────────────────────────────────────────────
    //  fheNeg
    // ──────────────────────────────────────────────

    function test_fheNeg_uint8_5() public {
        bytes32 ct = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheNeg(ct);
        // Two's complement: (~5 + 1) & 0xFF = 251
        assertEq(_readPlaintext(result), 251);
    }

    function test_fheNeg_uint8_0() public {
        bytes32 ct = _trivialEncrypt(0, FheType.Uint8);
        bytes32 result = executor.fheNeg(ct);
        // Two's complement of 0 = 0
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheNeg_uint16() public {
        bytes32 ct = _trivialEncrypt(1, FheType.Uint16);
        bytes32 result = executor.fheNeg(ct);
        // (~1 + 1) & 0xFFFF = 65535
        assertEq(_readPlaintext(result), 65535);
    }

    function test_fheNeg_uint256() public {
        bytes32 ct = _trivialEncrypt(1, FheType.Uint256);
        bytes32 result = executor.fheNeg(ct);
        // Two's complement of 1 in 256-bit = type(uint256).max
        assertEq(_readPlaintext(result), type(uint256).max);
    }

    function test_fheNeg_revert_bool() public {
        bytes32 ct = _trivialEncrypt(1, FheType.Bool);
        vm.expectRevert(FHEVMExecutor.UnsupportedType.selector);
        executor.fheNeg(ct);
    }

    function test_fheNeg_preservesType() public {
        bytes32 ct = _trivialEncrypt(5, FheType.Uint32);
        bytes32 result = executor.fheNeg(ct);
        assertEq(uint8(result[30]), uint8(FheType.Uint32));
    }

    // ──────────────────────────────────────────────
    //  fheNot
    // ──────────────────────────────────────────────

    function test_fheNot_uint8_5() public {
        bytes32 ct = _trivialEncrypt(5, FheType.Uint8);
        bytes32 result = executor.fheNot(ct);
        // ~5 & 0xFF = 250
        assertEq(_readPlaintext(result), 250);
    }

    function test_fheNot_uint8_0() public {
        bytes32 ct = _trivialEncrypt(0, FheType.Uint8);
        bytes32 result = executor.fheNot(ct);
        // ~0 & 0xFF = 255
        assertEq(_readPlaintext(result), 255);
    }

    function test_fheNot_bool_1() public {
        bytes32 ct = _trivialEncrypt(1, FheType.Bool);
        bytes32 result = executor.fheNot(ct);
        // ~1 & 1 = 0
        assertEq(_readPlaintext(result), 0);
    }

    function test_fheNot_bool_0() public {
        bytes32 ct = _trivialEncrypt(0, FheType.Bool);
        bytes32 result = executor.fheNot(ct);
        // ~0 & 1 = 1
        assertEq(_readPlaintext(result), 1);
    }

    function test_fheNot_uint256() public {
        bytes32 ct = _trivialEncrypt(0, FheType.Uint256);
        bytes32 result = executor.fheNot(ct);
        assertEq(_readPlaintext(result), type(uint256).max);
    }

    function test_fheNot_preservesType() public {
        bytes32 ct = _trivialEncrypt(5, FheType.Uint64);
        bytes32 result = executor.fheNot(ct);
        assertEq(uint8(result[30]), uint8(FheType.Uint64));
    }

    // ──────────────────────────────────────────────
    //  Fuzz tests
    // ──────────────────────────────────────────────

    function testFuzz_fheNeg_uint8(uint8 a) public {
        bytes32 ct = _trivialEncrypt(uint256(a), FheType.Uint8);
        bytes32 result = executor.fheNeg(ct);
        uint256 expected;
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            expected = uint256(uint8(-int8(int256(uint256(a)))));
        }
        assertEq(_readPlaintext(result), expected);
    }

    function testFuzz_fheNot_uint8(uint8 a) public {
        bytes32 ct = _trivialEncrypt(uint256(a), FheType.Uint8);
        bytes32 result = executor.fheNot(ct);
        assertEq(_readPlaintext(result), uint256(~a));
    }
}
