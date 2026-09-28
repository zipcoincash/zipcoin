// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

/**
 * @title ZipDoorstep
 * @notice Burn zipcoins at someone's door. Snowmoon ch. 20: "he had no way to prove that he was someone to talk to,
 *         except perhaps for burning a hundred zipcoins at his doorstep."
 * @dev Second contract that spends zipped notes (the pool only requires `msg.sender == processooor`). A speech burns
 *      zipcoins, optionally leaves a gift at the door, and carries a message. `speakAnon` spends a Privacy Pool note:
 *      the door, the gift, the message and the relay fee live in `withdrawal.data`, bound to the proof through the
 *      `context` signal, so nobody (relayer included) can redirect the gift or rewrite the message. The recipient
 *      gets zipcoins from this contract and nothing links them to the deposit that paid. `speak` is the public
 *      version, straight from a wallet. Every gift must be accompanied by a burn of at least a tenth of it, so a
 *      doorstep never becomes a free private transfer. No owner, no admin, holds no funds between calls.
 */
contract ZipDoorstep {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  /**
   * @notice Payload carried in `Withdrawal.data` for anonymous speech
   * @param message The broadcast text
   * @param target Who the message is for, free text (kept from v1; the door itself is `to`)
   * @param to The door: who receives the gift and whose page collects the burn (address(0) = no door)
   * @param gift Zipcoins left at the door, paid out of the withdrawn value
   * @param feeRecipient The relayer paid for submitting the transaction
   * @param relayFeeBPS The relayer fee, in basis points of the withdrawn value
   */
  struct Speech {
    string message;
    string target;
    address to;
    uint256 gift;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  address public constant BURN = 0x000000000000000000000000000000000000dEaD;
  uint256 public constant MAX_MESSAGE_BYTES = 280;
  uint256 public constant MAX_TARGET_BYTES = 120;
  uint256 public constant MAX_RELAY_FEE_BPS = 500;
  /// @notice Burn at least this fraction of any gift (basis points): a gift is a costly signal, not a transfer
  uint256 public constant MIN_BURN_OF_GIFT_BPS = 1000;

  IPrivacyPool public immutable POOL;
  IERC20 public immutable ZC;
  uint256 public immutable MIN_BURN;

  /**
   * @notice Emitted for every doorstep speech
   * @param speaker The wallet that burned, or address(0) when anonymous
   * @param to The door (address(0) when the message has no door)
   * @param nullifierHash The spent note nullifier for anonymous speech, 0 for public speech
   * @param burned The amount sent to the burn address
   * @param gift The amount left at the door
   * @param fee The relayer fee paid out of the withdrawn value
   * @param message The broadcast text
   * @param target Who the message is for, free text
   */
  event Spoken(
    address indexed speaker,
    address indexed to,
    uint256 indexed nullifierHash,
    uint256 burned,
    uint256 gift,
    uint256 fee,
    string message,
    string target
  );

  error EmptyMessage();
  error MessageTooLong();
  error TargetTooLong();
  error BurnTooSmall();
  error GiftNeedsDoor();
  error InvalidDoor();
  error RelayFeeTooHigh();
  error InvalidProcessooor();
  error ValueTooSmall();
  error ZeroMinBurn();

  constructor(IPrivacyPool _pool, uint256 _minBurn) {
    if (_minBurn == 0) revert ZeroMinBurn();
    POOL = _pool;
    ZC = IERC20(_pool.ASSET());
    MIN_BURN = _minBurn;
  }

  /**
   * @notice Burn (and gift) from a zipped note without revealing who you are
   * @param _withdrawal Withdrawal with `processooor == address(this)` and `data == abi.encode(Speech)`
   * @param _proof Withdrawal proof generated against that exact `_withdrawal`
   */
  function speakAnon(IPrivacyPool.Withdrawal calldata _withdrawal, ProofLib.WithdrawProof calldata _proof) external {
    if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

    Speech memory _s = abi.decode(_withdrawal.data, (Speech));
    _validate(_s.message, _s.target, _s.to, _s.gift);
    if (_s.relayFeeBPS > MAX_RELAY_FEE_BPS) revert RelayFeeTooHigh();

    uint256 _value = _proof.withdrawnValue();
    uint256 _fee = (_value * _s.relayFeeBPS) / 10_000;
    if (_value < _fee + _s.gift) revert ValueTooSmall();
    uint256 _burned = _value - _fee - _s.gift;
    _checkBurn(_burned, _s.gift);

    POOL.withdraw(_withdrawal, _proof);

    if (_fee != 0) ZC.safeTransfer(_s.feeRecipient, _fee);
    if (_s.gift != 0) ZC.safeTransfer(_s.to, _s.gift);
    ZC.safeTransfer(BURN, _burned);

    emit Spoken(address(0), _s.to, _proof.existingNullifierHash(), _burned, _s.gift, _fee, _s.message, _s.target);
  }

  /**
   * @notice Burn (and gift) from your wallet, publicly
   * @param _to The door (address(0) for a message with no door)
   * @param _burn Amount to burn (requires approval of `_burn + _gift`)
   * @param _gift Amount left at the door
   * @param _message The broadcast text
   * @param _target Who the message is for, free text
   */
  function speak(
    address _to,
    uint256 _burn,
    uint256 _gift,
    string calldata _message,
    string calldata _target
  ) external {
    _validate(_message, _target, _to, _gift);
    _checkBurn(_burn, _gift);

    ZC.safeTransferFrom(msg.sender, BURN, _burn);
    if (_gift != 0) ZC.safeTransferFrom(msg.sender, _to, _gift);

    emit Spoken(msg.sender, _to, 0, _burn, _gift, 0, _message, _target);
  }

  function _checkBurn(uint256 _burn, uint256 _gift) internal view {
    if (_burn < MIN_BURN) revert BurnTooSmall();
    if (_burn * 10_000 < _gift * MIN_BURN_OF_GIFT_BPS) revert BurnTooSmall();
  }

  function _validate(string memory _message, string memory _target, address _to, uint256 _gift) internal view {
    uint256 _len = bytes(_message).length;
    if (_len == 0) revert EmptyMessage();
    if (_len > MAX_MESSAGE_BYTES) revert MessageTooLong();
    if (bytes(_target).length > MAX_TARGET_BYTES) revert TargetTooLong();
    if (_gift != 0 && _to == address(0)) revert GiftNeedsDoor();
    if (_to == address(this) || _to == address(POOL) || _to == BURN) revert InvalidDoor();
  }
}
