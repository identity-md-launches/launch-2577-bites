All dependencies are vendored as ordinary source files and retain their upstream
licenses. Building and testing requires no package manager or submodule fetch.

| Dependency | Pinned tag | Vendored contents | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093 | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | `src/` (test support only) | MIT OR Apache-2.0 |

OpenZeppelin source files are under `lib/openzeppelin-contracts/contracts/`, with
the upstream `LICENSE` alongside. Forge standard library source files are under
`lib/forge-std/src/`, with `LICENSE-MIT` and `LICENSE-APACHE` alongside. Source bytes
are unchanged from the pinned archives. Upstream tests, build artifacts, package
manager configuration, and repository metadata are not needed and are omitted.

Archive provenance (SHA-256):

```text
https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a

https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
```

[`DEPENDENCIES.sha256`](DEPENDENCIES.sha256) also records every vendored file's
SHA-256 hash. Verify the local copies with `sha256sum -c DEPENDENCIES.sha256`.

