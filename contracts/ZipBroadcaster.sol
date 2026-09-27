// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

/**
 * @title ZipBroadcaster
 * @notice Burn zipcoins to make a message worth reading.
 * @dev `speakAnon` spends a Privacy Pool note: this contract is the withdrawal `processooor`, the message lives in
 *      `withdrawal.data` and is bound to the proof through the `context` signal, so nobody (relayer included) can
 *      alter the message, the fee or the fee recipient. `speak` is the public version, straight from a wallet.
 *      No owner, no admin, holds no funds between calls.
 */
contract ZipBroadcaster {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  /**
   * @notice Payload carried in `Withdrawal.data` for anonymous speech
   * @param message The broadcast text
   * @param target Who the message is for, free text (e.g. "someone who ate at Beautiful Plants, 18, successful")
   * @param feeRecipient The relayer paid for submitting the transaction
   * @param relayFeeBPS The relayer fee, in basis points of the withdrawn value
   */
  struct Speech {
    string message;
    string target;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  address public constant BURN = 0x000000000000000000000000000000000000dEaD;
  uint256 public constant MAX_MESSAGE_BYTES = 280;
  uint256 public constant MAX_TARGET_BYTES = 120;
  uint256 public constant MAX_RELAY_FEE_BPS = 500;

  IPrivacyPool public immutable POOL;
  IERC20 public immutable ZC;
  uint256 public immutable MIN_BURN;

  /**
   * @notice Emitted for every broadcast
   * @param speaker The wallet that burned, or address(0) when anonymous
   * @param nullifierHash The spent note nullifier for anonymous speech, 0 for public speech
   * @param burned The amount sent to the burn address
   * @param fee The relayer fee paid out of the withdrawn value
   * @param message The broadcast text
   * @param target Who the message is for
   */
  event Spoken(
    address indexed speaker, uint256 indexed nullifierHash, uint256 burned, uint256 fee, string message, string target
  );

  error EmptyMessage();
  error MessageTooLong();
  error TargetTooLong();
  error BurnTooSmall();
  error RelayFeeTooHigh();
  error InvalidProcessooor();
  error ZeroMinBurn();

  constructor(IPrivacyPool _pool, uint256 _minBurn) {
    if (_minBurn == 0) revert ZeroMinBurn();
    POOL = _pool;
    ZC = IERC20(_pool.ASSET());
    MIN_BURN = _minBurn;
  }

  /**
   * @notice Burn from a zipped note and broadcast without revealing who you are
   * @param _withdrawal Withdrawal with `processooor == address(this)` and `data == abi.encode(Speech)`
   * @param _proof Withdrawal proof generated against that exact `_withdrawal`
   */
  function speakAnon(IPrivacyPool.Withdrawal calldata _withdrawal, ProofLib.WithdrawProof calldata _proof) external {
    if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

    Speech memory _speech = abi.decode(_withdrawal.data, (Speech));
    _validate(_speech.message, _speech.target);
    if (_speech.relayFeeBPS > MAX_RELAY_FEE_BPS) revert RelayFeeTooHigh();

    uint256 _value = _proof.withdrawnValue();
    uint256 _fee = (_value * _speech.relayFeeBPS) / 10_000;
    uint256 _burned = _value - _fee;
    if (_burned < MIN_BURN) revert BurnTooSmall();

    POOL.withdraw(_withdrawal, _proof);

    if (_fee != 0) ZC.safeTransfer(_speech.feeRecipient, _fee);
    ZC.safeTransfer(BURN, _burned);

    emit Spoken(address(0), _proof.existingNullifierHash(), _burned, _fee, _speech.message, _speech.target);
  }

  /**
   * @notice Burn from your wallet and broadcast publicly
   * @param _amount Amount to burn (requires approval)
   * @param _message The broadcast text
   * @param _target Who the message is for
   */
  function speak(uint256 _amount, string calldata _message, string calldata _target) external {
    _validate(_message, _target);
    if (_amount < MIN_BURN) revert BurnTooSmall();

    ZC.safeTransferFrom(msg.sender, BURN, _amount);

    emit Spoken(msg.sender, 0, _amount, 0, _message, _target);
  }

  function _validate(string memory _message, string memory _target) internal pure {
    uint256 _len = bytes(_message).length;
    if (_len == 0) revert EmptyMessage();
    if (_len > MAX_MESSAGE_BYTES) revert MessageTooLong();
    if (bytes(_target).length > MAX_TARGET_BYTES) revert TargetTooLong();
  }
}
