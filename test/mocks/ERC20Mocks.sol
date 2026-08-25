// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Mirrors the mocks OpenZeppelin uses to test `SafeERC20` (`contracts/mocks/token/`), made
/// concrete and fixed at 6 decimals. Each contract deviates from the standard in exactly one way.
///
/// 6 decimals keeps `ERC7984ERC20Wrapper.rate()` at 1, so wrapped amounts map 1:1 to the underlying.
abstract contract ERC20SixDecimalsMock is ERC20 {
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @notice Fully standard ERC-20, as a baseline.
contract ERC20StandardMock is ERC20SixDecimalsMock {
    constructor() ERC20("ERC20StandardMock", "STANDARD") {}
}

/// @notice Rejects a non-zero to non-zero allowance change, the approval behavior USDT documents.
/// @dev Upstream `ERC20ForceApproveMock`. Note this quirk is *documented* by USDT but its `require`
/// is commented out in the deployed contract; the live deviation is the missing return value below.
contract ERC20ForceApproveMock is ERC20SixDecimalsMock {
    constructor() ERC20("ERC20ForceApproveMock", "ZEROFIRST") {}

    function approve(address spender, uint256 value) public override returns (bool) {
        require(value == 0 || allowance(msg.sender, spender) == 0, "approval failure");
        return super.approve(spender, value);
    }
}

/// @notice Returns no data at all from `approve`, the way USDT actually does.
/// @dev Upstream `ERC20NoReturnMock`. The `return(0, 0)` terminates the external call with empty
/// return data, which is what makes a typed `approve` revert in the *caller* while decoding a bool.
contract ERC20NoReturnMock is ERC20SixDecimalsMock {
    constructor() ERC20("ERC20NoReturnMock", "NORETURN") {}

    function approve(address spender, uint256 value) public override returns (bool) {
        super.approve(spender, value);
        assembly {
            return(0, 0)
        }
    }
}

/// @notice Reports failure through the return value instead of reverting.
/// @dev Upstream `ERC20ReturnFalseMock`. This is the only path that reaches
/// `SafeERC20FailedOperation`: a reverting `approve` gets its own reason bubbled instead.
contract ERC20ReturnFalseMock is ERC20SixDecimalsMock {
    constructor() ERC20("ERC20ReturnFalseMock", "RETURNFALSE") {}

    function approve(address, uint256) public pure override returns (bool) {
        return false;
    }
}
