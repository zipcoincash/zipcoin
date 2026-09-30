// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {IV3SwapRouter} from './ZipTeller.sol';

/**
 * @title ZipTellerEth
 * @notice Pay anyone private dollars from a zipped ETH note in 0xbow's Privacy Pool.
 * @dev A processooor for 0xbow's canonical ETH pool: the pool only requires `msg.sender == processooor`, and the
 *      proof's context binds the recipient, the DAI minimum and a deadline. The ETH leaves their pool, is sold for
 *      DAI on Uniswap v3, and the DAI goes straight to the recipient: for a zk.money deposit address, a private
 *      balance on Aztec. Ethereum's largest privacy pool on one side, Aztec on the other, one proof in between.
 *      If any leg fails the whole call reverts and the note is not spent. No owner, holds no funds between calls.
 */
contract ZipTellerEth {
  using ProofLib for ProofLib.WithdrawProof;

  /**
   * @notice What a payment carries, ABI-encoded in `withdrawal.data`
   * @param to The recipient of the DAI (for zk.money, the tag's fresh deposit address)
   * @param minOut The least DAI the recipient may receive, or the call reverts (slippage guard)
   * @param deadline Last timestamp at which the payment may execute
   * @param feeRecipient Who gets the relay fee, in ETH
   * @param relayFeeBPS Relay fee in basis points of the withdrawn value
   */
  struct Payment {
    address to;
    uint256 minOut;
    uint256 deadline;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  /// @notice ETH notes can be small and mainnet gas is not; the relayer may take up to this much to cover it
  uint256 public constant MAX_RELAY_FEE_BPS = 1000;
  /// @notice zk.money credits deposits up to this much DAI per payment; larger ones would sit uncredited
  uint256 public constant MAX_OUT = 2_500 ether;
  /// @notice Below this the recipient's deposit fee eats the payment
  uint256 public constant MIN_OUT = 1 ether;
  uint24 public constant DAI_POOL_FEE = 500;

  IPrivacyPool public immutable POOL;
  address public immutable WETH;
  IERC20 public immutable DAI;
  IV3SwapRouter public immutable V3;

  event Paid(address indexed to, uint256 nullifierHash, uint256 ethIn, uint256 daiOut, uint256 fee);

  error InvalidProcessooor();
  error InvalidRecipient();
  error Expired();
  error RelayFeeTooHigh();
  error MinOutOfRange();
  error TooMuchForOneDeposit();
  error FeeTransferFailed();
  error ZeroAddress();

  constructor(IPrivacyPool _pool, address _weth, IERC20 _dai, IV3SwapRouter _v3) {
    if (address(_pool) == address(0) || _weth == address(0) || address(_dai) == address(0) || address(_v3) == address(0)) {
      revert ZeroAddress();
    }
    POOL = _pool;
    WETH = _weth;
    DAI = _dai;
    V3 = _v3;
  }

  /// @dev The pool pays the processooor with a plain call; nothing else may send ETH here.
  receive() external payable {
    if (msg.sender != address(POOL)) revert InvalidProcessooor();
  }

  /**
   * @notice Pay a recipient in DAI from a zipped ETH note, without revealing who you are
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
    uint256 _sold = _value - _fee;

    POOL.withdraw(_withdrawal, _proof);

    if (_fee != 0) {
      (bool _ok,) = _p.feeRecipient.call{value: _fee}('');
      if (!_ok) revert FeeTransferFailed();
    }

    // ETH -> DAI on Uniswap v3; the router wraps the ETH itself and pays the recipient directly.
    uint256 _dai = V3.exactInputSingle{value: _sold}(
      IV3SwapRouter.ExactInputSingleParams({
        tokenIn: WETH,
        tokenOut: address(DAI),
        fee: DAI_POOL_FEE,
        recipient: _p.to,
        amountIn: _sold,
        amountOutMinimum: _p.minOut,
        sqrtPriceLimitX96: 0
      })
    );
    if (_dai > MAX_OUT) revert TooMuchForOneDeposit();

    emit Paid(_p.to, _proof.existingNullifierHash(), _value, _dai, _fee);
  }
}
