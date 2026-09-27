# ZIPCOIN ($ZC) — spec v1 (2026-09-27)

> "Vitalik wrote the currency. We shipped it."

Source lore: Vitalik's novel *Snowmoon* (full 32 chapters at `vitalik.eth.limo/snowmoon/html/`, went public ~Sep 27 2026).
Zipcoin is Veridia's money. In the book it is: fully anonymized (ch6, ch19), burned to make a message worth reading (ch19 "burned four hundred zipcoins to send this message", ch20 "50 zipcoins have just been burned 🔥", ch27 paid Silverchat polls), taxed automatically in real time (ch6), and borrowed against reputation with nullifiers (ch6, v2).

Market context at spec time (13:04 UTC): ~25 "zipcoin" tickers already live, ETH leader `0x2CA7…a46E` ~$1.5M mc 20 min after launch. **None of them do anything.** Our edge = the only zipcoin that works like the book.

---

## 1. Product (day 1)

| Book mechanic | Our feature | Tech |
|---|---|---|
| "Payment is done in zipcoins, that's fully anonymized" | **Zip / Unzip** — deposit ZC, withdraw any amount to any fresh address, unlinkable | Privacy Pools (0xbow, Apache-2.0) — our own Entrypoint + ERC20 pool, reusing the **mainnet ceremony verifiers** |
| "An anonymous person burned 400 zipcoins to send this message" | **Burn to speak (anon)** — burn from your zipped balance, post a message nobody can link to you, addressed to a set ("to: someone who ate at Beautiful Plants, 18, successful") | Withdrawal whose `processooor` is our `ZipBroadcaster`; message lives in `withdrawal.data`, bound into the ZK proof via `context` |
| "50 zipcoins have just been burned 🔥" | **Burn to speak (public)** — cheap, from wallet | `ZipBroadcaster.publicBurn` |
| Silverchat paid polls | Feed ranking: bigger burn = higher + longer pin + TG push | indexer |
| Real-time sales tax to the government | **Veridian sales tax** page — creator fee accrual/claims, live | sender locker events |

Out of scope (v2): Gladias reputation loan (nullifier-backed 2773 ZC credit line).

## 2. Launch venue — sender.family (decided)

Verified from the deployed source (`SendItFactory` / `LaunchToken`, Etherscan-verified, Solidity 0.8.26):
- ETH mainnet, Uniswap v4, whole 1B fixed supply in one locked position, no mint/owner/pause, LP unpullable.
- `LaunchToken._update`: after the 3-block launch guard (creator-only block, then buy/hold caps) it is a **plain ERC20** — no fee-on-transfer. With `holderFees=false` no reward hooks run. ⇒ safe to hold in the privacy pool.
- Fees: 1% per swap; **70% creator forever** (claim via locker), 24% $SEND burn, 6% protocol. Launch fee Ξ0.002. Dev buy in launch tx, publicly shown.
- Metadata must be hosted by sender (only renders its own) ⇒ launch through their create flow (or their metadata upload), `holderFees=false`, ETH pair.
- Current gen: Factory `0x8D37c2981bdF809567092fd458B6bf3e97ee860c`, Locker `0x844833D98765344eE206598a81f31ad3CC15b1a4`.

Why not a custom token: all the magic lives in the pool, which accepts any plain ERC20. A custom token would cost our own LP ETH, lose discoverability and locked-LP trust, and a tax token would break pool accounting. Nothing to gain.

## 3. Contracts

| Contract | Source | Notes |
|---|---|---|
| `$ZC` | sender `LaunchToken` clone | ETH pair, holderFees=false |
| `Entrypoint` (UUPS proxy) | 0xbow `privacy-pools-core/packages/contracts` | our deployment; we hold OWNER + POSTMAN |
| `PrivacyPoolComplex(ZC)` | 0xbow | constructor wired to mainnet ceremony verifiers: WithdrawalVerifier `0x022891f938ae7fdc8ab9ead0fbf50aba8c897d6d`, Ragequit/CommitmentVerifier `0xa45aca8604a73d80c551faad6355a5c3a5565ec6` (read from 0xbow ETH pool `0xF241d57C…C9fB`, 5,932 deposits) ⇒ no trusted setup of our own |
| `ZipBroadcaster` | **new, ~100 lines** | see below |

`ZipBroadcaster`:
- `broadcast(Withdrawal w, WithdrawProof p)`: requires `w.processooor == address(this)`; calls `pool.withdraw(w, p)`; decodes `w.data = abi.encode(string message, string target, address feeRecipient, uint16 relayFeeBps)`; pays relay fee; sends the rest to `0x000000000000000000000000000000000000dEaD`; `emit Broadcast(nullifierHash, burned, message, target)`. Message + fee terms are bound by the proof (`context = keccak256(abi.encode(w, scope))`), so a relayer cannot alter them.
- `publicBurn(uint256 amount, string message, string target)`: `transferFrom(msg.sender, dEaD)` + same event with `sender`.
- Limits: message ≤ 280 bytes, target ≤ 120 bytes, min burn configurable by owner (immutable after launch? decide).

## 3b. Build status (2026-09-27)

- Contracts: `ZipBroadcaster` done; mainnet-fork suite 7/7 green with real proofs against the live mainnet verifiers on a real sender launch.
- Services: relayer (validation + simulate + gas floor + subsidy budget), ASP postman loop, feed/stats APIs, Telegram loop — all inside the Next server.
- Frontend: all five pages; zip key derived from a wallet signature (or 12-word phrase); proofs generated in the browser.
- Rehearsals: headless e2e (zip → postman → anon speak → unzip → public speak) and headless Chromium anon speech both pass on the fork.
- Runbook: `README.md`.

