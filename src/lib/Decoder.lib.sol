//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ProtocolLib } from "./Protocol.lib.sol";

library DecoderLib {

    error InvalidParams(string functionName);
    error ParamsOutOfRange(uint256 paramsLength);
    /** V1 decoder
    function decoder(bytes[] calldata _data) external pure returns(ProtocolLib.DeFiParam[] memory){
        uint256[] memory paramsTypes = abi.decode(_data[0], (uint256[]));
        if(paramsTypes.length > 20 || paramsTypes.length < 1) revert ParamsOutOfRange(paramsTypes.length);
        ProtocolLib.DeFiParam[] memory params = new ProtocolLib.DeFiParam[](paramsTypes.length);
        uint256 offset = 0; 
        for(uint256 i = 0; i < paramsTypes.length; i++){
            ProtocolLib.DeFiParam memory param;
            if(paramsTypes[i] == 0){
                param._type = 0;
                param.w = abi.decode(_data[1][offset:offset+32], (address));
            } else if(paramsTypes[i] == 1){
                param._type = 1;
                param.x = abi.decode(_data[1][offset:offset+32], (uint256));
            } else if(paramsTypes[i] == 2){
                param._type = 2;
                param.y = abi.decode(_data[1][offset:offset+32], (int256));
            } else if(paramsTypes[i] == 3){
                param._type = 3;
                param.z = abi.decode(_data[1][offset:offset+32], (bool));
            } else if(paramsTypes[i] == 4){
                param._type = 4;
                param.v = _data[1][offset:offset+32];
            } else {
                revert InvalidParams("decoder");
            }
            params[i] = param;
            offset += 32;
        }
        return(params);
    }*/

    function decoder(bytes[] calldata _data) external pure returns(ProtocolLib.DeFiParam[] memory){
        uint256[] memory paramsTypes = abi.decode(_data[0], (uint256[]));
        bytes[] memory paramsDecoded = abi.decode(_data[1], (bytes[]));
        if(paramsTypes.length > 20 || paramsTypes.length < 1) revert ParamsOutOfRange(paramsTypes.length);
        ProtocolLib.DeFiParam[] memory params = new ProtocolLib.DeFiParam[](paramsTypes.length);
        for(uint256 i = 0; i < paramsTypes.length; i++){
            ProtocolLib.DeFiParam memory param;
            if(paramsTypes[i] == 0){
                param._type = 0;
                param.w = abi.decode(paramsDecoded[i], (address));
            } else if(paramsTypes[i] == 1){
                param._type = 1;
                param.x = abi.decode(paramsDecoded[i], (uint256));
            } else if(paramsTypes[i] == 2){
                param._type = 2;
                param.y = abi.decode(paramsDecoded[i], (int256));
            } else if(paramsTypes[i] == 3){
                param._type = 3;
                param.z = abi.decode(paramsDecoded[i], (bool));
            } else if(paramsTypes[i] == 4){
                param._type = 4;
                param.v = paramsDecoded[i];
            } else {
                revert InvalidParams("decoderV2");
            }
            params[i] = param;
        }
        return(params);
    }

}