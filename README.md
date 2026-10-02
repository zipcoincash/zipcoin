# zipcoin ($ZC)

> "Only Gladias and the restaurant knew that a 10.5 zipcoin order had been made." — *Snowmoon*, ch. 6

The currency from Vitalik Buterin's novel [Snowmoon](https://vitalik.eth.limo/snowmoon/html/), shipped on Ethereum mainnet. Not affiliated with the author.

- **Zip / unzip** — deposit $ZC into a Privacy Pool, withdraw any amount to any address with a zero-knowledge proof built in your browser. (0xbow [privacy-pools-core](https://github.com/0xbow-io/privacy-pools-core), the design from the 2023 Privacy Pools paper.)
- **Burn to speak** — burn zipcoins to post a message; the bigger the burn, the louder. Publicly from a wallet, or anonymously from a zipped note through a relayer that cannot alter the message.
- **The Doorstep** — burn at someone's door (ENS name or address) and optionally leave an anonymous gift. Every door has a page (`/door/vitalik.eth`) that collects everything burned there. Ch. 20.
- **Farcaster Mini App** — share any cast to zipcoin and knock at its author's door in one tap (`/fc`, `/fc/share`). Door links render as cards with a Knock button; people who added the app get buzzed when someone knocks at theirs (webhook + Postgres + `notifier.ts`). Manifest at `/.well-known/farcaster.json`.
- **Veridian sales tax** — 0.5% of every trade flows to the treasury on-chain, in real time.
- **Private AI chat** — [chat.zipcoin.cash](https://chat.zipcoin.cash): fund a browser-only key from a zipped note, deposit into [zkAPI](https://github.com/ethereum/zkapi)'s vault, talk to any model with short-lived keys straight from the browser. No account, no wallet connection; ask about a tx, a contract or a wallet without telling anyone it is yours; burn ZC to publish an answer to the Book; gift links. Open source: [zipcoincash/zipcoin-chat](https://github.com/zipcoincash/zipcoin-chat). Works with zkAPI (Open Anonymity + EF dAI); experimental, no affiliation.

Site: https://zipcoin.cash · X: [@zipcoincash](https://x.com/zipcoincash) · Token: `0x4E67DB19044549fF420860834c91b45BaD298722`

## Verify it yourself

- Proofs are generated client-side, in your browser, with the [0xbow SDK](https://github.com/0xbow-io/privacy-pools-core) and its published circuit artifacts (`https://zipcoin.cash/artifacts/…`, SHA-256 digests match the SDK's). The on-chain verifiers are the ones securing 0xbow's own mainnet pool (`0x022891F9…7D6d`, `0xa45ACa86…5eC6`). Nobody on the zipcoin side can forge a proof.
- The zip key is derived in the browser from a wallet signature (`masterKeys`, `mnemonicFromSignature`); it is never sent anywhere. The 12-word phrase is portable to any Privacy Pools tooling.
- The relayer can only submit what the proof already binds: recipient, fee and message live in `withdrawal.data`, which is hashed into the proof's `context`. See `contracts/ZipcoinFork.t.sol::test_speakAnon_relayerCannotRewriteMessage`. Every spending contract (`ZipBroadcaster`, `ZipDoorstep`, `ZipTeller`, `ZipTellerEth`, `ZipHearth`) is verified on Etherscan, has no owner, and holds nothing between calls.
- The pool never depends on the association set for custody: any depositor can `ragequit` back to their own wallet.
- The burn contract (`contracts/ZipBroadcaster.sol`) has no owner and holds nothing between calls. Burns go to `0x…dEaD`.

## Layout

- `contracts/` — our Solidity (burn contract, mainnet-fork tests, deploy scripts) and deployment addresses. They live inside [our fork of privacy-pools-core](https://github.com/zipcoincash/privacy-pools-core/tree/zipcoin) (branch `zipcoin`); see `contracts/README.md`.
- `scripts/` — deploy the stack for a token, go-live, local anvil-fork rehearsal.
- The chat app lives in its own repo: [zipcoin-chat](https://github.com/zipcoincash/zipcoin-chat). The agent SDK and MCP server: [zipcoin-agent](https://github.com/zipcoincash/zipcoin-agent).

The website (zipcoin.cash) is a separate, closed-source Next.js app. Everything that matters for trust is on chain and in `contracts/`: the pool, the spending contracts, and the proofs your browser builds with 0xbow's open SDK.

Local mainnet-fork rehearsal of the contracts: `anvil --fork-url <archive rpc> --chain-id 31337`, then `./scripts/local-up.sh`.

## Trust and risks

The Privacy Pools contracts are audited upstream; `ZipBroadcaster` and the launchpad contracts are not. The Entrypoint is upgradeable by the zipcoin owner key, like the original. The relayer and association set are run by the team: they can delay approvals or refuse to relay, they cannot move coins. Anonymity grows with pool usage. $ZC is a volatile token; nothing here is investment advice.

MIT for our code. Vendored and forked components keep their own licenses (privacy-pools-core: Apache-2.0).
