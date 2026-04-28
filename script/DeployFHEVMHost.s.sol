// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {EmptyUUPSProxyACL} from "@fhevm/host-contracts/contracts/emptyProxyACL/EmptyUUPSProxyACL.sol";
import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {ACL} from "@fhevm/host-contracts/contracts/ACL.sol";
import {CleartextFHEVMExecutor} from "forge-fhevm/cleartext/CleartextFHEVMExecutor.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";
import {KMSVerifier} from "@fhevm/host-contracts/contracts/KMSVerifier.sol";
import {InputVerifier} from "@fhevm/host-contracts/contracts/InputVerifier.sol";
import {HCULimit} from "@fhevm/host-contracts/contracts/HCULimit.sol";
import {PauserSet} from "@fhevm/host-contracts/contracts/immutable/PauserSet.sol";

import {
    aclAdd,
    fhevmExecutorAdd,
    kmsVerifierAdd,
    inputVerifierAdd,
    hcuLimitAdd,
    pauserSetAdd
} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";

/**
 * @title DeployFHEVMHost
 * @notice Step 2 of the two-phase FHEVM host deployment.
 *
 * Must be run AFTER ComputeAddresses.s.sol has written FHEVMHostAddresses.sol
 * and `forge build` has been executed so that all implementation contracts
 * carry the correct baked-in addresses.
 *
 * Usage (from forge-fhevm/):
 *
 *   forge script script/DeployFHEVMHost.s.sol \
 *       --rpc-url <rpc> \
 *       --broadcast \
 *       --private-key $DEPLOYER_PRIVATE_KEY
 *
 * Required environment variables:
 *   DEPLOYER_PRIVATE_KEY             — deployer private key
 *   DECRYPTION_ADDRESS               — Gateway Decryption proxy (EIP-712 verifying contract for KMSVerifier)
 *   INPUT_VERIFICATION_ADDRESS       — Gateway InputVerification proxy (EIP-712 verifying contract for InputVerifier)
 *   CHAIN_ID_GATEWAY                 — Chain ID of the gateway chain
 *   PUBLIC_DECRYPTION_THRESHOLD      — Minimum KMS signatures required for decryption
 *   COPROCESSOR_THRESHOLD            — Minimum coprocessor signatures required
 *
 * KMS signer — supply one of:
 *   KMS_SIGNER_ADDRESS_0             — address directly
 *   KMS_SIGNER_PRIVATE_KEY_0         — private key; address is derived via vm.addr()
 *
 * Coprocessor signer — supply one of:
 *   COPROCESSOR_SIGNER_ADDRESS_0     — address directly
 *   COPROCESSOR_SIGNER_PRIVATE_KEY_0 — private key; address is derived via vm.addr()
 *
 * Optional environment variables:
 *   PAUSER_ADDRESS_0                 — Address to grant pauser role (skipped if unset)
 */
