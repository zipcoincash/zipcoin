// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

/// @dev Stockereum's LaunchRouter, the Uniswap v4 pool key it expects.
struct PoolKey {
  address currency0;
  address currency1;
  uint24 fee;
  int24 tickSpacing;
  address hooks;
}

interface ILaunchRouter {
  /// @notice Sells `token` into the pool's quote (WETH here); pulls `amountIn` from msg.sender, pays msg.sender.
  function sell(
    PoolKey calldata key,
    address token,
    address quote,
    uint256 amountIn,
    uint256 minOut,
    bytes calldata hookData
  ) external returns (uint256 amountOut);
}

/// @dev Uniswap SwapRouter02.
interface IV3SwapRouter {
  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/**
 * @title ZipTeller
 * @notice Pay anyone private dollars from a zipped note. Snowmoon ch. 6: the bill is settled in zipcoins and the
 *         restaurant never learns who paid.
 * @dev Third contract that spends zipped notes (the pool only requires `msg.sender == processooor`). The proof locks
 *      in the recipient, the minimum DAI out and a deadline through `withdrawal.data`, bound to the proof by the
 *      `context` signal, so a relayer can neither redirect the payment nor shave the amount. ZC leaves the pool, is
 *      sold for WETH on its own Uniswap v4 pool through Stockereum's router, the WETH is sold for DAI on Uniswap v3,
 *      and the DAI goes straight to the recipient: for a zk.money deposit address, that is a private balance on Aztec.
 *      If any leg fails the whole call reverts and the note is not spent. Payments are capped at zk.money's per-deposit
 *      limit so nothing is ever left stranded. No owner, no admin, holds no funds between calls.
 */
contract ZipTeller {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  /**
   * @notice What a payment carries, ABI-encoded in `withdrawal.data`
   * @param to The recipient of the DAI (for zk.money, the tag's fresh deposit address)
   * @param minOut The least DAI the recipient may receive, or the call reverts (slippage guard)
   * @param deadline Last timestamp at which the payment may execute
   * @param feeRecipient Who gets the relay fee, in ZC
   * @param relayFeeBPS Relay fee in basis points of the withdrawn value
   */
  struct Payment {
    address to;
    uint256 minOut;
    uint256 deadline;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  uint256 public constant MAX_RELAY_FEE_BPS = 500;
  /// @notice zk.money credits deposits up to this much DAI per payment; larger ones would sit uncredited
  uint256 public constant MAX_OUT = 2_500 ether;
  /// @notice Below this the recipient's deposit fee eats the payment
  uint256 public constant MIN_OUT = 1 ether;
  uint24 public constant DAI_POOL_FEE = 500;

  IPrivacyPool public immutable POOL;
  IERC20 public immutable ZC;
  IERC20 public immutable WETH;
  IERC20 public immutable DAI;
  ILaunchRouter public immutable ROUTER;
  IV3SwapRouter public immutable V3;
  address public immutable HOOK;
  int24 public immutable TICK_SPACING;

  /**
   * @notice A note was spent and its value delivered as DAI
   * @param to The recipient
   * @param nullifierHash The spent nullifier
   * @param zcIn Withdrawn value, in ZC
   * @param daiOut DAI delivered to `to`
   * @param fee Relay fee paid, in ZC
   */
  event Paid(address indexed to, uint256 nullifierHash, uint256 zcIn, uint256 daiOut, uint256 fee);

  error InvalidProcessooor();
  error InvalidRecipient();
  error Expired();
  error RelayFeeTooHigh();
  error MinOutOfRange();
  error TooMuchForOneDeposit();
  error ZeroAddress();

  constructor(
    IPrivacyPool _pool,
    IERC20 _weth,
    IERC20 _dai,
    ILaunchRouter _router,
    IV3SwapRouter _v3,
    address _hook,
    int24 _tickSpacing
  ) {
    if (
      address(_pool) == address(0) || address(_weth) == address(0) || address(_dai) == address(0)
        || address(_router) == address(0) || address(_v3) == address(0) || _hook == address(0)
    ) revert ZeroAddress();
    POOL = _pool;
    ZC = IERC20(_pool.ASSET());
    WETH = _weth;
    DAI = _dai;
    ROUTER = _router;
    V3 = _v3;
    HOOK = _hook;
    TICK_SPACING = _tickSpacing;
  }

  /**
   * @notice Pay a recipient in DAI from a zipped note, without revealing who you are
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
    if (_fee != 0) ZC.safeTransfer(_p.feeRecipient, _fee);

    // ZC -> WETH on the token's own pool. The DAI leg enforces the minimum, so this leg takes what the pool gives.
    ZC.forceApprove(address(ROUTER), _sold);
    uint256 _weth = ROUTER.sell(_poolKey(), address(ZC), address(WETH), _sold, 0, '');

    // WETH -> DAI, delivered straight to the recipient.
    WETH.forceApprove(address(V3), _weth);
    uint256 _dai = V3.exactInputSingle(
      IV3SwapRouter.ExactInputSingleParams({
        tokenIn: address(WETH),
        tokenOut: address(DAI),
        fee: DAI_POOL_FEE,
        recipient: _p.to,
        amountIn: _weth,
        amountOutMinimum: _p.minOut,
        sqrtPriceLimitX96: 0
      })
    );
    if (_dai > MAX_OUT) revert TooMuchForOneDeposit();

    emit Paid(_p.to, _proof.existingNullifierHash(), _value, _dai, _fee);
  }

  /// @notice The ZC/WETH pool key as Stockereum's factory built it: fee 0 (the hook charges), fixed tick spacing.
  function _poolKey() internal view returns (PoolKey memory) {
    bool _zcFirst = address(ZC) < address(WETH);
    return PoolKey({
      currency0: _zcFirst ? address(ZC) : address(WETH),
      currency1: _zcFirst ? address(WETH) : address(ZC),
      fee: 0,
      tickSpacing: TICK_SPACING,
      hooks: HOOK
    });
  }
}
