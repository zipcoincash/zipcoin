# The Reader

> "2,800,000 zipped for whoever reads the book closely enough. Nothing more will be said."

2,800,000 $ZC sit in the zipcoin Privacy Pool under a 12-word zip phrase. The phrase is in this repo, encrypted. The key is six numbers from Vitalik Buterin's novel [Snowmoon](https://vitalik.eth.limo/snowmoon/html/). Read carefully, decrypt, unzip. First valid unzip takes everything.

## The six answers

All answers are numbers exactly as the book writes them in digits (decimal point, no thousands separators, no units, no words).

1. In Veridia, what does Gladias's salad cost before tax?
2. What is the sales tax on it?
3. How many zipcoins does Emerald borrow against Gladias's reputation?
4. How many zipcoins did the anonymous person burn to send the message from the food court?
5. How many zipcoins did Mov burn while Seila waited at a stranger's door?
6. The street number of the Beautiful Plants food court.

Lowercase everything, join with `|` and nothing else, SHA-256 it: that is the AES-256-GCM key for `prize.json`.

```bash
pip install cryptography
python3 solve.py <a1> <a2> <a3> <a4> <a5> <a6>
```

Wrong answers fail the authentication tag; there is no partial credit and nothing to brute-force but the book.

## Claiming

1. Go to https://zipcoin.cash/unzip, pick **use a 12 word zip phrase**, paste the phrase.
2. Enter any address (a fresh one, if you like privacy) and unzip the full note. The proof is built in your browser; the relayer pays the gas and keeps 1% (28,000 ZC). You receive 2,772,000 ZC.
3. That's it. The unzip transaction is the only announcement. Nobody, including us, learns who you are unless you say so.

## Fair play

- The prize note is a normal deposit in the pool. Deposit tx: _added once the note is approved_.
- Until it is claimed, the depositing wallet could technically pull it back with `ragequit`. We won't, and the chain will show that we didn't.
- Two people can decrypt at the same time; only the first proof that lands on chain spends the note. The second gets `NullifierAlreadySpent`.
- No hints, no timer. The book has 32 chapters; the answers are in three of them.

Code for everything else: https://github.com/zipcoincash/zipcoin
