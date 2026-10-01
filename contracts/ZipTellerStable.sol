// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {IV3SwapRouter} from './ZipTeller.sol';

/**
 * @title ZipTellerStable
 * @notice Pay a zk.money tag from a zipped stablecoin note in one of 0xbow's Privacy Pools (DAI, USDC, USDT).
 * @dev One instance per pool. A processooor for 0xbow's pool: the pool only requires `msg.sender == processooor`, and
 *      the proof's context binds the recipient, the DAI minimum and a deadline. From the DAI pool the note is paid as it
 *      is, no swap at all; from USDC or USDT it takes a single 0.01% hop on Uniswap v3. The DAI goes straight to the
 *      recipient: for a zk.money deposit address, a private balance on Aztec. If any leg fails the whole call reverts
 *      and the note is not spent. No owner, holds no funds between calls.
 */
contract ZipTellerStable {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  struct Payment {
    address to;
    uint256 minOut;
    uint256 deadline;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  uint256 public constant MAX_RELAY_FEE_BPS = 1000;
  /// @notice zk.money credits deposits up to this much DAI per payment; larger ones would sit uncredited
  uint256 public constant MAX_OUT = 2_500 ether;
  /// @notice Below this the recipient's deposit fee eats the payment
  uint256 public constant MIN_OUT = 1 ether;

  IPrivacyPool public immutable POOL;
  IERC20 public immutable ASSET;
  IERC20 public immutable DAI;
  IV3SwapRouter public immutable V3;
  /// @notice Uniswap v3 fee tier of the ASSET/DAI pool used for the hop (unused when ASSET is DAI)
  uint24 public immutable SWAP_FEE;

  event Paid(address indexed to, uint256 nullifierHash, uint256 assetIn, uint256 daiOut, uint256 fee);

  error InvalidProcessooor();
  error InvalidRecipient();
  error Expired();
  error RelayFeeTooHigh();
  error MinOutOfRange();
  error TooMuchForOneDeposit();
  error TooLittleReceived();
  error ZeroAddress();

  constructor(IPrivacyPool _pool, IERC20 _dai, IV3SwapRouter _v3, uint24 _swapFee) {
    if (address(_pool) == address(0) || address(_dai) == address(0) || address(_v3) == address(0)) revert ZeroAddress();
    POOL = _pool;
    ASSET = IERC20(_pool.ASSET());
    DAI = _dai;
    V3 = _v3;
    SWAP_FEE = _swapFee;
  }

  /**
   * @notice Pay a recipient in DAI from a zipped stablecoin note, without revealing who you are
   * @param _withdrawal Withdrawal with `processooor == address(this)` and `data == abi.encode(Payment)`
   * @param _proof Withdrawal proof generated against that exact `_withdrawal`
   */
  function pay(IPrivacyPool.Withdrawal calldata _withdrawal, ProofLib.WithdrawProof calldata _proof) external {
    if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

    Payment memory _p = abi.decode(_withdrawal.data, (Payment));
    if (_p.to == address(0) || _p.to == address(this) || _p.to == address(POOL)) revert InvalidRecipient();
    if (block.timestamp > _p.deadline) revert Expired();
    if (_p.relayFeeBPS > MAX_RELAY_FEE_BPS) revert RelayFeeTooHigh();
    if (_p.minOut < MIN_OUT || _p.minOut > MAX_OUT) revert MinOutOfRange();

    uint256 _value = _proof.withdrawnValue();
    uint256 _fee = (_value * _p.relayFeeBPS) / 10_000;
    uint256 _paid = _value - _fee;

    POOL.withdraw(_withdrawal, _proof);
    if (_fee != 0) ASSET.safeTransfer(_p.feeRecipient, _fee);

    uint256 _dai;
    if (address(ASSET) == address(DAI)) {
      // DAI pays as itself: no market, no slippage, no fee beyond the relayer's.
      if (_paid < _p.minOut) revert TooLittleReceived();
      DAI.safeTransfer(_p.to, _paid);
      _dai = _paid;
    } else {
      ASSET.forceApprove(address(V3), _paid);
      _dai = V3.exactInputSingle(
        IV3SwapRouter.ExactInputSingleParams({
          tokenIn: address(ASSET),
          tokenOut: address(DAI),
          fee: SWAP_FEE,
          recipient: _p.to,
          amountIn: _paid,
          amountOutMinimum: _p.minOut,
          sqrtPriceLimitX96: 0
        })
      );
    }
    if (_dai > MAX_OUT) revert TooMuchForOneDeposit();

    emit Paid(_p.to, _proof.existingNullifierHash(), _value, _dai, _fee);
  }
}
