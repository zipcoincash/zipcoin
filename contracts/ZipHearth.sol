// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {PoolKey} from './ZipTeller.sol';

interface ILaunchRouterBuy {
  function buyWethPairWithEth(PoolKey calldata key, uint256 minOut, bytes calldata hookData) external payable returns (uint256 amountOut);
}

interface IZipDoorstep {
  function speak(address _to, uint256 _burn, uint256 _gift, string calldata _message, string calldata _target) external;
}

/**
 * @title ZipHearth
 * @notice Speak, or knock at a door, from a zipped ETH note in 0xbow's Privacy Pool.
 * @dev A processooor for 0xbow's canonical ETH pool. The ETH leaves their pool; an optional gift goes to the door in
 *      ETH; the rest buys zipcoins on their own pool (paying the sales tax like any trade) and burns them with the
 *      message through ZipDoorstep, so the word lands in the same book as every other. The book shows this contract
 *      as the speaker, which is to say: someone, out of Ethereum's largest anonymity set. The proof binds every field
 *      of the word, so a relayer can neither reword nor redirect it. No owner, holds nothing between calls.
 */
contract ZipHearth {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  /**
   * @notice What a word carries, ABI-encoded in `withdrawal.data`
   * @param message The broadcast text
   * @param target Who it is for, free text
   * @param to The door (address(0) for a message with no door)
   * @param gift ETH left at the door
   * @param minZcOut The least zipcoins the burn may buy (slippage guard)
   * @param deadline Last timestamp at which the word may execute
   * @param feeRecipient Who gets the relay fee, in ETH
   * @param relayFeeBPS Relay fee in basis points of the withdrawn value
   */
  struct Word {
    string message;
    string target;
    address to;
    uint256 gift;
    uint256 minZcOut;
    uint256 deadline;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  uint256 public constant MAX_RELAY_FEE_BPS = 1000;
  /// @notice A gift needs a burn of at least a tenth of it, measured in ETH, as at the ZC doorstep
  uint256 public constant MIN_BURN_OF_GIFT_BPS = 1000;

  IPrivacyPool public immutable POOL;
  IERC20 public immutable ZC;
  address public immutable WETH;
  ILaunchRouterBuy public immutable ROUTER;
  IZipDoorstep public immutable DOORSTEP;
  address public immutable HOOK;
  int24 public immutable TICK_SPACING;

  /**
   * @notice A word was spoken from an ETH note
   * @param to The door, or address(0)
   * @param nullifierHash The spent nullifier
   * @param ethIn Withdrawn value, in ETH
   * @param zcBurned Zipcoins bought and burned
   * @param gift ETH left at the door
   * @param fee Relay fee paid, in ETH
   */
  event Hearth(address indexed to, uint256 nullifierHash, uint256 ethIn, uint256 zcBurned, uint256 gift, uint256 fee);

  error InvalidProcessooor();
  error GiftNeedsDoor();
  error InvalidDoor();
  error Expired();
  error RelayFeeTooHigh();
  error BurnTooSmall();
  error TransferFailed();
  error ZeroAddress();

  constructor(IPrivacyPool _pool, IERC20 _zc, address _weth, ILaunchRouterBuy _router, IZipDoorstep _doorstep, address _hook, int24 _tickSpacing) {
    if (
      address(_pool) == address(0) || address(_zc) == address(0) || _weth == address(0) || address(_router) == address(0)
        || address(_doorstep) == address(0) || _hook == address(0)
    ) revert ZeroAddress();
    POOL = _pool;
    ZC = _zc;
    WETH = _weth;
    ROUTER = _router;
    DOORSTEP = _doorstep;
    HOOK = _hook;
    TICK_SPACING = _tickSpacing;
  }

  /// @dev The pool pays the processooor with a plain call; the router refunds dust the same way.
  receive() external payable {
    if (msg.sender != address(POOL) && msg.sender != address(ROUTER)) revert InvalidProcessooor();
  }

  /**
   * @notice Burn (and gift) from a zipped ETH note without revealing who you are
   * @param _withdrawal Withdrawal with `processooor == address(this)` and `data == abi.encode(Word)`
   * @param _proof Withdrawal proof generated against that exact `_withdrawal`
   */
  function speak(IPrivacyPool.Withdrawal calldata _withdrawal, ProofLib.WithdrawProof calldata _proof) external {
    if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

    Word memory _w = abi.decode(_withdrawal.data, (Word));
    if (block.timestamp > _w.deadline) revert Expired();
    if (_w.relayFeeBPS > MAX_RELAY_FEE_BPS) revert RelayFeeTooHigh();
    if (_w.gift != 0 && _w.to == address(0)) revert GiftNeedsDoor();
    if (_w.to == address(this) || _w.to == address(POOL) || _w.to == address(DOORSTEP)) revert InvalidDoor();

    uint256 _value = _proof.withdrawnValue();
    uint256 _fee = (_value * _w.relayFeeBPS) / 10_000;
    if (_value < _fee + _w.gift) revert BurnTooSmall();
    uint256 _burnEth = _value - _fee - _w.gift;
    if (_burnEth == 0 || _burnEth * 10_000 < _w.gift * MIN_BURN_OF_GIFT_BPS) revert BurnTooSmall();

    POOL.withdraw(_withdrawal, _proof);

    if (_fee != 0) _send(_w.feeRecipient, _fee);
    if (_w.gift != 0) _send(_w.to, _w.gift);

    // ETH -> ZC on the token's own pool, then burned with the word through the doorstep (which enforces its minimum).
    uint256 _zc = ROUTER.buyWethPairWithEth{value: _burnEth}(_poolKey(), _w.minZcOut, '');
    ZC.forceApprove(address(DOORSTEP), _zc);
    DOORSTEP.speak(_w.to, _zc, 0, _w.message, _w.target);

    emit Hearth(_w.to, _proof.existingNullifierHash(), _value, _zc, _w.gift, _fee);
  }

  function _send(address _to, uint256 _value) internal {
    (bool _ok,) = _to.call{value: _value}('');
    if (!_ok) revert TransferFailed();
  }

  function _poolKey() internal view returns (PoolKey memory) {
    bool _zcFirst = address(ZC) < WETH;
    return PoolKey({currency0: _zcFirst ? address(ZC) : WETH, currency1: _zcFirst ? WETH : address(ZC), fee: 0, tickSpacing: TICK_SPACING, hooks: HOOK});
  }
}
