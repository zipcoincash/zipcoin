// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {ILaunchRouter, PoolKey} from './ZipTeller.sol';

interface IWETH {
  function withdraw(uint256 wad) external;
}

/**
 * @title ZipChanger
 * @notice Unzip as ETH: spend a zipped ZC note and deliver plain ETH to any address, without revealing who you are.
 * @dev A processooor for the zipcoin pool (the pool only requires `msg.sender == processooor`). The proof's context
 *      binds the recipient, the minimum ETH out, a deadline and the relay fee, so a relayer can neither redirect the
 *      ETH nor shave the amount. The ZC is sold for WETH on its own Uniswap v4 pool through Stockereum's router (paying
 *      the sales tax like any trade), the WETH is unwrapped, and the ETH goes straight to the recipient. One use: funding
 *      a zkAPI client's address so it can buy private AI credits from a fresh, unlinked address. If any leg fails the
 *      whole call reverts and the note is not spent. No owner, no admin, holds no funds between calls.
 */
contract ZipChanger {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  struct Exchange {
    address to;
    uint256 minOut;
    uint256 deadline;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  uint256 public constant MAX_RELAY_FEE_BPS = 500;

  IPrivacyPool public immutable POOL;
  IERC20 public immutable ZC;
  IWETH public immutable WETH;
  ILaunchRouter public immutable ROUTER;
  address public immutable HOOK;
  int24 public immutable TICK_SPACING;

  /**
   * @notice A note was spent and its value delivered as ETH
   * @param to The recipient
   * @param nullifierHash The spent nullifier
   * @param zcIn Withdrawn value, in ZC
   * @param ethOut ETH delivered to `to`
   * @param fee Relay fee paid, in ZC
   */
  event Changed(address indexed to, uint256 nullifierHash, uint256 zcIn, uint256 ethOut, uint256 fee);

  error InvalidProcessooor();
  error InvalidRecipient();
  error Expired();
  error RelayFeeTooHigh();
  error ZeroMinOut();
  error EthTransferFailed();
  error NotWeth();
  error ZeroAddress();

  constructor(IPrivacyPool _pool, IWETH _weth, ILaunchRouter _router, address _hook, int24 _tickSpacing) {
    if (address(_pool) == address(0) || address(_weth) == address(0) || address(_router) == address(0) || _hook == address(0))
    {
      revert ZeroAddress();
    }
    POOL = _pool;
    ZC = IERC20(_pool.ASSET());
    WETH = _weth;
    ROUTER = _router;
    HOOK = _hook;
    TICK_SPACING = _tickSpacing;
  }

  /// @dev Only WETH may send ETH here, and only while unwrapping inside `change`.
  receive() external payable {
    if (msg.sender != address(WETH)) revert NotWeth();
  }

  /**
   * @notice Deliver a zipped note as ETH to a recipient
   * @param _withdrawal Withdrawal with `processooor == address(this)` and `data == abi.encode(Exchange)`
   * @param _proof Withdrawal proof generated against that exact `_withdrawal`
   */
  function change(IPrivacyPool.Withdrawal calldata _withdrawal, ProofLib.WithdrawProof calldata _proof) external {
    if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

    Exchange memory _x = abi.decode(_withdrawal.data, (Exchange));
    if (_x.to == address(0) || _x.to == address(this) || _x.to == address(POOL)) revert InvalidRecipient();
    if (block.timestamp > _x.deadline) revert Expired();
    if (_x.relayFeeBPS > MAX_RELAY_FEE_BPS) revert RelayFeeTooHigh();
    if (_x.minOut == 0) revert ZeroMinOut();

    uint256 _value = _proof.withdrawnValue();
    uint256 _fee = (_value * _x.relayFeeBPS) / 10_000;
    uint256 _sold = _value - _fee;

    POOL.withdraw(_withdrawal, _proof);
    if (_fee != 0) ZC.safeTransfer(_x.feeRecipient, _fee);

    // ZC -> WETH on the token's own pool, with the recipient's minimum enforced by the router.
    ZC.forceApprove(address(ROUTER), _sold);
    uint256 _weth = ROUTER.sell(_poolKey(), address(ZC), address(IERC20(address(WETH))), _sold, _x.minOut, '');

    // WETH -> ETH -> recipient.
    WETH.withdraw(_weth);
    (bool _ok,) = payable(_x.to).call{value: _weth}('');
    if (!_ok) revert EthTransferFailed();

    emit Changed(_x.to, _proof.existingNullifierHash(), _value, _weth, _fee);
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
