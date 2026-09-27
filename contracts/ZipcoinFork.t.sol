// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IntegrationBase} from '../integration/IntegrationBase.sol';

import {IERC20} from '@oz/interfaces/IERC20.sol';

import {PrivacyPoolComplex} from 'contracts/implementations/PrivacyPoolComplex.sol';
import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {InternalLeanIMT, LeanIMTData} from 'lean-imt/InternalLeanIMT.sol';

import {IEntrypoint} from 'interfaces/IEntrypoint.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {Constants} from 'test/helper/Constants.sol';

import {ZipBroadcaster} from 'zipcoin/ZipBroadcaster.sol';

interface ISendItFactory {
  function launchFee() external view returns (uint256);
  function launchWith(
    string calldata name,
    string calldata symbol,
    string calldata metadataURI,
    address quote,
    uint256 quoteIn,
    bool holderFees,
    int24 startTick
  ) external payable returns (address token, uint256 tokenId);
}

/**
 * @notice Mainnet-fork test of the full zipcoin stack:
 *         real sender.family launch -> Privacy Pool on the launched token wired to the MAINNET ceremony verifiers
 *         -> zip -> anonymous burn-to-speak / public speak / relayed unzip, with real Groth16 proofs.
 */
contract ZipcoinFork is IntegrationBase {
  using InternalLeanIMT for LeanIMTData;

  ISendItFactory internal constant _SENDER = ISendItFactory(0x8D37c2981bdF809567092fd458B6bf3e97ee860c);
  address internal constant _MAINNET_WITHDRAWAL_VERIFIER = 0x022891F938Ae7fDC8Ab9Ead0FBf50aBA8C897D6d;
  address internal constant _MAINNET_RAGEQUIT_VERIFIER = 0xa45ACa8604a73D80C551fAad6355A5c3A5565eC6;
  address internal constant _BURN = 0x000000000000000000000000000000000000dEaD;
  int24 internal constant _START_TICK_DEFAULT = type(int24).min;

  uint256 internal constant _ZC_VETTING_FEE_BPS = 50;
  uint256 internal constant _ZC_MAX_RELAY_FEE_BPS = 300;
  uint256 internal constant _ZC_RELAY_FEE_BPS = 100;
  uint256 internal constant _MIN_BURN = 1000 ether;

  address internal immutable _DEV = makeAddr('DEV');

  IERC20 internal _zc;
  PrivacyPoolComplex internal _zcPool;
  ZipBroadcaster internal _broadcaster;

  function setUp() public override {
    super.setUp();

    // Launch $ZC on sender.family exactly like production: ETH pair, holder fees off, 0.1 ETH disclosed dev buy
    vm.deal(_DEV, 1 ether);
    uint256 _fee = _SENDER.launchFee();
    vm.prank(_DEV);
    (address _token,) =
      _SENDER.launchWith{value: _fee + 0.1 ether}('zipcoin', 'ZC', 'ipfs://zipcoin', address(0), 0, false, _START_TICK_DEFAULT);
    _zc = IERC20(_token);

    // Leave the 3-block launch guard behind
    vm.roll(block.number + 5);

    // Privacy Pool for ZC, wired to the verifiers already live on mainnet (0xbow ceremony keys)
    _zcPool = new PrivacyPoolComplex(
      address(_entrypoint), _MAINNET_WITHDRAWAL_VERIFIER, _MAINNET_RAGEQUIT_VERIFIER, address(_zc)
    );
    vm.prank(_OWNER);
    _entrypoint.registerPool(
      _zc, IPrivacyPool(address(_zcPool)), 1 ether, _ZC_VETTING_FEE_BPS, _ZC_MAX_RELAY_FEE_BPS
    );

    _broadcaster = new ZipBroadcaster(IPrivacyPool(address(_zcPool)), _MIN_BURN);

    // Fund Alice from the dev bag (plain transfer, post-guard)
    vm.prank(_DEV);
    _zc.transfer(_ALICE, 5_000_000 ether);
  }

  /*///////////////////////////////////////////////////////////////
                              HELPERS
  //////////////////////////////////////////////////////////////*/

  function _zip(
    address _depositor,
    uint256 _amount,
    string memory _nullifier,
    string memory _secret
  ) internal returns (Commitment memory _c) {
    _c.asset = _zc;
    _c.nullifier = _genSecretBySeed(_nullifier);
    _c.secret = _genSecretBySeed(_secret);
    _c.label = uint256(keccak256(abi.encodePacked(_zcPool.SCOPE(), _zcPool.nonce() + 1))) % Constants.SNARK_SCALAR_FIELD;
    _c.value = _deductFee(_amount, _ZC_VETTING_FEE_BPS);
    _c.precommitment = _hashPrecommitment(_c.nullifier, _c.secret);
    _c.hash = _hashCommitment(_c.value, _c.label, _c.precommitment);

    _insertIntoShadowMerkleTree(_c.hash);
    _insertIntoShadowASPMerkleTree(_c.label);

    vm.startPrank(_depositor);
    _zc.approve(address(_entrypoint), _amount);
    _entrypoint.deposit(_zc, _amount, _c.precommitment);
    vm.stopPrank();

    assertEq(_zcPool.depositors(_c.label), _depositor, 'depositor');
  }

  function _pushAspRoot() internal {
    vm.prank(_POSTMAN);
    _entrypoint.updateRoot(_shadowASPMerkleTree._root(), 'ipfs_cid_ipfs_cid_ipfs_cid_ipfs_cid_ipfs_cid_ipfs_cid');
  }

  function _speechWithdrawal(
    string memory _message,
    string memory _target,
    uint256 _relayFeeBPS
  ) internal view returns (IPrivacyPool.Withdrawal memory) {
    return IPrivacyPool.Withdrawal({
      processooor: address(_broadcaster),
      data: abi.encode(ZipBroadcaster.Speech(_message, _target, _RELAYER, _relayFeeBPS))
    });
  }

  function _prove(
    IPrivacyPool.Withdrawal memory _w,
    Commitment memory _c,
    uint256 _amount
  ) internal returns (ProofLib.WithdrawProof memory _proof) {
    uint256 _context = uint256(keccak256(abi.encode(_w, _zcPool.SCOPE()))) % SNARK_SCALAR_FIELD;
    Commitment memory _new;
    (_new, _proof) = _computeNewCommitmentAndProof(
      _context,
      WithdrawalParams({
        withdrawnAmount: _amount,
        newNullifier: 'new_nullifier',
        newSecret: 'new_secret',
        recipient: address(0),
        commitment: _c
      })
    );
  }

  /*///////////////////////////////////////////////////////////////
                               TESTS
  //////////////////////////////////////////////////////////////*/

  function test_launchIsPlainErc20AfterGuard() public view {
    assertEq(_zc.totalSupply(), 1_000_000_000 ether, 'supply');
    assertGt(_zc.balanceOf(_DEV), 0, 'dev buy landed');
    assertEq(_zc.balanceOf(_ALICE), 5_000_000 ether, 'plain transfer, no tax');
  }

  function test_zipTakesVettingFee() public {
    uint256 _epBefore = _zc.balanceOf(address(_entrypoint));
    Commitment memory _c = _zip(_ALICE, 1_000_000 ether, 'n1', 's1');
    assertEq(_zc.balanceOf(address(_zcPool)), _c.value, 'pool holds note value');
    assertEq(_zc.balanceOf(address(_entrypoint)) - _epBefore, 1_000_000 ether - _c.value, 'vetting fee kept');
  }

  function test_speakAnon_burnsAndBroadcasts() public {
    Commitment memory _c = _zip(_ALICE, 1_000_000 ether, 'n1', 's1');
    _pushAspRoot();

    string memory _msg = 'The mysterious gentleman looks around much less than the average person.';
    string memory _to = 'someone who ate at Beautiful Plants, 18, successful';
    IPrivacyPool.Withdrawal memory _w = _speechWithdrawal(_msg, _to, _ZC_RELAY_FEE_BPS);
    uint256 _amount = 400_000 ether;
    ProofLib.WithdrawProof memory _proof = _prove(_w, _c, _amount);

    uint256 _fee = (_amount * _ZC_RELAY_FEE_BPS) / 10_000;
    uint256 _burnBefore = _zc.balanceOf(_BURN);

    vm.expectEmit(address(_broadcaster));
    emit ZipBroadcaster.Spoken(address(0), _proof.pubSignals[1], _amount - _fee, _fee, _msg, _to);

    vm.prank(_RELAYER);
    _broadcaster.speakAnon(_w, _proof);

    assertEq(_zc.balanceOf(_BURN) - _burnBefore, _amount - _fee, 'burned');
    assertEq(_zc.balanceOf(_RELAYER), _fee, 'relayer paid');
    assertEq(_zc.balanceOf(address(_broadcaster)), 0, 'broadcaster keeps nothing');
    assertEq(_zc.balanceOf(address(_zcPool)), _c.value - _amount, 'remainder stays zipped');
    assertTrue(_zcPool.nullifierHashes(_proof.pubSignals[1]), 'nullifier spent');
  }

  function test_speakAnon_relayerCannotRewriteMessage() public {
    Commitment memory _c = _zip(_ALICE, 1_000_000 ether, 'n1', 's1');
    _pushAspRoot();

    IPrivacyPool.Withdrawal memory _w = _speechWithdrawal('original words', '', _ZC_RELAY_FEE_BPS);
    ProofLib.WithdrawProof memory _proof = _prove(_w, _c, 100_000 ether);

    IPrivacyPool.Withdrawal memory _forged = _speechWithdrawal('forged words', '', _ZC_RELAY_FEE_BPS);
    vm.prank(_RELAYER);
    vm.expectRevert(IPrivacyPool.ContextMismatch.selector);
    _broadcaster.speakAnon(_forged, _proof);

    IPrivacyPool.Withdrawal memory _greedy = _speechWithdrawal('original words', '', 500);
    vm.prank(_RELAYER);
    vm.expectRevert(IPrivacyPool.ContextMismatch.selector);
    _broadcaster.speakAnon(_greedy, _proof);
  }

  function test_unzipThroughRelayer() public {
    Commitment memory _c = _zip(_ALICE, 1_000_000 ether, 'n1', 's1');
    _pushAspRoot();

    IPrivacyPool.Withdrawal memory _w = IPrivacyPool.Withdrawal({
      processooor: address(_entrypoint),
      data: abi.encode(IEntrypoint.RelayData({recipient: _BOB, feeRecipient: _RELAYER, relayFeeBPS: _ZC_RELAY_FEE_BPS}))
    });
    uint256 _amount = 600_000 ether;
    ProofLib.WithdrawProof memory _proof = _prove(_w, _c, _amount);

    uint256 _scope = _zcPool.SCOPE();
    vm.prank(_RELAYER);
    _entrypoint.relay(_w, _proof, _scope);

    uint256 _fee = (_amount * _ZC_RELAY_FEE_BPS) / 10_000;
    assertEq(_zc.balanceOf(_BOB), _amount - _fee, 'bob unzipped');
    assertEq(_zc.balanceOf(_RELAYER), _fee, 'relay fee');
  }

  function test_speakPublic() public {
    uint256 _burnBefore = _zc.balanceOf(_BURN);
    vm.startPrank(_ALICE);
    _zc.approve(address(_broadcaster), 50_000 ether);
    vm.expectEmit(address(_broadcaster));
    emit ZipBroadcaster.Spoken(_ALICE, 0, 50_000 ether, 0, '50 zipcoins have just been burned', 'Telroy');
    _broadcaster.speak(50_000 ether, '50 zipcoins have just been burned', 'Telroy');
    vm.stopPrank();
    assertEq(_zc.balanceOf(_BURN) - _burnBefore, 50_000 ether, 'burned');
  }

  function test_speakPublic_limits() public {
    vm.startPrank(_ALICE);
    _zc.approve(address(_broadcaster), type(uint256).max);

    vm.expectRevert(ZipBroadcaster.BurnTooSmall.selector);
    _broadcaster.speak(_MIN_BURN - 1, 'hi', '');

    vm.expectRevert(ZipBroadcaster.EmptyMessage.selector);
    _broadcaster.speak(_MIN_BURN, '', '');

    vm.expectRevert(ZipBroadcaster.MessageTooLong.selector);
    _broadcaster.speak(_MIN_BURN, string(new bytes(281)), '');

    vm.expectRevert(ZipBroadcaster.TargetTooLong.selector);
    _broadcaster.speak(_MIN_BURN, 'hi', string(new bytes(121)));
    vm.stopPrank();
  }
}
