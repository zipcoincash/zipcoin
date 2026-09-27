// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ERC1967Proxy} from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import {IERC20} from '@oz/token/ERC20/IERC20.sol';
import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';

import {Entrypoint} from 'contracts/Entrypoint.sol';
import {PrivacyPoolComplex} from 'contracts/implementations/PrivacyPoolComplex.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

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
 * @notice Shared constants and deploy steps for the zipcoin stack.
 * @dev Verifiers are the ones already live on Ethereum mainnet (0xbow ceremony keys), read from the 0xbow ETH pool.
 */
abstract contract ZipcoinBase is Script {
  address internal constant _WITHDRAWAL_VERIFIER = 0x022891F938Ae7fDC8Ab9Ead0FBf50aBA8C897D6d;
  address internal constant _RAGEQUIT_VERIFIER = 0xa45ACa8604a73D80C551fAad6355A5c3A5565eC6;
  ISendItFactory internal constant _SENDER = ISendItFactory(0x8D37c2981bdF809567092fd458B6bf3e97ee860c);

  function _deployEntrypoint(address _owner, address _postman) internal returns (Entrypoint _entrypoint) {
    address _impl = address(new Entrypoint());
    _entrypoint = Entrypoint(
      payable(address(new ERC1967Proxy(_impl, abi.encodeCall(Entrypoint.initialize, (_owner, _postman)))))
    );
  }

  function _deployPool(
    Entrypoint _entrypoint,
    IERC20 _zc,
    uint256 _minDeposit,
    uint256 _vettingFeeBPS,
    uint256 _maxRelayFeeBPS,
    uint256 _minBurn
  ) internal returns (PrivacyPoolComplex _pool, ZipBroadcaster _broadcaster) {
    _pool = new PrivacyPoolComplex(address(_entrypoint), _WITHDRAWAL_VERIFIER, _RAGEQUIT_VERIFIER, address(_zc));
    _entrypoint.registerPool(_zc, IPrivacyPool(address(_pool)), _minDeposit, _vettingFeeBPS, _maxRelayFeeBPS);
    _broadcaster = new ZipBroadcaster(IPrivacyPool(address(_pool)), _minBurn);
  }

  function _record(
    string memory _file,
    address _zc,
    address _entrypoint,
    address _pool,
    address _broadcaster,
    uint256 _deployBlock
  ) internal {
    string memory _o = 'zipcoin';
    vm.serializeUint(_o, 'chainId', block.chainid);
    vm.serializeAddress(_o, 'zc', _zc);
    vm.serializeAddress(_o, 'entrypoint', _entrypoint);
    vm.serializeAddress(_o, 'pool', _pool);
    vm.serializeAddress(_o, 'broadcaster', _broadcaster);
    vm.serializeUint(_o, 'scope', _pool == address(0) ? 0 : PrivacyPoolComplex(_pool).SCOPE());
    string memory _json = vm.serializeUint(_o, 'deployBlock', _deployBlock);
    vm.writeJson(_json, _file);
    console.log('wrote', _file);
  }
}

/**
 * @notice Mainnet step 1 (before the launch): Entrypoint behind an ERC1967 proxy.
 * @dev env: OWNER_ADDRESS, POSTMAN_ADDRESS
 */
contract DeployEntrypoint is ZipcoinBase {
  function run() external {
    address _owner = vm.envAddress('OWNER_ADDRESS');
    address _postman = vm.envAddress('POSTMAN_ADDRESS');
    vm.startBroadcast();
    Entrypoint _entrypoint = _deployEntrypoint(_owner, _postman);
    vm.stopBroadcast();
    console.log('Entrypoint', address(_entrypoint));
  }
}

/**
 * @notice Mainnet Entrypoint as a thin ERC1967 proxy over 0xbow's live implementation, byte-identical to the audited
 *         source we test against (only the UUPS `__self` immutable differs). ~0.29M gas instead of ~3.3M.
 *         The deployer receives no role. Upgrades are controlled by OWNER.
 * @dev env: OWNER_ADDRESS, POSTMAN_ADDRESS, optional ENTRYPOINT_IMPL
 */
