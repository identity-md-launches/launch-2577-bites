bites (BIT) is a fixed-supply ERC-20 token for Ethereum. Deployable contract:
[`src/BitesToken.sol`](src/BitesToken.sol), Solidity identifier `BitesToken`.

| Parameter | Value |
| --- | --- |
| Name | `bites` |
| Symbol | `BIT` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` BIT |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Initial recipient | Immediate constructor caller, `msg.sender` |
| Constructor arguments | None; ABI argument list `[]` |
| Constructor ETH value | `0` |
| Initialization calls | None |
| Target chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM / optimizer | Cancun / enabled, 200 runs |
| Metadata bytecode hash | `none` |

The constructor mints the entire supply once and emits
`Transfer(address(0), deployer, INITIAL_SUPPLY)`. For a factory deployment the
factory receives every token, regardless of the transaction origin or the caller
of the factory. There are no external constructor calls or linked libraries.
The creation bytecode needs no appended constructor arguments. The build artifact
is `out/BitesToken.sol/BitesToken.json`.

The requested token is interpreted as a plain ERC-20, implemented using the
vendored OpenZeppelin Contracts v5.0.2 ERC-20 base. There are no transfer fees,
rebases, taxes, burns, mint methods, administrative roles, pause or blacklist
controls, upgrades, or external dependencies at runtime. Every transfer delivers
the requested amount. The deployer has the same transfer rights as any holder;
deployment does not confer power over anyone else's balance.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
the inherited ERC-6093 custom errors on invalid addresses, insufficient balances,
or insufficient allowances. Zero-value transfers between nonzero addresses
succeed and emit `Transfer`. Self-transfers preserve balances. Approving the zero
address or transferring to it reverts, including for an amount of zero.

An approval replaces the previous allowance. Finite allowances decrease on
`transferFrom`; an allowance of `type(uint256).max` remains unchanged until the
holder changes it. Failed transfers revert all changes, including allowance
consumption. `approve` emits `Approval`; allowance consumption in this version of
OpenZeppelin does not emit an additional `Approval` event. Indexers should read
`allowance` for the current value.

Build and check from the repository root using Foundry with Solidity 0.8.26
available locally:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xe0ae7ec635a250afe7d26df766425909521d565ae9b99d4668bbd4ab9ac8eae6 forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`.
No dependency installation, network fork, RPC endpoint, secret, environment file,
FFI, or filesystem cheatcode permission is needed. Tests read no environment
variables; the optional seed above is interpreted by Foundry itself. The
configuration runs each fuzz test 1,024 times and each stateful invariant for 128
sequences of 64 calls. Dependency versions and archive checksums are recorded in
[`DEPENDENCIES.md`](DEPENDENCIES.md).

The tests cover metadata, the exact constructor allocation and mint event,
CREATE2 factory deployment, transfers, approvals, delegation, finite and infinite
allowances, event fields, zero values, self-transfers, authorization failures,
invalid addresses, balance/allowance rollback, and rejected mint/admin/upgrade
calls. Stateful tests compare randomized transfers and approvals to an independent
accounting model and verify supply conservation.

The local factory test verifies exact token movements for the launch's 10% swarm,
70% pool, and 20% remainder split, followed by a claim and transfers both ways
between a pool address and a trader. Those addresses are test fixtures. This test
does not implement or verify Uniswap pricing, liquidity, or settlement. The
network's supplied protected harness performs the actual pool integration checks
using its launch contracts, resolved manifest, and environment. Those launch
components are not part of this token project.

For deployment, the IdentityMD launch process supplies the factory and writes its
manifest separately. It must select `BitesToken`, use an empty constructor argument
list, record the supply and decimals above, and deploy the built creation code
with zero ETH. The factory performs the swarm allocation, pool seeding, and
remainder distribution. The token constructor does not distribute or reserve any
of the supply itself. There are no application contracts to launch. This project
does not need a signer, owner, oracle, router, or recipient parameter, and includes
no broadcast script or launch manifest.

After launch, no owner settings, maintenance calls, or keeper duties exist. The
launch operator is responsible for checking deployed code and metadata, verifying
source on the explorer, checking the constructor mint and subsequent allocation
events, and completing the network's independent review and pool checks. Holders
are responsible for recipient accuracy and approval management. To replace a
nonzero allowance safely, first submit an approval of zero and wait for confirmation
before approving the new amount; prefer only the allowance required by the intended
operation. An already authorized spender may spend before a pending revocation is
confirmed.

The contract cannot recover tokens sent to an unintended address or to itself.
Plain ETH transfers revert, and there is no rescue function for forcibly sent ETH
or other assets. The unit, fuzz, and invariant checks are local verification, not
an independent security audit. No live deployment or transaction is performed by
this project.

Local validation completed with Solidity 0.8.26: `forge build`, `forge test` with
the specified seed, and `forge fmt --check` all passed. Foundry reported 36 passing
tests, including four fuzz tests at 1,024 runs each and a grouped invariant suite
with two properties across 8,192 calls and zero reverts. A forced rebuild and test
run also passed with `--offline` and a cleared environment (only executable search
paths were supplied; the seed was passed as a CLI argument). All vendored-file
checksums passed. The deployed runtime is 1,752 bytes and has no library link
references. Slither, Mythril, and the network-owned protected integration harness
were not run locally.

