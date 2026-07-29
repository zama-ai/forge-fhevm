// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

/**
 * @dev Minimal local copies of the two token interfaces `dealConfidential` needs.
 *
 * These deliberately do not import OpenZeppelin. `FhevmTest` is inherited by consumer test
 * suites, so anything it imports lands in the consumer's compile graph — and Foundry
 * remappings are project-global, so an OZ import here would pin every consumer to our OZ
 * version. Keeping the surface local lets downstream repos choose their own.
 */
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/**
 * @dev Subset of `IERC7984ERC20Wrapper`. `wrap` is declared without its `euint64` return
 * value: return data is simply ignored, and omitting it keeps this file free of any
 * encrypted-type dependency.
 */
interface IConfidentialERC20Wrapper {
    function underlying() external view returns (address);
    function wrap(address to, uint256 amount) external;
}