contract DeployFHEVMHost is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address decryptionAddress = vm.envAddress("DECRYPTION_ADDRESS");
        address inputVerificationAddress = vm.envAddress("INPUT_VERIFICATION_ADDRESS");
        uint64 chainIdGateway = uint64(vm.envUint("CHAIN_ID_GATEWAY"));

        uint256 kmsThreshold = vm.envUint("PUBLIC_DECRYPTION_THRESHOLD");
        uint256 coprocessorThreshold = vm.envUint("COPROCESSOR_THRESHOLD");

        address kmsSigner = _resolveSignerAddress("KMS_SIGNER_ADDRESS_0", "KMS_SIGNER_PRIVATE_KEY_0");
        address coprocessorSigner =
            _resolveSignerAddress("COPROCESSOR_SIGNER_ADDRESS_0", "COPROCESSOR_SIGNER_PRIVATE_KEY_0");

        vm.startBroadcast(deployerKey);

        // ----------------------------------------------------------------
        // Step 1: Deploy 5 empty UUPS proxies.
        //
        // Deployment order must exactly match the nonce offsets computed in
        // ComputeAddresses.s.sol. Each proxy = 1 impl deploy + 1 proxy deploy.
        //
        // ACL must come first: the other EmptyUUPSProxy contracts import aclAdd
        // via ACLOwnable and check the ACL owner in _authorizeUpgrade.
        // ----------------------------------------------------------------

        // nonce+0: EmptyUUPSProxyACL implementation
        // nonce+1: ACL proxy → must equal aclAdd
        {
            EmptyUUPSProxyACL aclImpl = new EmptyUUPSProxyACL();
            ERC1967Proxy aclProxy =
                new ERC1967Proxy(address(aclImpl), abi.encodeCall(EmptyUUPSProxyACL.initialize, (deployer)));
            require(address(aclProxy) == aclAdd, "DeployFHEVMHost: ACL proxy address mismatch");
            console.log("ACL empty proxy:           ", address(aclProxy));
        }

        // nonce+2: EmptyUUPSProxy implementation (FHEVMExecutor slot)
        // nonce+3: FHEVMExecutor proxy → must equal fhevmExecutorAdd
        {
            EmptyUUPSProxy fhevmImpl = new EmptyUUPSProxy();
            ERC1967Proxy fhevmProxy =
                new ERC1967Proxy(address(fhevmImpl), abi.encodeCall(EmptyUUPSProxy.initialize, ()));
            require(address(fhevmProxy) == fhevmExecutorAdd, "DeployFHEVMHost: FHEVMExecutor proxy address mismatch");
            console.log("FHEVMExecutor empty proxy: ", address(fhevmProxy));
        }

        // nonce+4: EmptyUUPSProxy implementation (KMSVerifier slot)
        // nonce+5: KMSVerifier proxy → must equal kmsVerifierAdd
        {
            EmptyUUPSProxy kmsImpl = new EmptyUUPSProxy();
            ERC1967Proxy kmsProxy = new ERC1967Proxy(address(kmsImpl), abi.encodeCall(EmptyUUPSProxy.initialize, ()));
            require(address(kmsProxy) == kmsVerifierAdd, "DeployFHEVMHost: KMSVerifier proxy address mismatch");
            console.log("KMSVerifier empty proxy:   ", address(kmsProxy));
        }

        // nonce+6: EmptyUUPSProxy implementation (InputVerifier slot)
        // nonce+7: InputVerifier proxy → must equal inputVerifierAdd
        {
            EmptyUUPSProxy ivImpl = new EmptyUUPSProxy();
            ERC1967Proxy ivProxy = new ERC1967Proxy(address(ivImpl), abi.encodeCall(EmptyUUPSProxy.initialize, ()));
            require(address(ivProxy) == inputVerifierAdd, "DeployFHEVMHost: InputVerifier proxy address mismatch");
            console.log("InputVerifier empty proxy: ", address(ivProxy));
        }

        // nonce+8: EmptyUUPSProxy implementation (HCULimit slot)
        // nonce+9: HCULimit proxy → must equal hcuLimitAdd
        {
            EmptyUUPSProxy hcuImpl = new EmptyUUPSProxy();
            ERC1967Proxy hcuProxy = new ERC1967Proxy(address(hcuImpl), abi.encodeCall(EmptyUUPSProxy.initialize, ()));
            require(address(hcuProxy) == hcuLimitAdd, "DeployFHEVMHost: HCULimit proxy address mismatch");
            console.log("HCULimit empty proxy:      ", address(hcuProxy));
        }

        // ----------------------------------------------------------------
        // Step 2: Deploy PauserSet (immutable, no proxy).
        //
        // nonce+10: PauserSet → must equal pauserSetAdd
        // ----------------------------------------------------------------
        {
            PauserSet ps = new PauserSet();
            require(address(ps) == pauserSetAdd, "DeployFHEVMHost: PauserSet address mismatch");
            console.log("PauserSet:                 ", address(ps));
        }

        // ----------------------------------------------------------------
        // Step 3: Deploy implementations and upgrade proxies.
        //
        // FHEVMHostAddresses.sol is now complete, so all implementations
        // compile with the correct baked-in addresses.
        // ----------------------------------------------------------------

        // --- ACL ---
        {
            ACL aclImpl2 = new ACL();
            UUPSUpgradeable(aclAdd)
                .upgradeToAndCall(address(aclImpl2), abi.encodeCall(ACL.initializeFromEmptyProxy, ()));
            console.log("ACL upgraded:              ", aclAdd);
        }

        // --- CleartextFHEVMExecutor ---
        {
            CleartextFHEVMExecutor fhevmImpl2 = new CleartextFHEVMExecutor();
            UUPSUpgradeable(fhevmExecutorAdd)
                .upgradeToAndCall(address(fhevmImpl2), abi.encodeCall(FHEVMExecutor.initializeFromEmptyProxy, ()));
            console.log("CleartextFHEVMExecutor upgraded: ", fhevmExecutorAdd);
        }

        // --- KMSVerifier ---
        {
            address[] memory kmsSigners = new address[](1);
            kmsSigners[0] = kmsSigner;
            KMSVerifier kmsImpl2 = new KMSVerifier();
            UUPSUpgradeable(kmsVerifierAdd)
                .upgradeToAndCall(
                    address(kmsImpl2),
                    abi.encodeCall(
                        KMSVerifier.initializeFromEmptyProxy,
                        (decryptionAddress, chainIdGateway, kmsSigners, kmsThreshold)
                    )
                );
            console.log("KMSVerifier upgraded:      ", kmsVerifierAdd);
        }

        // --- InputVerifier ---
        {
            address[] memory coprocessorSigners = new address[](1);
            coprocessorSigners[0] = coprocessorSigner;
            InputVerifier ivImpl2 = new InputVerifier();
            UUPSUpgradeable(inputVerifierAdd)
                .upgradeToAndCall(
                    address(ivImpl2),
                    abi.encodeCall(
                        InputVerifier.initializeFromEmptyProxy,
                        (inputVerificationAddress, chainIdGateway, coprocessorSigners, coprocessorThreshold)
                    )
                );
            console.log("InputVerifier upgraded:    ", inputVerifierAdd);
        }

        // --- HCULimit ---
        {
            HCULimit hcuImpl2 = new HCULimit();
            UUPSUpgradeable(hcuLimitAdd)
                .upgradeToAndCall(
                    address(hcuImpl2),
                    abi.encodeCall(HCULimit.initializeFromEmptyProxy, (20_000_000, 5_000_000, 20_000_000))
                );
            console.log("HCULimit upgraded:         ", hcuLimitAdd);
        }

        // ----------------------------------------------------------------
        // Step 4: Add pausers (optional).
        // ----------------------------------------------------------------
        try vm.envAddress("PAUSER_ADDRESS_0") returns (address pauser) {
            PauserSet(pauserSetAdd).addPauser(pauser);
            console.log("Pauser added:              ", pauser);
        } catch {
            // PAUSER_ADDRESS_0 not set — skipping
        }

        vm.stopBroadcast();

        console.log("\n--- Deployment complete ---");
        console.log("aclAdd:           ", aclAdd);
        console.log("fhevmExecutorAdd: ", fhevmExecutorAdd);
        console.log("kmsVerifierAdd:   ", kmsVerifierAdd);
        console.log("inputVerifierAdd: ", inputVerifierAdd);
        console.log("hcuLimitAdd:      ", hcuLimitAdd);
        console.log("pauserSetAdd:     ", pauserSetAdd);
    }

    /// @dev Returns the signer address from `addrVar` if set, otherwise derives
    ///      it from the private key in `pkeyVar`. Reverts if neither is set.
    function _resolveSignerAddress(string memory addrVar, string memory pkeyVar)
        internal
        view
        returns (address signer)
    {
        try vm.envAddress(addrVar) returns (address a) {
            return a;
        } catch {}

        try vm.envUint(pkeyVar) returns (uint256 pk) {
            return vm.addr(pk);
        } catch {}

        revert(string.concat("DeployFHEVMHost: set either ", addrVar, " or ", pkeyVar));
    }
}
