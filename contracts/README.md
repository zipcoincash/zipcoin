# zipcoin contracts

Everything that is ours, on top of 0xbow's [privacy-pools-core](https://github.com/0xbow-io/privacy-pools-core) (Apache-2.0):

- `ZipBroadcaster.sol` — burn-to-speak. `speakAnon` spends a Privacy Pool note (this contract is the withdrawal `processooor`; the message is sealed into the proof through `context`), `speak` burns from a wallet. No owner, holds nothing between calls.
- `ZipDoorstep.sol` — the Doorstep: burn at an ENS name or address with an optional gift, anonymously from a zipped note or publicly. Second independent processooor on the same pool; gift ≥ 10x burn is rejected.
- `ZipcoinFork.t.sol`, `ZipDoorstepFork.t.sol` — mainnet-fork suites: real launchpad token, real Groth16 proofs checked by the verifiers already live on mainnet.
- `Zipcoin.s.sol` — deploy scripts: Entrypoint as an ERC1967 proxy over 0xbow's live implementation, pool + broadcaster per token.
- `deployments/` — addresses.

These files live at `packages/contracts/src/zipcoin`, `test/zipcoin`, `script/zipcoin` inside [our fork of privacy-pools-core](https://github.com/zipcoincash/privacy-pools-core/tree/zipcoin) (branch `zipcoin`), together with a two-line remapping fix for forge 1.8. Run there:

```bash
ETHEREUM_MAINNET_RPC=<archive rpc> FORK_BLOCK=26069500 forge test --ffi --match-contract Zip   # sender.family paused launches on Sep 27, so the suite pins a block where launching still worked
```

Mainnet: Entrypoint `0x7a8DA01D241C3cFcF7803cdB007EcE5663749193`, $ZC pool `0x6d0eBA4D1E2665bF2256507E8b0124C647ada422`, burn contract `0x992550B536749125D63d5F9c19fea765232D6928`, Doorstep `0x1813A541FB107C5E9b46e9cbB04e67140bCE7730`. Verifiers: withdrawal `0x022891F938Ae7fDC8Ab9Ead0FBf50aBA8C897D6d`, ragequit `0xa45ACa8604a73D80C551fAad6355A5c3A5565eC6` (0xbow trusted setup).
