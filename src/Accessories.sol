// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/access/Ownable.sol";
import "./Aminal.sol";

error AlreadyInitialized();
error ZeroAffinity();
error OnlyOwnerCanEquip();
error OnlyMaxAffinityCanDress();
error MaxAccessoriesMinted();
error OnlyMinterCanMint();

contract Accessories is ERC721, Ownable {
    constructor() ERC721("AccessoriesTemplate", "TEMP") {
        initialized = true;
    }

    event AccessoryEquipped(uint256 accessoryId, uint256 aminalId);

    uint256 maxAccessories;
    uint256 currentAccessoryId;

    address minter;
    address aminalAddress;

    mapping(uint256 => bool) equipped;

    bool initialized;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address _aminalAddress,
        uint256 supply
    ) public {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        _name = name_;
        _symbol = symbol_;
        aminalAddress = _aminalAddress;
        maxAccessories = supply;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function equip(uint256 accessoryId, uint256 aminalId) external {
        Aminal _aminal = Aminal(aminalAddress);
        if (ownerOf(accessoryId) != _aminal.addressOf(aminalId))
            revert OnlyOwnerCanEquip();

        uint256 senderAffinity = _aminal.affinity(aminalId, msg.sender);
        if (senderAffinity == 0) revert ZeroAffinity();

        if (_aminal.maxAffinity(aminalId) > senderAffinity)
            revert OnlyMaxAffinityCanDress();

        equipped[accessoryId] = true;

        emit AccessoryEquipped(accessoryId, aminalId);
    }

    function mint(address recipient) external {
        // TODO batch minting
        if (msg.sender != minter) revert OnlyMinterCanMint();
        if (currentAccessoryId == maxAccessories) revert MaxAccessoriesMinted();
        currentAccessoryId++;

        _mint(recipient, currentAccessoryId);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }
}
