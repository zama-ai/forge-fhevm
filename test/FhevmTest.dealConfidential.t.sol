// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FhevmTest} from "../src/FhevmTest.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20.sol";
import {SafeERC20} from "../src/utils/SafeERC20.sol";
import {
    ERC20ForceApproveMock,
    ERC20NoReturnMock,
    ERC20ReturnFalseMock,
    ERC20StandardMock
} from "./mocks/ERC20Mocks.sol";

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC7984ERC20WrapperMock} from "@openzeppelin/confidential-contracts/mocks/token/ERC7984ERC20WrapperMock.sol";

contract FhevmTestDealConfidentialTest is FhevmTest {
    uint256 internal constant HOLDER_PK = 0xA11CE;
    uint256 internal constant AMOUNT = 1000;

    address internal holder;

    function setUp() public override {
        super.setUp();
        holder = vm.addr(HOLDER_PK);
    }

    function test_dealConfidential_wrapsStandardUnderlying() public {
        (ERC20 underlying, ERC7984ERC20WrapperMock wrapper) = _deployWrapper(new ERC20StandardMock());

        dealConfidential(address(wrapper), holder, AMOUNT);

        _assertWrapped(underlying, wrapper, AMOUNT);
    }

    /// @dev The case this helper originally got wrong: a typed `approve` reverts on this underlying.
    function test_dealConfidential_wrapsUnderlyingWithoutApproveReturnValue() public {
        (ERC20 underlying, ERC7984ERC20WrapperMock wrapper) = _deployWrapper(new ERC20NoReturnMock());

        dealConfidential(address(wrapper), holder, AMOUNT);

        _assertWrapped(underlying, wrapper, AMOUNT);
    }

    function test_dealConfidential_wrapsUnderlyingRequiringZeroAllowanceFirst() public {
        (ERC20 underlying, ERC7984ERC20WrapperMock wrapper) = _deployWrapper(new ERC20ForceApproveMock());

        // Two deals in a row: the second one hits a max allowance already in place, which is the
        // non-zero to non-zero change this underlying rejects outright.
        dealConfidential(address(wrapper), holder, AMOUNT);
        dealConfidential(address(wrapper), holder, AMOUNT);

        _assertWrapped(underlying, wrapper, 2 * AMOUNT);
    }

    function test_dealConfidential_revertsWhenUnderlyingReportsApprovalFailure() public {
        (, ERC7984ERC20WrapperMock wrapper) = _deployWrapper(new ERC20ReturnFalseMock());
        address underlying = wrapper.underlying();

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, underlying));
        this.exposed_dealConfidential(address(wrapper), holder, AMOUNT);
    }

    /// @dev Anchors why `dealConfidential` cannot call a typed `approve`: decoding a `bool` from the
    /// empty return data of a USDT-style token reverts. Note that the revert is raised by the caller
    /// after a *successful* call, which is why the external boundary below is required.
    function test_typedApproveRevertsOnUnderlyingWithoutReturnValue() public {
        address underlying = address(new ERC20NoReturnMock());

        vm.expectRevert();
        this.exposed_typedApproveMax(underlying, address(this));
    }

    /// @dev `dealConfidential` is `internal`, so an external boundary is needed for `expectRevert`.
    function exposed_dealConfidential(address wrapper, address user, uint256 amount) external {
        dealConfidential(wrapper, user, amount);
    }

    function exposed_typedApproveMax(address token, address spender) external {
        IERC20Minimal(token).approve(spender, type(uint256).max);
    }

    function _deployWrapper(ERC20 underlying) private returns (ERC20, ERC7984ERC20WrapperMock wrapper) {
        wrapper = new ERC7984ERC20WrapperMock(
            IERC20(address(underlying)), "Confidential Mock", "cMOCK", "https://example.com/metadata"
        );
        return (underlying, wrapper);
    }

    /// @dev `dealConfidential` leaves the wrapper holding the underlying and the user holding the
    /// confidential balance, so assert on both sides of the wrap.
    function _assertWrapped(ERC20 underlying, ERC7984ERC20WrapperMock wrapper, uint256 amount) private {
        assertEq(underlying.balanceOf(holder), 0, "underlying should be fully wrapped");
        assertEq(underlying.balanceOf(address(wrapper)), amount, "wrapper should custody the underlying");

        euint64 confidentialBalance = wrapper.confidentialBalanceOf(holder);
        assertEq(decrypt(confidentialBalance), amount, "confidential balance should match the dealt amount");
    }
}
