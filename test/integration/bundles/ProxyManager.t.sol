// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ProxyManager} from "../../../src/core/bundles/storage/ProxyManager.sol";
import {AddressProvider} from "../../../src/core/config/AddressProvider.sol";
import {Roles} from "../../../src/security/Roles.sol";
import {ProxyFactory} from "../../../src/core/bundles/executors/ProxyFactory.sol";
import {PairTradingProxy} from "../../../src/core/bundles/executors/proxy.sol";
import {ProxyAccessControl} from "../../../src/core/bundles/security/proxyAccessControl.sol";
import {ClosePositionCallbacksMock} from "../../mocks/ClosePositionCallbacks.sol";
import {GMXOrderExecutorMock} from "../../mocks/GMX/GMXOrderExecutor.sol";

contract ProxyManagerTest is Test {

    ProxyManager public proxyManager;
    Roles public roles;
    AddressProvider public addressProvider;
    ProxyFactory public factory;
    ProxyAccessControl public proxyAccessControl;
    GMXOrderExecutorMock public gmxOrderExecutorMock;
    ClosePositionCallbacksMock public closePositions;

    address public ADMIN1 = 0x7F4C831de10684f85867899708cB49FfbF4983B9;
    address public ADMIN2 = 0xdD8f39262841F9425ed9180D0D989312E41EbEEc;
    address public ADMIN3 = 0xD023851C8AC8ceC385988e7E5af84b1A6D1f9079;

    address public USER1 = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
    address public USER2 = 0x01BAF8bD0669031A7252D75d8d7e21F44767582e;
    address public USER3 = 0xa160A99ec745FC1E3Aa6b144971225596a26BfB4;
    address public USER4 = 0x81806092f74bEd8B100c29517Fbb5765fBe592f1;
    address public USER5 = 0x63492B775e30a9E6b4b4761c12605EB9d071d5e9;
    address public USER6 = 0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41;
    address public USER7 = 0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;
    address public USER8 = 0xaF87D065e77C8CC2239327c5eDb3A432268e5831;
    address public USER9 = 0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d;
    address public USER10 = 0xf60becbba223EEA9495Da3f606753867eC10d139;

    address[] public users = [USER1, USER2, USER3, USER4, USER5, USER6, USER7, USER8, USER9, USER10];

    function setUp() public {
        vm.startPrank(ADMIN1);
        roles = new Roles(ADMIN1, ADMIN2, ADMIN3);
        addressProvider = new AddressProvider(address(roles));
        addressProvider.setAddress("Roles", address(roles));
        factory = new ProxyFactory(address(addressProvider));
        addressProvider.setAddress("ProxyFactory", address(factory));
        proxyManager = new ProxyManager(address(addressProvider));
        roles.allowContract(address(proxyManager), "ProxyManager");
        addressProvider.setAddress("ProxyManager", address(proxyManager));
        addressProvider.setAddress("PairTrading", address(0xABCD));
        proxyAccessControl = new ProxyAccessControl(address(roles));
        addressProvider.setAddress("ProxyAccessControl", address(proxyAccessControl));
        gmxOrderExecutorMock = new GMXOrderExecutorMock();
        closePositions = new ClosePositionCallbacksMock(address(addressProvider));
        addressProvider.setAddress("ClosePositionCallbacks", address(closePositions));
        roles.allowContract(address(closePositions), "ClosePositionCallbacks");
        vm.stopPrank();
    }

    /*
    * @notice Test the initializeProxy function
    * @dev Test the initializeProxy function to check if the proxy is initialized correctly
    * @custom:note initialize a proxy via deploy
    */
    function test_initializeProxy_whenProxyIsNotAvailable() public { 
        vm.prank(USER1);
        address proxy = proxyManager.initializeProxy(USER1);
        assertTrue(proxy != address(0));
        PairTradingProxy pairTradingProxy = PairTradingProxy(proxy);
        uint256 id = pairTradingProxy.getId();
        assertEq(id, 0);
        address owner = proxyManager.getOwner(id);
        assertEq(owner, USER1);
    }
    // command for testing: forge test --mt test_initializeProxy -vvvvv

    /*
    * @notice Test the initializeProxy function
    * @dev Test the initializeProxy function to check if the proxy is initialized correctly
    * @custom:note initialize a proxy via claim
    */
    function test_initializeProxy_whenProxyIsAvailable() public {
        address proxyToClaim = deployAndSetAvailableProxy();
        (uint256 proxyId, uint256 batchId, address proxyAddress, bool isAvailable) = proxyManager.getAvailableProxy();
        assertEq(proxyId, 0);
        assertEq(batchId, 0);
        assertEq(proxyAddress, proxyToClaim);
        assertEq(isAvailable, true);
        vm.prank(USER1);
        address proxy = proxyManager.initializeProxy(USER1);
        assertTrue(proxy == proxyToClaim);
        PairTradingProxy pairTradingProxy = PairTradingProxy(proxy);
        uint256 id = pairTradingProxy.getId();
        assertEq(id, 0);
        address owner = proxyManager.getOwner(id);
        assertEq(owner, USER1);
    }
    // command for testing: forge test --mt test_initializeProxy_whenProxyIsAvailable -vvvvv

    function test_multipleUsersDeployProxies() public {
        address[] memory proxies = multipleUsersDeployProxies(10);
        setAvailableProxy(proxies[3]);
        (uint256 proxyId, uint256 batchId, address proxyAddress, bool isAvailable) = proxyManager.getAvailableProxy();
        assertEq(proxyId, 3);
        assertEq(batchId, 0);
        assertEq(proxyAddress, proxies[3]);
        assertEq(isAvailable, true);
        vm.prank(users[3]);
        address proxy = proxyManager.initializeProxy(users[3]);
        assertTrue(proxy == proxies[3]);
        PairTradingProxy pairTradingProxy = PairTradingProxy(proxy);
        uint256 id = pairTradingProxy.getId();
        assertEq(id, 3);
        address owner = proxyManager.getOwner(id);
        assertEq(owner, users[3]);
        setAvailableProxy(proxies[7]);
        setAvailableProxy(proxies[9]);
        setAvailableProxy(proxies[1]);
        (proxyId, batchId, proxyAddress, isAvailable) = proxyManager.getAvailableProxy();
        assertEq(proxyId, 1);
        assertEq(batchId, 0);
        assertEq(proxyAddress, proxies[1]);
        assertEq(isAvailable, true);
        vm.prank(users[3]);
        address proxy2 = proxyManager.initializeProxy(users[3]);
        assertTrue(proxy2 == proxies[1]);
        PairTradingProxy pairTradingProxy2 = PairTradingProxy(proxy2);
        uint256 id2 = pairTradingProxy2.getId();
        assertEq(id2, 1);
        address owner2 = proxyManager.getOwner(id);
        assertEq(owner2, users[3]);
    }
    // command for testing: forge test --mt test_multipleUsersDeployProxies -vvvv

    function test_initialize_withFilledBatches() public {
        (, address proxyToBeClaimed) = fillBatches(3);
        assertTrue(proxyManager.isbatchFilled(0));
        assertTrue(proxyManager.isbatchFilled(1));
        assertTrue(proxyManager.isbatchFilled(2));
        (,,address proxyAddress,) = proxyManager.getAvailableProxy();
        assertEq(proxyToBeClaimed, proxyAddress);
        vm.prank(USER1);
        address proxy = proxyManager.initializeProxy(USER1);
        assertTrue(proxy == proxyToBeClaimed);
        assertEq(proxyManager.getOwner(PairTradingProxy(proxy).getId()), USER1);
        assertFalse(proxyManager.isbatchFilled(0));
    }
    // command for testing: forge test --mt test_initialize_withFilledBatches -vvvvv

    function test_setAvailable_NotAllowedSender() public {
        vm.expectRevert(abi.encodeWithSelector(ProxyManager.SenderNotAllowed.selector));
        proxyManager.setAvailable(123);
    }
    // command for testing: forge test --mt test_setAvailable_NotAllowedSender -vvvv

    function test_() public {}

    // Functions

    function deployAndSetAvailableProxy() public returns (address) {
        vm.startPrank(USER1);
        //deploy
        address proxy = proxyManager.initializeProxy(USER1);
        // set available
        gmxOrderExecutorMock.afterOrderExecution(address(closePositions), 0);  // simulates a callback from GMX when a decrease order is executed
        vm.stopPrank();
        return proxy;
    }

    function multipleUsersDeployProxies(uint256 numberOfUsers) public returns (address[] memory) {
        require(numberOfUsers <= 10, "Number of users must be less than or equal to 10");
        address[] memory proxies = new address[](numberOfUsers);
        for(uint256 i = 0; i < numberOfUsers; i++) {
            vm.prank(users[i]);
            address proxy = proxyManager.initializeProxy(users[i]);
            proxies[i] = proxy;
        }
        return proxies;
    }

    function setAvailableProxy(address proxy) public {
        PairTradingProxy pairTradingProxy = PairTradingProxy(proxy);
        uint256 proxyId = pairTradingProxy.getId();
        gmxOrderExecutorMock.afterOrderExecution(address(closePositions), proxyId);  // simulates a callback from GMX when a decrease order is executed to set available
    }

    function setAvailableProxyById(uint256 proxyId) public {
        gmxOrderExecutorMock.afterOrderExecution(address(closePositions), proxyId);  // simulates a callback from GMX when a decrease order is executed to set available
    }

    function fillBatches(uint256 batchesToFill) public returns (address lastProxy, address proxyToBeClaimed) {
        address proxy;
        for(uint256 i = 0; i < batchesToFill; i++){
            for(uint256 j = 0; j < 10; j++){
                vm.startPrank(users[j]);
                for(uint256 k = 0; k < 10; k++){
                    proxy = proxyManager.initializeProxy(users[j]);
                    if(i == 0 && j == 9 && k == 9){
                        proxyToBeClaimed = proxy;
                    }
                }
                vm.stopPrank();
                if(j == 9){
                    if(i == batchesToFill - 1){
                        console.log("last batch filled");
                        for(uint256 k = 0; k < 300; k++){
                            setAvailableProxyById(k);
                        }
                        lastProxy = proxy;
                        return (lastProxy, proxyToBeClaimed);
                    }
                }
            }
        }
    }

}