// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Clones} from "openzeppelin/proxy/Clones.sol";
import "openzeppelin/access/Ownable.sol";

error ImplementationAddressCantBeZero();

contract AccessoryCreator is Ownable {
    address public template;

    constructor(address _template) implementationNotZero(_template) {
        template = _template;
    }

    function createAccessory(bytes32 salt, bytes calldata initData)
        external
        returns (address accessory)
    {
        // Create Sound Edition proxy.
        accessory = payable(
            Clones.cloneDeterministic(template, _saltedSalt(msg.sender, salt))
        );

        // Initialize proxy.
        assembly {
            // Grab the free memory pointer.
            let m := mload(0x40)
            // Copy the `initData` to the free memory.
            calldatacopy(m, initData.offset, initData.length)
            // Call the initializer, and revert if the call fails.
            if iszero(
                call(
                    gas(), // Gas remaining.
                    accessory, // Address of the edition.
                    0, // `msg.value` of the call: 0 ETH.
                    m, // Start of input.
                    initData.length, // Length of input.
                    0x00, // Start of output. Not used.
                    0x00 // Size of output. Not used.
                )
            ) {
                // Bubble up the revert if the call reverts.
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }
        }

        Ownable(accessory).transferOwnership(msg.sender);

        // TODO event
    }

    function setTemplate(address newTemplate)
        external
        implementationNotZero(newTemplate)
        onlyOwner
    {
        template = newTemplate;
    }

    function accessoryAddress(address by, bytes32 salt)
        external
        view
        returns (address addr, bool exists)
    {
        addr = Clones.predictDeterministicAddress(
            template,
            _saltedSalt(by, salt),
            address(this)
        );
        exists = addr.code.length > 0;
    }

    /**
     * @dev Returns the salted salt.
     *      To prevent griefing and accidental collisions from clients that don't
     *      generate their salt properly.
     * @param by   The caller of the {createSoundAndMints} function.
     * @param salt The salt, generated on the client side.
     * @return result The computed value.
     */
    function _saltedSalt(address by, bytes32 salt)
        internal
        pure
        returns (bytes32 result)
    {
        assembly {
            // Store the variables into the scratch space.
            mstore(0x00, by)
            mstore(0x20, salt)
            // Equivalent to `keccak256(abi.encode(by, salt))`.
            result := keccak256(0x00, 0x40)
        }
    }

    /**
     * @dev Reverts if the given implementation address is zero.
     * @param implementation The address of the implementation.
     */
    modifier implementationNotZero(address implementation) {
        if (implementation == address(0)) {
            revert ImplementationAddressCantBeZero();
        }
        _;
    }
}
