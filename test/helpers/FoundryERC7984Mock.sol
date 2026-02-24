// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ERC7984Mock} from "@openzeppelin/confidential-contracts/mocks/token/ERC7984Mock.sol";

/// @notice Test-only ERC7984 mock exposing selected internal hooks for Foundry tests.
contract FoundryERC7984Mock is ERC7984Mock {
    constructor(string memory name_, string memory symbol_, string memory uri_) ERC7984Mock(name_, symbol_, uri_) {}

    /// @notice Test helper to set operator approval directly through the underlying internal hook.
    /// @param holder Holder account granting or revoking approval.
    /// @param operator Operator account whose approval is being updated.
    /// @param until Timestamp until which the operator is approved.
    function $_setOperator(address holder, address operator, uint48 until) public {
        _setOperator(holder, operator, until);
    }
}
