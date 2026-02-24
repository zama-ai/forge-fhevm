---
layout: home

hero:
  name: forge-fhevm
  text: Foundry Testing for Confidential Contracts
  tagline: Write Forge tests for FHEVM contracts — encrypt, compute, decrypt, assert.
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: API Reference
      link: /api/fhevm-test
---

<div class="vp-doc" style="max-width: 688px; margin: 2rem auto; padding: 0 24px;">

```solidity
contract ConfidentialTransferTest is FhevmTest {
    FoundryERC7984Mock token;

    function setUp() public override {
        super.setUp();
        token = new FoundryERC7984Mock("ConfToken", "CFT", "");
        // Mint 1000 tokens to holder
        (externalEuint64 amt, bytes memory proof) = encryptUint64(1000, holder, address(token));
        vm.prank(holder);
        token.$_mint(holder, amt, proof);
    }

    function test_confidentialTransfer() public {
        // Encrypt and transfer 400 tokens
        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, holder, address(token));
        vm.prank(holder);
        token.confidentialTransfer(recipient, amount, proof);

        // Decrypt and assert balances
        bytes memory sig = signUserDecrypt(HOLDER_PK, address(token));
        uint256 holderBal = userDecrypt(
            euint64.unwrap(token.confidentialBalanceOf(holder)), holder, address(token), sig
        );

        sig = signUserDecrypt(RECIPIENT_PK, address(token));
        uint256 recipientBal = userDecrypt(
            euint64.unwrap(token.confidentialBalanceOf(recipient)), recipient, address(token), sig
        );

        assertEq(holderBal, 600);
        assertEq(recipientBal, 400);
    }
}
```

</div>
