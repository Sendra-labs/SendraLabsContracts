//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract DOCU_UNDO_POSITIONS {
    constructor() {
        //
    }

    /*
    En upgradeableLib registramos los positionTypes... debemos añadir un campo bytes[] a esos types.
    Se usara para registrar las instrucciones de como deshacer una posicion de ese tipo.
    el bytes[] estara compuesto de :
            * uint[] actionType // 0 = sendEth, 1 = sendToken, 2 = callFunction, 3 = callPayableFunction
            * address[] contracts // se usara para almacenar las direcciones de los contratos que se usan en la instruccion
            * string[] functions // se usara para almacenar las funciones que se usan en la instruccion en string 
            ********************* // functions tendrá este formato para encodewithselector: execute(uint256, address) por ejemplo 
            * uint[] paramsTypes // se usara para almacenar los tipos d parametros que se usan en la instruccion, igual que portocolLib.PositionParam.paramType
            * bytes[] params: valores de los parametros ---- NO, esto los pasamos dependiendo de la situación... hay que probar... porque habra que
            ******     meter memory values... que se obtengan de otra funcion... 

    
    Con esto podemos tener una funcion undo(bytes[] memory instructions) que se encargara de deshacer una posicion de cualquier tipo.

    function undo(bytes[] memory instructions) public {
        // decodifica instructions :
        bytes[] memory decodedInstructions = abi.decode(instructions, (bytes[]));
        // decodifica cada array dentro de decodedInstructions :
        uint[] memory actionType = abi.decode(decodedInstructions[0], (uint[]));
        address[] memory contracts = abi.decode(decodedInstructions[1], (address[]));
        string[] memory functions = abi.decode(decodedInstructions[2], (string[]));
        uint[] memory paramsTypes = abi.decode(decodedInstructions[3], (uint[]));
        bytes[] memory params = abi.decode(decodedInstructions[4], (bytes[]));
        // los params podra decodificarlos usando el decoderV2 de la libreria que tenemos  por ahi
        for(uint i = 0; i < actionType.length; i++) {
            if(actionType[i] == 0) {
                // callFunction
                (bool success, ) = contracts[i].call(bytes4(abi.encodeWithSelector(functions[i], params[i])));
                if(!success) revert ExecutionFailed();
            } else if(actionType[i] == 1) {
                // sendToken
                IERC20(contracts[i]).transfer(msg.sender, params[i]);
            } else if(actionType[i] == 2) {
                // sendEth
                payable(msg.sender).transfer(params[i]);
            }
        }
    }
    */
}
