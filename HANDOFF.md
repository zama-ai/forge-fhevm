# Handoff — decoupling forge-fhevm consumers from our OpenZeppelin pin

**Status:** implemented on the feature branch; follow-up review edits are uncommitted.
**Branch:** `feat/host-bytecode-generation`.

---

## 1. Why this exists

Slack thread: [#C077CHJ97EF, 2026-07-28](https://zama-ai.slack.com/archives/C077CHJ97EF/p1785254478450909?thread_ts=1785247258.383939&cid=C077CHJ97EF)

Aryeh wanted a hybrid Foundry + Hardhat test setup in the confidential-contracts repo. `FhevmTest`
imported the vendored host contracts as **source**; those import OpenZeppelin; Foundry remappings
are **project-global**. So inheriting `FhevmTest` forced our OZ pin (5.1.0) on the consumer's entire
repo.

Joseph-André rejected the alternative (upgrading deployed mainnet contracts to suit a devX plugin)
and suggested shipping bytecode instead of source. That's what this does.

Aryeh offered to write the PR — this is a complete implementation he can review or take over.

---

## 2. What changed

### New

| Path | What |
|---|---|
| `src/generated/HostBytecode.sol` | Creation/runtime bytecode blobs, ~90 KB code / ~180 KB hex source |
| `src/generated/interfaces/I*.sol` | 7 ABI-derived interfaces (errors + events included) |
| `src/interfaces/IConfidentialWrapper.sol` | Hand-written minimal `IERC20Minimal` / `IConfidentialERC20Wrapper` |
| `script/gen/generate.py` | The generator |
| `fixtures/consumer/` | Downstream project pinned to **OZ 5.4**, builds + tests in CI |
| `.gitattributes` | Hides the bytecode diff while keeping generated interface diffs reviewable |

### Modified

- `src/FhevmTest.sol` — the substantive rewrite (fields, deploy path, `dealConfidential`)
- `src/PlaintextDBMixin.sol`, `src/InputProofHelper.sol` — `@fhevm/host-contracts/` → relative imports
- `Makefile` — `generate`, `check-generated`, `check-consumer-fixture`, `check`
- `.github/workflows/ci.yml` — two new jobs
- `README.md` — consumer dependency contract, vendoring rationale, checks table

### Unchanged on purpose

`src/fhevm-host/` (vendored source), `src/HCULimitNoDepthCap.sol`, `src/DeployableERC1967Proxy.sol`,
`src/cleartext/CleartextFHEVMExecutor.sol`, `script/DeployFHEVMHost.s.sol`, `test/helpers/*` and the
whole test suite still compile against the vendored **source**. That's deliberate: the source is what
the generator compiles, and our own tests can keep using concrete types and error selectors. Only the
*consumer-reachable* graph had to change.

### Measured result

```
before: 79 files across @openzeppelin-contracts, @openzeppelin-contracts-upgradeable,
        @openzeppelin-confidential-contracts, @fhevm-solidity, @encrypted-types, forge-std
after:  40 files across @encrypted-types, forge-std
        remappings a consumer must provide: encrypted-types/, forge-std/
```

Consumers need three remappings total (`forge-fhevm/`, `forge-std/`, `encrypted-types/`).
Zero OpenZeppelin files. 391/391 tests pass, unchanged.

---

## 3. The non-obvious constraints — read before touching `_deployAllContracts`

These are the things that cost the most time to find. All three are commented in
`src/FhevmTest.sol`, but they're worth stating up front because each fails in a confusing way.

### 3.1 `vm.etch` does **not** work for the implementations

Every UUPS host contract bakes `UUPSUpgradeable.__self = address(this)` into its runtime code
(3 splice sites; visible as `immutableReferences` in the artifact). `_checkProxy()` reverts unless
`ERC1967Utils.getImplementation() == __self`. A statically etched artifact blob carries **zero
placeholders** there, so every `upgradeToAndCall` would revert.

→ Implementations are deployed with `CREATE` on an embedded **creation** blob (`_deployBlob`), so the
constructor runs and immutables are set. Only `PauserSet` (no constructor, no immutables) and the
ERC-1967 proxy (no immutables) are etched.

**If a future host contract gains an immutable and you add it to `RUNTIME` instead of `CREATION` in
the generator, it will break silently-ish.** Default to `CREATION`.

### 3.2 The empty-proxy phase cannot be collapsed

`UUPSUpgradeableEmptyProxy.onlyFromEmptyProxy` requires `_getInitializedVersion() == 1`, which is only
true after the empty proxy's `initialize()` has run. Also `ACL.initializeFromEmptyProxy` calls
`__Ownable_init(owner())`, reading the owner set in phase 1.

→ `_installProxy` writes the ERC-1967 slot by hand (replicating the proxy constructor, which `vm.etch`
can't run), then the caller invokes `initialize()`, *then* `upgradeToAndCall`. Skipping straight to the
real implementation reverts with `NotInitializingFromEmptyProxy`.

### 3.3 ACL must be deployed first

`EmptyUUPSProxy` inherits `ACLOwnable`, whose `onlyACLOwner` reads
`Ownable2StepUpgradeable(aclAdd).owner()`. Reorder `_deployAllContracts()` and every subsequent
`_authorizeUpgrade` fails.

---

## 4. Workarounds and compromises

Ranked by how likely they are to bite.

### 4.1 `dealConfidential` signature change — **breaking**

`dealConfidential(IERC7984ERC20Wrapper, address, uint256)` → `dealConfidential(address, address, uint256)`.

Keeping the OZ-typed parameter would have pinned `@openzeppelin/contracts` **and**
`@openzeppelin/confidential-contracts` on every consumer. Any interface-typed parameter would have been
breaking anyway (Solidity has no implicit contract→interface conversion across unrelated types), so
`address` was the honest choice.

Callers write `dealConfidential(address(wrapper), user, amount)`. Not mentioned anywhere in `docs/`, so
the blast radius is small. The migration is now documented in the README.

The protected host fields also changed from concrete contract types to generated interfaces:
`FHEVMExecutor` → `IFHEVMExecutor`, `ACL` → `IACL`, `InputVerifier` → `IInputVerifier`, and
`KMSVerifier` → `IKMSVerifier`. Normal method calls remain available, but callers assigning these
fields to concrete variables must update the type or cast through `address`.

### 4.2 `FheType` post-processing in the generator — string matching

`cast interface` flattens enum parameters into a local `type FheType is uint8;`, which is a *distinct*
type from the shared enum callers pass. The generator strips that line and injects an import of the
real (OZ-free) `shared/FheType.sol`.

The match is on the literal string `type FheType is uint8;`. **If `cast`'s output format changes, this
silently stops firing and the build breaks with confusing conversion errors** (that's how it first
surfaced). It's guarded by `check-generated` + the test suite, so it fails loudly in CI, but the
diagnosis isn't obvious. Parsing the ABI JSON directly was considered during review, but replacing
this small pinned-tool workaround with a larger custom generator is not justified unless it becomes
an actual maintenance problem.

### 4.3 Generation uses the default compiler profile

Blobs are byte-identical to what the test suite compiled *before* this change — which is why 391 tests
pass untouched — but **not necessarily identical to what's deployed on mainnet**. We do not currently
match upstream's solc version / optimizer runs / metadata settings.

Public wording now states the precise guarantee: the contracts are built from vendored upstream
source, but local compiler settings do not prove byte-identical fidelity with a live deployment.
See §6.1 for the optional stronger check.

### 4.4 The fixture copies `src/` rather than doing a real install

`check-consumer-fixture` does `cp -r src fixtures/consumer/dependencies/forge-fhevm/src`, mimicking a
soldeer layout. It doesn't exercise soldeer's actual packaging (`.gitignore` filtering, `files` field,
version resolution). Good enough to catch remapping and relative-import breakage; won't catch a
packaging manifest problem.

The fixture also `cd`s in the Makefile recipe because `forge soldeer install` has no `--root`.

### 4.5 The fixture is an integration check, not an exact compile-graph assertion

If `FhevmTest` re-imported host source, the fixture *might* still compile because OZ 5.4 versus 5.1
isn't guaranteed to conflict. A custom import-graph checker was considered and removed during review:
maintaining a Solidity import parser was disproportionate to the current need. The fixture keeps the
original downstream scenario covered without claiming to prove the exact set of reachable packages.

### 4.6 `make generate` skips `FhevmTest` and `test/**`

Those import the files being generated, so building them first makes regeneration impossible from a
clean tree. The skip flags are load-bearing — I hit exactly this bug and fixed it. **If you add a new
consumer-facing file that imports `src/generated/`, add it to the skip list**, or `make generate` breaks
on a clean checkout while continuing to work on your machine.

Verified: `rm -rf src/generated && forge clean && make generate` reproduces byte-identical output.

---

## 5. Areas to watch

- **Regenerate after *any* change under `src/fhevm-host/`.** `make update-host-contracts` now does it
  automatically; a manual edit does not. `make check-generated` catches it in CI.
- **Adding an import to `FhevmTest.sol` can re-pin a dependency on every consumer.** Treat its import
  surface as part of the consumer interface and exercise dependency changes through the fixture.
- **Determinism** depends on the pinned `solc = "0.8.27"` plus `cbor_metadata = false` /
  `bytecode_hash = "none"`. If someone changes those, blobs churn and `check-generated` fails on
  unrelated PRs.
- **`reinitializer(REINITIALIZER_VERSION)`** — if upstream bumps a host contract's reinitializer
  version, the two-phase init sequence may need revisiting. Currently every
  `initializeFromEmptyProxy` requires initialized version exactly 1.
- **The `HostBytecode.sol` diff is suppressed** via `.gitattributes`. Generated interface diffs stay
  visible. `check-generated` is what verifies the unreviewable bytecode; do not disable that job.

---

## 6. Worth improving

Roughly in value order.

### 6.1 On-chain fidelity check (the big one)

Read the ERC-1967 implementation slot of each canonical proxy on Sepolia (`cast storage`), pull
`cast code`, compare against our generated runtime. This is the only check that proves the blobs match
what's actually deployed — everything we have today only proves internal consistency with the vendored
source.

Needs a `[profile.hostgen]` reproducing upstream's compiler settings (solc version, optimizer runs,
metadata). A comparison must also normalize the UUPS `__self` immutable reference, which legitimately
contains a different implementation address in local and live deployments. Start advisory; promote to
blocking only if it goes reliably green. It may not be achievable — worth timeboxing.

### 6.2 No source-vs-blob parity test

The original source-deployment path was **replaced**, not kept alongside. We can't currently A/B the
two. The 391 passing tests are strong evidence the blob path is equivalent, but if you want a
standing guarantee, parameterize `_deployAllContracts` on mode and run the suite twice.

### 6.3 Split `HostBytecode.sol`

One 180 KB file. Per-contract files would make `git` and editors happier and allow regenerating only
what changed. Cosmetic.

### 6.4 Interfaces not exposed for everything

`IPauserSet` (vendored, OZ-free) and `IHCULimit` exist but aren't surfaced as public fields on
`FhevmTest`. If consumers ask for `_hcuLimit` / `_pauserSet`, the interfaces are already generated.

### 6.5 Upstream sync stays manual — by design

We explicitly decided **not** to auto-sync from `zama-ai/fhevm` releases: what's on GitHub is not
necessarily what runs on the live network, so a human always submits the contract update PR.
`make update-host-contracts FHEVM_VERSION=vX.Y.Z` is the entry point. Don't add a cron for this.

---

## 7. Verification

```bash
make check                      # everything below, plus the full suite
make check-generated            # src/generated/ matches the vendored source
make check-consumer-fixture     # downstream project on OZ 5.4 builds and passes
make generate                   # regenerate after touching src/fhevm-host/
```

Confirmed green:
- 391/391 library tests
- 2/2 consumer-fixture tests, against **OZ 5.4** while this repo builds on **5.1.0**
- `forge fmt --check`
- byte-identical regeneration after `forge clean`

---

## 8. Open questions for the team

1. **Release versioning** for the documented source-level breaks — forge-fhevm has no changelog
   convention in the repository today.
2. **Is mainnet-bytecode fidelity (§6.1) in scope**, or is source-faithful vendoring the standing
   contract? Public wording has been softened so this no longer blocks the current change.
3. **Hand to Aryeh for review, or ship from devX?** He offered to write it; this is a finished
   implementation, so the useful thing is probably his review as the consumer who hit the problem.
