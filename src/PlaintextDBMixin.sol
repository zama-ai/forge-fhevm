// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FHEEvents} from "@fhevm/host-contracts/contracts/FHEEvents.sol";
import {fhevmExecutorAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {CleartextArithmetic} from "./cleartext/CleartextArithmetic.sol";
import {FheTypeBitWidth} from "./cleartext/FheTypeBitWidth.sol";

abstract contract PlaintextDBMixin is Test, FHEEvents {
    mapping(bytes32 => uint256) internal _plaintexts;

    function _processNewLogs() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != fhevmExecutorAdd) {
                continue;
            }
            _dispatchFheEvent(logs[i]);
        }
    }

    function _dispatchFheEvent(Vm.Log memory logEntry) internal {
        bytes32 selector = logEntry.topics[0];

        if (selector == FheAdd.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.add);
        } else if (selector == FheSub.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.sub);
        } else if (selector == FheMul.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.mul);
        } else if (selector == FheDiv.selector) {
            _handleDiv(logEntry.data);
        } else if (selector == FheRem.selector) {
            _handleRem(logEntry.data);
        } else if (selector == FheBitAnd.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.bitAnd);
        } else if (selector == FheBitOr.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.bitOr);
        } else if (selector == FheBitXor.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.bitXor);
        } else if (selector == FheShl.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.shl);
        } else if (selector == FheShr.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.shr);
        } else if (selector == FheRotl.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.rotl);
        } else if (selector == FheRotr.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.rotr);
        } else if (selector == FheEq.selector) {
            _handleCmp(logEntry.data, _eq);
        } else if (selector == FheNe.selector) {
            _handleCmp(logEntry.data, _ne);
        } else if (selector == FheGe.selector) {
            _handleCmp(logEntry.data, _ge);
        } else if (selector == FheGt.selector) {
            _handleCmp(logEntry.data, _gt);
        } else if (selector == FheLe.selector) {
            _handleCmp(logEntry.data, _le);
        } else if (selector == FheLt.selector) {
            _handleCmp(logEntry.data, _lt);
        } else if (selector == FheMin.selector) {
            _handleCmp(logEntry.data, _min);
        } else if (selector == FheMax.selector) {
            _handleCmp(logEntry.data, _max);
        } else if (selector == FheNeg.selector) {
            _handleUnaryOp(logEntry.data, CleartextArithmetic.neg);
        } else if (selector == FheNot.selector) {
            _handleUnaryOp(logEntry.data, CleartextArithmetic.bitNot);
        } else if (selector == TrivialEncrypt.selector) {
            _handleTrivialEncrypt(logEntry.data);
        } else if (selector == Cast.selector) {
            _handleCast(logEntry.data);
        } else if (selector == FheIfThenElse.selector) {
            _handleIfThenElse(logEntry.data);
        } else if (selector == FheRand.selector) {
            _handleRand(logEntry.data);
        } else if (selector == FheRandBounded.selector) {
            _handleRandBounded(logEntry.data);
        } else if (selector == VerifyInput.selector) {
            _handleVerifyInput(logEntry.data);
        }
    }

    // --- Binary arithmetic (lhs, rhs, scalarByte, result) ---

    function _loadBinaryOperands(bytes memory data)
        private
        view
        returns (bytes32 result, uint256 bitWidth, uint256 a, uint256 b)
    {
        (bytes32 lhs, bytes32 rhs, bytes1 scalarByte, bytes32 res) =
            abi.decode(data, (bytes32, bytes32, bytes1, bytes32));
        result = res;
        bitWidth = FheTypeBitWidth.bitWidthForType(uint8(_typeOf(lhs)));
        a = CleartextArithmetic.clamp(_plaintexts[lhs], bitWidth);
        b = (scalarByte == 0x01) ? uint256(rhs) : CleartextArithmetic.clamp(_plaintexts[rhs], bitWidth);
    }

    function _handleBinaryOp(bytes memory data, function(uint256, uint256, uint256) pure returns (uint256) op) private {
        (bytes32 result, uint256 bw, uint256 a, uint256 b) = _loadBinaryOperands(data);
        _plaintexts[result] = op(a, b, bw);
    }

    function _handleDiv(bytes memory data) private {
        (bytes32 result,, uint256 a, uint256 b) = _loadBinaryOperands(data);
        _plaintexts[result] = a / b;
    }

    function _handleRem(bytes memory data) private {
        (bytes32 result,, uint256 a, uint256 b) = _loadBinaryOperands(data);
        _plaintexts[result] = a % b;
    }

    // --- Comparison / select (same decoding, no bitWidth needed) ---

    function _handleCmp(bytes memory data, function(uint256, uint256) pure returns (uint256) op) private {
        (bytes32 result,, uint256 a, uint256 b) = _loadBinaryOperands(data);
        _plaintexts[result] = op(a, b);
    }

    function _eq(uint256 a, uint256 b) private pure returns (uint256) {
        return (a == b) ? 1 : 0;
    }

    function _ne(uint256 a, uint256 b) private pure returns (uint256) {
        return (a != b) ? 1 : 0;
    }

    function _ge(uint256 a, uint256 b) private pure returns (uint256) {
        return (a >= b) ? 1 : 0;
    }

    function _gt(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? 1 : 0;
    }

    function _le(uint256 a, uint256 b) private pure returns (uint256) {
        return (a <= b) ? 1 : 0;
    }

    function _lt(uint256 a, uint256 b) private pure returns (uint256) {
        return (a < b) ? 1 : 0;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a < b) ? a : b;
    }

    function _max(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? a : b;
    }

    // --- Unary (ct, result) ---

    function _handleUnaryOp(bytes memory data, function(uint256, uint256) pure returns (uint256) op) private {
        (bytes32 ct, bytes32 result) = abi.decode(data, (bytes32, bytes32));
        uint256 bw = FheTypeBitWidth.bitWidthForType(uint8(_typeOf(ct)));
        _plaintexts[result] = op(CleartextArithmetic.clamp(_plaintexts[ct], bw), bw);
    }

    // --- Misc ---

    function _handleTrivialEncrypt(bytes memory data) private {
        (uint256 pt,, bytes32 result) = abi.decode(data, (uint256, uint8, bytes32));
        _plaintexts[result] = pt;
    }

    function _handleCast(bytes memory data) private {
        (bytes32 ct, uint8 toTypeRaw, bytes32 result) = abi.decode(data, (bytes32, uint8, bytes32));
        _plaintexts[result] = CleartextArithmetic.clamp(_plaintexts[ct], FheTypeBitWidth.bitWidthForType(toTypeRaw));
    }

    function _handleIfThenElse(bytes memory data) private {
        (bytes32 control, bytes32 ifTrue, bytes32 ifFalse, bytes32 result) =
            abi.decode(data, (bytes32, bytes32, bytes32, bytes32));
        _plaintexts[result] = (_plaintexts[control] == 1) ? _plaintexts[ifTrue] : _plaintexts[ifFalse];
    }

    function _handleRand(bytes memory data) private {
        (uint8 randTypeRaw, bytes16 seed, bytes32 result) = abi.decode(data, (uint8, bytes16, bytes32));
        _plaintexts[result] = CleartextArithmetic.rand(seed, FheTypeBitWidth.bitWidthForType(randTypeRaw));
    }

    function _handleRandBounded(bytes memory data) private {
        (uint256 upperBound,, bytes16 seed, bytes32 result) = abi.decode(data, (uint256, uint8, bytes16, bytes32));
        _plaintexts[result] = CleartextArithmetic.randBounded(seed, upperBound);
    }

    function _handleVerifyInput(bytes memory data) private pure {
        (bytes32 inputHandle,,,, bytes32 result) = abi.decode(data, (bytes32, address, bytes, uint8, bytes32));
        assert(inputHandle == result);
    }

    // --- Shared helpers ---

    function _typeOf(bytes32 handle) internal pure returns (FheType) {
        return FheType(uint8(handle[30]));
    }

    function _seedPlaintext(bytes32 handle, uint256 value) internal {
        _plaintexts[handle] = value;
    }

    function _readPlaintext(bytes32 handle) internal returns (uint256) {
        _processNewLogs();
        return _plaintexts[handle];
    }
}
