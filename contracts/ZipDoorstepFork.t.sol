// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {ZipcoinFork} from './ZipcoinFork.t.sol';
import {ZipDoorstep} from 'zipcoin/ZipDoorstep.sol';

/**
 * @notice Doorstep on the same mainnet fork: a second contract spending zipped notes, no Entrypoint change.
 */
contract ZipDoorstepFork is ZipcoinFork {
  ZipDoorstep internal _door;
  address internal immutable _SEILA = makeAddr('SEILA');

  function setUp() public override {
    super.setUp();
    _door = new ZipDoorstep(IPrivacyPool(address(_zcPool)), _MIN_BURN);
  }

  function _doorWithdrawal(
    string memory _message,
    address _to,
    uint256 _gift,
    uint256 _relayFeeBPS
  ) internal view returns (IPrivacyPool.Withdrawal memory) {
    return IPrivacyPool.Withdrawal({
      processooor: address(_door),
      data: abi.encode(ZipDoorstep.Speech(_message, 'Seila', _to, _gift, _RELAYER, _relayFeeBPS))
    });
  }

  function test_doorstep_anonGiftAndBurn() public {
    Commitment memory _c = _zip(_ALICE, 1_000_000 ether, 'n1', 's1');
    _pushAspRoot();

    uint256 _amount = 200_000 ether;
    uint256 _gift = 100_000 ether;
    IPrivacyPool.Withdrawal memory _w = _doorWithdrawal('50 zipcoins have just been burned.', _SEILA, _gift, _ZC_RELAY_FEE_BPS);
    ProofLib.WithdrawProof memory _proof = _prove(_w, _c, _amount);

    uint256 _fee = (_amount * _ZC_RELAY_FEE_BPS) / 10_000;
    uint256 _burned = _amount - _fee - _gift;
    uint256 _burnBefore = _zc.balanceOf(_BURN);

    vm.expectEmit(address(_door));
    emit ZipDoorstep.Spoken(address(0), _SEILA, _proof.pubSignals[1], _burned, _gift, _fee, '50 zipcoins have just been burned.', 'Seila');

    vm.prank(_RELAYER);
    _door.speakAnon(_w, _proof);

    assertEq(_zc.balanceOf(_SEILA), _gift, 'gift at the door');
    assertEq(_zc.balanceOf(_BURN) - _burnBefore, _burned, 'burned');
    assertEq(_zc.balanceOf(_RELAYER), _fee, 'relayer paid');
    assertEq(_zc.balanceOf(address(_door)), 0, 'door keeps nothing');
    assertTrue(_zcPool.nullifierHashes(_proof.pubSignals[1]), 'nullifier spent');
  }

  function test_doorstep_relayerCannotRedirectGift() public {
    Commitment memory _c = _zip(_ALICE, 1_000_000 ether, 'n1', 's1');
    _pushAspRoot();

    IPrivacyPool.Withdrawal memory _w = _doorWithdrawal('for Seila', _SEILA, 50_000 ether, _ZC_RELAY_FEE_BPS);
    ProofLib.WithdrawProof memory _proof = _prove(_w, _c, 100_000 ether);

    IPrivacyPool.Withdrawal memory _stolen = _doorWithdrawal('for Seila', _RELAYER, 50_000 ether, _ZC_RELAY_FEE_BPS);
    vm.prank(_RELAYER);
    vm.expectRevert(IPrivacyPool.ContextMismatch.selector);
    _door.speakAnon(_stolen, _proof);

    IPrivacyPool.Withdrawal memory _bigger = _doorWithdrawal('for Seila', _SEILA, 90_000 ether, _ZC_RELAY_FEE_BPS);
    vm.prank(_RELAYER);
    vm.expectRevert(IPrivacyPool.ContextMismatch.selector);
    _door.speakAnon(_bigger, _proof);
  }

  function test_doorstep_anonGiftNeedsTenPercentBurn() public {
    Commitment memory _c = _zip(_ALICE, 1_000_000 ether, 'n1', 's1');
    _pushAspRoot();

    // 100k withdrawn, 1% fee, 95k gift -> 4k burn < 10% of gift
    IPrivacyPool.Withdrawal memory _w = _doorWithdrawal('too generous', _SEILA, 95_000 ether, _ZC_RELAY_FEE_BPS);
    ProofLib.WithdrawProof memory _proof = _prove(_w, _c, 100_000 ether);
    vm.prank(_RELAYER);
    vm.expectRevert(ZipDoorstep.BurnTooSmall.selector);
    _door.speakAnon(_w, _proof);
  }

  function test_doorstep_public() public {
    uint256 _burnBefore = _zc.balanceOf(_BURN);
    vm.startPrank(_ALICE);
    _zc.approve(address(_door), 110_000 ether);
    vm.expectEmit(address(_door));
    emit ZipDoorstep.Spoken(_ALICE, _SEILA, 0, 10_000 ether, 100_000 ether, 0, 'at your door', 'Seila');
    _door.speak(_SEILA, 10_000 ether, 100_000 ether, 'at your door', 'Seila');
    vm.stopPrank();
    assertEq(_zc.balanceOf(_SEILA), 100_000 ether, 'gift');
    assertEq(_zc.balanceOf(_BURN) - _burnBefore, 10_000 ether, 'burned');
  }

  function test_doorstep_public_limits() public {
    vm.startPrank(_ALICE);
    _zc.approve(address(_door), type(uint256).max);

    vm.expectRevert(ZipDoorstep.BurnTooSmall.selector);
    _door.speak(_SEILA, 9_999 ether, 100_000 ether, 'cheap', '');

    vm.expectRevert(ZipDoorstep.GiftNeedsDoor.selector);
    _door.speak(address(0), 10_000 ether, 1 ether, 'gift to nobody', '');

    vm.expectRevert(ZipDoorstep.InvalidDoor.selector);
    _door.speak(address(_zcPool), 10_000 ether, 0, 'pool is not a door', '');

    vm.expectRevert(ZipDoorstep.BurnTooSmall.selector);
    _door.speak(address(0), _MIN_BURN - 1, 0, 'hi', '');

    // no door, no gift: a plain broadcast still works
    _door.speak(address(0), _MIN_BURN, 0, 'just talking', '');
    vm.stopPrank();
  }
}
