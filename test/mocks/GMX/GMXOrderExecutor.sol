//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IOrderCallbackReceiver} from "../../../src/interfaces/GMX/IOrderCallbackReceiver.sol";
import {EventUtils} from "gmx-synthetics/event/EventUtils.sol";
import {ClosePositionCallbacksMock} from "../../mocks/ClosePositionCallbacks.sol";

contract GMXOrderExecutorMock {

    function executeOrder(address _account, address _market, uint256 _size, uint256 _price, uint256 _triggerPrice, uint256 _executionFee) public {
        // TODO: Implement the order execution logic
    }

    function afterOrderExecution(address callbackContract, uint256 proxyId) public {
        ClosePositionCallbacksMock(callbackContract).afterOrderExecution(proxyId);
    }
}