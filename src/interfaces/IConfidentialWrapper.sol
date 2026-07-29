// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

/// @dev Local copy rather than an OpenZeppelin import: this file reaches every consumer's
/// compile graph through the test base, and Foundry remappings are project-global.
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/// @dev Subset of `IERC7984ERC20Wrapper`. `wrap` drops the real `euint64` return value so that
/// this file needs no encrypted-type dependency; the returned data is ignored either way.
interface IConfidentialERC20Wrapper {
    function underlying() external view returns (address);
    function wrap(address to, uint256 amount) external;
}