contract DeployEntrypointProxy is ZipcoinBase {
  address internal constant _IMPL_0XBOW = 0x15e355024de1CDc74ADdea7EBDf98418Ba5B1a2c;

  function run() external {
    address _impl = vm.envOr('ENTRYPOINT_IMPL', _IMPL_0XBOW);
    bytes memory _init = abi.encodeCall(Entrypoint.initialize, (vm.envAddress('OWNER_ADDRESS'), vm.envAddress('POSTMAN_ADDRESS')));
    vm.startBroadcast();
    address _entrypoint = address(new ERC1967Proxy(_impl, _init));
    vm.stopBroadcast();
    console.log('Entrypoint', _entrypoint);
  }
}

/**
 * @notice Deploys a pool + broadcaster for any sender token on an existing Entrypoint, without registering it
 *         (registration is an OWNER transaction). Used for the TSST integration test and for $ZC at launch.
 * @dev env: ENTRYPOINT_ADDRESS, ASSET_ADDRESS, MIN_BURN, OUT_FILE
 */
contract DeployPoolUnregistered is ZipcoinBase {
  function run() external {
    Entrypoint _entrypoint = Entrypoint(payable(vm.envAddress('ENTRYPOINT_ADDRESS')));
    address _asset = vm.envAddress('ASSET_ADDRESS');
    uint256 _block = block.number;
    vm.startBroadcast();
    PrivacyPoolComplex _pool = new PrivacyPoolComplex(address(_entrypoint), _WITHDRAWAL_VERIFIER, _RAGEQUIT_VERIFIER, _asset);
    ZipBroadcaster _broadcaster = new ZipBroadcaster(IPrivacyPool(address(_pool)), vm.envUint('MIN_BURN'));
    vm.stopBroadcast();
    _record(vm.envString('OUT_FILE'), _asset, address(_entrypoint), address(_pool), address(_broadcaster), _block);
  }
}

/**
 * @notice Mainnet step 2 (right after the sender.family launch): ZC pool + registration + broadcaster.
 * @dev Must be broadcast by the Entrypoint OWNER.
 *      env: ENTRYPOINT_ADDRESS, ZC_ADDRESS, MIN_DEPOSIT, VETTING_FEE_BPS, MAX_RELAY_FEE_BPS, MIN_BURN
 */
contract DeployZcPool is ZipcoinBase {
  function run() external {
    Entrypoint _entrypoint = Entrypoint(payable(vm.envAddress('ENTRYPOINT_ADDRESS')));
    IERC20 _zc = IERC20(vm.envAddress('ZC_ADDRESS'));
    uint256 _block = block.number;
    vm.startBroadcast();
    (PrivacyPoolComplex _pool, ZipBroadcaster _broadcaster) = _deployPool(
      _entrypoint,
      _zc,
      vm.envUint('MIN_DEPOSIT'),
      vm.envUint('VETTING_FEE_BPS'),
      vm.envUint('MAX_RELAY_FEE_BPS'),
      vm.envUint('MIN_BURN')
    );
    vm.stopBroadcast();
    _record(
      './deployments/zipcoin-mainnet.json',
      address(_zc),
      address(_entrypoint),
      address(_pool),
      address(_broadcaster),
      _block
    );
  }
}

/**
 * @notice Local rehearsal on an anvil fork of mainnet: real sender.family launch + the full stack.
 * @dev env: OWNER_ADDRESS (the broadcaster), POSTMAN_ADDRESS, DEV_BUY_WEI
 */
contract LocalFork is ZipcoinBase {
  function run() external {
    address _owner = vm.envAddress('OWNER_ADDRESS');
    address _postman = vm.envAddress('POSTMAN_ADDRESS');
    uint256 _devBuy = vm.envOr('DEV_BUY_WEI', uint256(0.1 ether));
    uint256 _block = block.number;

    vm.startBroadcast();
    (address _zc,) = _SENDER.launchWith{value: _SENDER.launchFee() + _devBuy}(
      'zipcoin', 'ZC', 'ipfs://zipcoin-local', address(0), 0, false, type(int24).min
    );
    Entrypoint _entrypoint = _deployEntrypoint(_owner, _postman);
    (PrivacyPoolComplex _pool, ZipBroadcaster _broadcaster) =
      _deployPool(_entrypoint, IERC20(_zc), 1 ether, 50, 300, 1000 ether);
    vm.stopBroadcast();

    _record('./deployments/zipcoin-local.json', _zc, address(_entrypoint), address(_pool), address(_broadcaster), _block);
  }
}
