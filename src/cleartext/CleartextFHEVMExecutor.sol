// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FHEVMExecutor} from "../fhevm-host/contracts/FHEVMExecutor.sol";
import {FheType} from "../fhevm-host/contracts/shared/FheType.sol";
import {CleartextArithmetic} from "./CleartextArithmetic.sol";
import {FheTypeBitWidth} from "./FheTypeBitWidth.sol";

/// @notice FHEVMExecutor variant that mirrors every operation result into a `plaintexts` mapping.
/// @dev Each override calls `super` (symbolic handle flow) then stores the cleartext.
contract CleartextFHEVMExecutor is FHEVMExecutor {
    error UnsupportedCleartextBinaryOp(Operators op);
    error UnsupportedCleartextUnaryOp(Operators op);

    /// @dev Handle to cleartext value mapping for local testing.
    mapping(bytes32 => uint256) public plaintexts;

    function cast(bytes32 ct, FheType toType) public override returns (bytes32 result) {
        result = super.cast(ct, toType);
        plaintexts[result] = CleartextArithmetic.fheCast(plaintexts[ct], uint8(toType));
    }

    function trivialEncrypt(uint256 pt, FheType toType) public override returns (bytes32 result) {
        result = super.trivialEncrypt(pt, toType);
        plaintexts[result] = CleartextArithmetic.normalizePlaintextToType(pt, uint8(toType));
    }

    /// @notice Verifies input and extracts cleartext from the proof's extra-data suffix.
    function verifyInput(bytes32 inputHandle, address userAddress, bytes memory inputProof, FheType inputType)
        public
        override
        returns (bytes32 result)
    {
        result = super.verifyInput(inputHandle, userAddress, inputProof, inputType);
        (bool foundCleartext, uint256 cleartext) = _tryReadCleartextFromProof(inputHandle, inputProof);
        if (foundCleartext) {
            plaintexts[result] = CleartextArithmetic.normalizePlaintextToType(cleartext, uint8(inputType));
        }
    }

    function _generateRand(FheType randType, bytes16 seed) internal override returns (bytes32 result) {
        result = super._generateRand(randType, seed);
        plaintexts[result] = CleartextArithmetic.rand(seed, FheTypeBitWidth.bitWidthForType(uint8(randType)));
    }

    function _generateRandBounded(uint256 upperBound, FheType randType, bytes16 seed)
        internal
        override
        returns (bytes32 result)
    {
        result = super._generateRandBounded(upperBound, randType, seed);
        plaintexts[result] = CleartextArithmetic.randBounded(seed, upperBound);
    }

    function _binaryOp(Operators op, bytes32 lhs, bytes32 rhs, bytes1 scalarByte, FheType resultType)
        internal
        override
        returns (bytes32 result)
    {
        result = super._binaryOp(op, lhs, rhs, scalarByte, resultType);
        plaintexts[result] = _computeBinaryResult(op, lhs, rhs, scalarByte);
    }

    function _unaryOp(Operators op, bytes32 ct) internal override returns (bytes32 result) {
        result = super._unaryOp(op, ct);
        plaintexts[result] = _computeUnaryResult(op, ct);
    }

    function _ternaryOp(Operators op, bytes32 lhs, bytes32 middle, bytes32 rhs)
        internal
        override
        returns (bytes32 result)
    {
        result = super._ternaryOp(op, lhs, middle, rhs);

        if (op == Operators.fheIfThenElse) {
            plaintexts[result] = CleartextArithmetic.fheIfThenElse(plaintexts[lhs], plaintexts[middle], plaintexts[rhs]);
        }
    }

    function _rhsValue(bytes32 rhs, bytes1 scalarByte) private view returns (uint256) {
        return (scalarByte == 0x01) ? uint256(rhs) : plaintexts[rhs];
    }

    function _computeBinaryResult(Operators op, bytes32 lhs, bytes32 rhs, bytes1 scalarByte)
        private
        view
        returns (uint256)
    {
        uint256 lhsValue = plaintexts[lhs];
        uint256 rhsValue = _rhsValue(rhs, scalarByte);
        uint8 fheType = uint8(_typeOf(lhs));

        if (op == Operators.fheAdd) return CleartextArithmetic.fheAdd(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheSub) return CleartextArithmetic.fheSub(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheMul) return CleartextArithmetic.fheMul(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheDiv) return CleartextArithmetic.fheDiv(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheRem) return CleartextArithmetic.fheRem(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheBitAnd) return CleartextArithmetic.fheBitAnd(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheBitOr) return CleartextArithmetic.fheBitOr(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheBitXor) return CleartextArithmetic.fheBitXor(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheShl) return CleartextArithmetic.fheShl(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheShr) return CleartextArithmetic.fheShr(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheRotl) return CleartextArithmetic.fheRotl(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheRotr) return CleartextArithmetic.fheRotr(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheEq) return CleartextArithmetic.fheEq(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheNe) return CleartextArithmetic.fheNe(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheGe) return CleartextArithmetic.fheGe(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheGt) return CleartextArithmetic.fheGt(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheLe) return CleartextArithmetic.fheLe(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheLt) return CleartextArithmetic.fheLt(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheMin) return CleartextArithmetic.fheMin(lhsValue, rhsValue, fheType, scalarByte);
        if (op == Operators.fheMax) return CleartextArithmetic.fheMax(lhsValue, rhsValue, fheType, scalarByte);

        revert UnsupportedCleartextBinaryOp(op);
    }

    function _computeUnaryResult(Operators op, bytes32 ct) private view returns (uint256) {
        uint256 value = plaintexts[ct];
        uint8 fheType = uint8(_typeOf(ct));

        if (op == Operators.fheNeg) return CleartextArithmetic.fheNeg(value, fheType);
        if (op == Operators.fheNot) return CleartextArithmetic.fheNot(value, fheType);

        revert UnsupportedCleartextUnaryOp(op);
    }

    function _tryReadCleartextFromProof(bytes32 inputHandle, bytes memory inputProof)
        private
        pure
        returns (bool foundCleartext, uint256 cleartext)
    {
        if (inputProof.length < 2) {
            return (false, 0);
        }

        uint8 numHandles = uint8(inputProof[0]);
        uint8 numSigners = uint8(inputProof[1]);
        uint256 cleartextStart = 2 + uint256(numHandles) * 32 + uint256(numSigners) * 65;

        if (inputProof.length < cleartextStart + 32) {
            return (false, 0);
        }

        for (uint8 i = 0; i < numHandles; i++) {
            uint256 handleOffset = 2 + uint256(i) * 32;
            bytes32 handleInProof;
            assembly {
                handleInProof := mload(add(add(inputProof, 32), handleOffset))
            }

            if (handleInProof != inputHandle) {
                continue;
            }

            uint256 cleartextOffset = cleartextStart + uint256(i) * 32;
            if (inputProof.length < cleartextOffset + 32) {
                return (false, 0);
            }

            assembly {
                cleartext := mload(add(add(inputProof, 32), cleartextOffset))
            }
            return (true, cleartext);
        }

        return (false, 0);
    }
}
