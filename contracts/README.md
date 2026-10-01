# zipcoin contracts

Everything that is ours, on top of 0xbow's [privacy-pools-core](https://github.com/0xbow-io/privacy-pools-core) (Apache-2.0):

- `ZipBroadcaster.sol` — burn-to-speak. `speakAnon` spends a Privacy Pool note (this contract is the withdrawal `processooor`; the message is sealed into the proof through `context`), `speak` burns from a wallet. No owner, holds nothing between calls.
- `ZipDoorstep.sol` — the Doorstep: burn at an ENS name or address with an optional gift, anonymously from a zipped note or publicly. Second independent processooor on the same pool; gift ≥ 10x burn is rejected.
- `ZipTeller.sol` — pay a zk.money tag from a zipped $ZC note: the proof binds the recipient (a fresh deposit address from zk.money's ENS resolver), a DAI minimum and a deadline; the contract sells ZC → WETH on its own pool and WETH → DAI on Uniswap v3, and sends the DAI. Capped at zk.money's 2,500 DAI per deposit.
- `ZipTellerEth.sol` — the same from a zipped **ETH** note in [0xbow's canonical mainnet pool](https://docs.privacypools.com/deployments) (`0xF241d57C…C9fB`). We are a processooor there: their pool only checks `msg.sender == processooor`, their ASP screens deposits, their fee is theirs.
- `ZipTellerStable.sol` — pay a zk.money tag from a **DAI, USDC or USDT** note in 0xbow's stablecoin pools (one instance per pool): DAI is paid as itself with no swap; USDC and USDT take one 0.01% hop on Uniswap v3.
- `ZipHearth.sol` — speak, or knock at a door, from an ETH note in 0xbow's pool: an optional gift is left in ETH, the rest buys $ZC (paying the sales tax like any trade) and burns it with the message through `ZipDoorstep`, so the word lands in the same book.
- `ZipcoinFork.t.sol`, `ZipDoorstepFork.t.sol` — mainnet-fork suites: real launchpad token, real Groth16 proofs checked by the verifiers already live on mainnet.
- `Zipcoin.s.sol` — deploy scripts: Entrypoint as an ERC1967 proxy over 0xbow's live implementation, pool + broadcaster per token.
- `deployments/` — addresses.

These files live at `packages/contracts/src/zipcoin`, `test/zipcoin`, `script/zipcoin` inside [our fork of privacy-pools-core](https://github.com/zipcoincash/privacy-pools-core/tree/zipcoin) (branch `zipcoin`), together with a two-line remapping fix for forge 1.8. Run there:

```bash
ETHEREUM_MAINNET_RPC=<archive rpc> FORK_BLOCK=26069500 forge test --ffi --match-contract Zip   # sender.family paused launches on Sep 27, so the suite pins a block where launching still worked
```

Mainnet: Entrypoint `0x7a8DA01D241C3cFcF7803cdB007EcE5663749193`, $ZC pool `0x6d0eBA4D1E2665bF2256507E8b0124C647ada422`, burn contract `0x992550B536749125D63d5F9c19fea765232D6928`, Doorstep `0x1813A541FB107C5E9b46e9cbB04e67140bCE7730`, ZipTeller `0x555E8A0CEAD850Ac195BAf160Aead84d5C8826ff`, ZipTellerEth `0x7EAA5f0cb82232F7a673ef0fA74a2B2264b336F0`, ZipHearth `0x5D711e59DeEBfAFbC8223eBE9A8f4Df286Af0531`, ZipTellerStable for DAI `0x65614F5c532e525891302B7eD6050f5B6b777dAd`, USDC `0x0F6E7E5269be27e8f40C55DE5FFc5E99abCC406f`, USDT `0xc3288A1cA1206D9EA0b21caF7daF03B8f831FC13` (all verified on Etherscan; no owner, hold nothing between calls). 0xbow's pools behind their Entrypoint `0x6818809EefCe719E480a7526D76bD3e561526b46`: ETH `0xF241d57C6DebAe225c0F2e6eA1529373C9A9C9fB`, DAI `0x1c31C03B8CB2EE674D0F11De77135536db828257`, USDC `0xb419c2867aB3CBc78921660cB95150d95A94ce86`, USDT `0xe859C0bD25f260BaEE534Fb52e307D3b64D24572`. Verifiers: withdrawal `0x022891F938Ae7fDC8Ab9Ead0FBf50aBA8C897D6d`, ragequit `0xa45ACa8604a73D80C551fAad6355A5c3A5565eC6` (0xbow trusted setup).