## 4. Money (where we earn — explicit)

1. **Sales tax** = sender creator share: 0.7% of all $ZC volume, in ETH, forever.
2. **Vetting fee** on zips (Entrypoint `vettingFeeBPS`, proposed 50 bps) → ZC to Entrypoint owner.
3. **Relay fee** on unzips / anon broadcasts (100 bps, capped by `maxRelayFeeBPS`). L1 gas per relay is ~$7, so a flat 1% only covers it above ~$700; the relayer enforces a live gas floor, optionally subsidised from the sales tax (`RELAY_SUBSIDY_BPS`, daily cap). Recommended: full subsidy at launch, capped.
4. Burns shrink supply (not revenue, but the narrative).

## 5. Off-chain services

- **Relayer** — 0xbow `packages/relayer`, configured for our Entrypoint + `ZipBroadcaster` route; own hot wallet with a small ETH float; verifies proof off-chain before sending.
- **ASP / postman** — watches `Deposited`; auto-approves labels after 10 min unless depositor is on a blocklist (OFAC SDN crypto addresses + known exploit wallets); pushes `updateRoot(root, cid)` only when there are new approvals (batch ≤ every 10–15 min). Unapproved depositors can always `ragequit`.
- **Indexer + API** — viem `getLogs` over pool / Entrypoint / Broadcaster / sender locker → SQLite/Postgres → feed + stats.
- **TG bot** — posts broadcasts above a burn threshold + big zips/unzips (amounts only).

## 6. Frontend (Next.js + wagmi/viem + `@0xbow/privacy-pools-core-sdk`, browser proving)

- `/` — hero line, live counters: ZC burned, zipped TVL, anonymity-set size, sales tax collected, latest broadcasts.
- `/zip` — connect → create/import **zip phrase** (BIP-39, shown once, never stored server-side; SDK warns against localStorage) → approve → deposit.
- `/unzip` — zip phrase → `AccountService` recovery → amount + recipient → proof in browser → relayer → tx.
- `/speak` — anon (from zipped balance) or public (from wallet); message + optional target set; feed ranked by burn.
- `/tax` — Veridian sales tax: creator fee accrual/claims, vetting/relay fees, burns.
- Copy/easter eggs from the book ("Forgot your wallet at home?", 2773, "Two ticks later, it confirmed").
- Honest UI: shows anonymity-set size and warns when it is small; wallet is required to zip / public-burn only.

## 7. Build plan (~12–16 focused hours)

| Block | Work | Gate |
|---|---|---|
| P0 preflight (1h) | clone 0xbow repo, Foundry, compile + tests; confirm `PrivacyPoolComplex` constructor, verifier vkey = final-keys, `withdraw` callable by a processooor contract with custom `data` | read-only |
| P1 contracts (3h) | `ZipBroadcaster` + forge tests; mainnet-fork test with a **real sender token** (existing current-gen launch): deposit → root → withdraw → broadcast | local fork |
| P2 services (3h, parallel) | relayer config, postman, indexer, TG bot | Sepolia (mock ERC20) |
| P3 frontend (5h, parallel) | pages above, SDK proving in browser | Sepolia |
| P4 e2e (1–2h) | full Sepolia run: zip → unzip → anon speak → public speak → feed | — |
| P5 launch | see §8 | **human GO** |

Cut order if late: `/tax` → static numbers, TG bot → manual, public burn stays, anon speak + zip/unzip never cut.

## 8. Launch sequence (T0, needs GO)

1. Deploy `Entrypoint` (mainnet) from a fresh deployer.
2. Launch `$ZC` on sender (ETH pair, holderFees=false, disclosed dev buy).
3. Deploy `PrivacyPoolComplex(ZC)` + `registerPool(ZC, pool, minDeposit, vettingBps, maxRelayBps)` + `ZipBroadcaster`.
4. Flip site env to mainnet addresses, relayer + postman live, first public burn from the dev wallet ("50 zipcoins have just been burned 🔥").
5. Post: book quote + site + contract.

## 9. Budget (ETH ≈ $2,700, ~6 gwei effective today — re-measure on fork)

- Deploys (Entrypoint + pool + broadcaster + register): ~0.06 ETH
- sender launch fee: 0.002 ETH + dev buy (human sets; Ξ0.1 ≈ 3% supply)
- Relayer float: 0.05 ETH; postman root updates ~0.0005 ETH each
- ≈ 0.12 ETH + dev buy

## 10. Risks

- **Legal**: privacy tool + we run relayer/ASP. Mitigation: Privacy Pools compliance model (screened association set, ragequit, no custody), attribution per Apache-2.0, ToS. Human's call.
- **Unaudited parts**: `ZipBroadcaster` (ours) and sender contracts. 0xbow core has audits in-repo.
- **Weak anonymity early**: small set on day 1 — disclosed in UI.
- **Mainnet gas**: small zips uneconomic; set `minDeposit` + min unzip.
- **Narrative decay**: hype is hours old; ship within ~24h or it is gone.

## 11. Open decisions (human)

1. Name/ticker: `zipcoin` / `$ZC` (book uses "zc")?
2. Dev buy size (disclosed).
3. Fees: vetting 50 bps / relay 100 bps / minDeposit?
4. Hosting: Vercel (site) + Railway (relayer, postman, indexer, bot)?
5. OK running the relayer + ASP ourselves?
6. Relay gas: subsidy % and daily cap (e.g. 100% up to 0.2 ETH/day).
7. WalletConnect project id (reown) so mobile wallets work; without it only injected / Rabby / Coinbase.
