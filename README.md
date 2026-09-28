# zipcoin ($ZC)

> "Only Gladias and the restaurant knew that a 10.5 zipcoin order had been made." — *Snowmoon*, ch. 6

The currency from Vitalik Buterin's novel [Snowmoon](https://vitalik.eth.limo/snowmoon/html/), shipped on Ethereum mainnet. Not affiliated with the author.

- **Zip / unzip** — deposit $ZC into a Privacy Pool, withdraw any amount to any address with a zero-knowledge proof built in your browser. (0xbow [privacy-pools-core](https://github.com/0xbow-io/privacy-pools-core), the design from the 2023 Privacy Pools paper.)
- **Burn to speak** — burn zipcoins to post a message; the bigger the burn, the louder. Publicly from a wallet, or anonymously from a zipped note through a relayer that cannot alter the message.
- **The Doorstep** — burn at someone's door (ENS name or address) and optionally leave an anonymous gift. Every door has a page (`/door/vitalik.eth`) that collects everything burned there. Ch. 20.
- **Veridian sales tax** — 0.5% of every trade flows to the treasury on-chain, in real time.

Site: https://zipcoin.cash · X: [@zipcoincash](https://x.com/zipcoincash) · Token: `0x4E67DB19044549fF420860834c91b45BaD298722`

## Verify it yourself

- Proofs are generated client-side: `web/src/lib/zip.ts` (`proveSpend`). Circuit artifacts in `web/public/artifacts/` match the SHA-256 digests published by the 0xbow SDK, and the on-chain verifiers are the ones securing 0xbow's own mainnet pool (`0x022891F9…7D6d`, `0xa45ACa86…5eC6`). Nobody on the zipcoin side can forge a proof.
- The zip key is derived in the browser from a wallet signature (`masterKeys`, `mnemonicFromSignature`); it is never sent anywhere. The 12-word phrase is portable to any Privacy Pools tooling.
- The relayer (`web/src/lib/server/relayer.ts`) can only submit what the proof already binds: recipient, fee and message live in `withdrawal.data`, which is hashed into the proof's `context`. See `contracts/ZipcoinFork.t.sol::test_speakAnon_relayerCannotRewriteMessage`.
- The pool never depends on the association set for custody: any depositor can `ragequit` back to their own wallet.
- The burn contract (`contracts/ZipBroadcaster.sol`) has no owner and holds nothing between calls. Burns go to `0x…dEaD`.

## Layout

- `contracts/` — our Solidity (burn contract, mainnet-fork tests, deploy scripts) and deployment addresses. They live inside [our fork of privacy-pools-core](https://github.com/zipcoincash/privacy-pools-core/tree/zipcoin) (branch `zipcoin`); see `contracts/README.md`.
- `web/` — Next.js app: UI, `/api/state` (pool index), `/api/relay` (relayer with gas floor + subsidy budget), `/api/feed`, `/api/stats`, `/api/health`; background loops for the association-set postman, watchdog alerts and fee sweeping (`src/instrumentation.ts`).
- `scripts/` — deploy the stack for a token, go-live, local anvil-fork rehearsal.
- `SPEC.md` — the original build spec.

## Run

```bash
cd web && pnpm install && cp .env.example .env.local   # fill in RPCs and keys
pnpm exec next dev -p 3100
pnpm exec tsc --noEmit && pnpm exec eslint src && pnpm exec next build
```

Local mainnet-fork rehearsal (real launchpad token, real proofs): `anvil --fork-url <archive rpc> --chain-id 31337`, then `./scripts/local-up.sh`, then `pnpm dlx tsx scripts/e2e.mts` in `web/`.

## Trust and risks

The Privacy Pools contracts are audited upstream; `ZipBroadcaster` and the launchpad contracts are not. The Entrypoint is upgradeable by the zipcoin owner key, like the original. The relayer and association set are run by the team: they can delay approvals or refuse to relay, they cannot move coins. Anonymity grows with pool usage. $ZC is a volatile token; nothing here is investment advice.

MIT for our code. Vendored and forked components keep their own licenses (privacy-pools-core: Apache-2.0).
