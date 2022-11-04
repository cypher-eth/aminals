// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "../lib/VRGDAs/src/LinearVRGDA.sol";
// Use SafeTransferLib from Solmate V7, which is identical to the
// SafeTransferLib from Solmate V6 besides the MIT license
import "../lib/solmate/src/utils/SafeTransferLib.sol";

error AminalDoesNotExist();
error PriceTooLow();
error SenderDoesNotHaveMaxAffinity();
error ExceedsMaxLocation();
error OnlyMoveWithGoTo();
error MaxAminalsSpawned();

contract Aminal is ERC721 {
    uint160 constant MAX_LOCATION = 1e9;

    uint256 constant MAX_AMINALS = 1e4;

    uint256 currentAminalId;

    bool going;

    modifier goingTo() {
        going = true;
        _;
        going = false;
    }

    event AminalSpawned(
        address spawner,
        uint256 aminalId,
        uint256 value,
        uint256 affinity
    );

    event AminalFed(
        address feeder,
        uint256 aminalId,
        uint256 value,
        uint256 newAffinity,
        bool newMax
    );

    mapping(uint256 => mapping(address => uint256)) public affinity;
    mapping(uint256 => uint256) public maxAffinity;
    // Spawning aminals has a global curve, while every other VRGDA is a local
    // curve. This is because we don't have per-aminal spawns. Breeding aminals,
    // for example, would have a local curve.
    LinearVRGDA spawnVRGDA;
    // Set up a mapping of VRGDAs per aminal
    // Each aminal has its own VRGDA curve, to represent its individual
    // level of attention
    mapping(uint256 => LinearVRGDA) feedVRGDA;
    mapping(uint256 => LinearVRGDA) goToVRGDA;

    // TODO: Update these values to more thoughtful ones
    // A spawn costs 0.01 ETH with a 10% price increase or decrease and an expected spawn rate of two per day
    uint256 spawnTargetPrice = 0.01e18;
    uint256 spawnPriceDecayPercent = 0.1e18;
    uint256 spawnPerTimeUnit = 2e18;

    // A feeding costs 0.001 ETH with a 5% price increase or decrease and an expected feed rate of 4 per hour, i.e. 4 * 24 = 96 over 24 hours
    uint256 feedTargetPrice = 0.001e18;
    uint256 feedPriceDecayPercent = 0.05e18;
    uint256 feedPerTimeUnit = 96e18;

    // A goto costs 0.001 ETH with a 10% price increase or decrease and an expected goto rate of 4 per hour, i.e. 4 * 24 = 96 over 24 hours
    uint256 feedTargetPrice = 0.001e18;
    uint256 feedPriceDecayPercent = 0.1e18;
    uint256 feedPerTimeUnit = 96e18;

    enum ActionTypes {
        SPAWN,
        FEED,
        GO_TO
    }

    constructor() ERC721("Aminal", "AMNL") {}

    function locationOf(uint256 aminalId)
        public
        view
        returns (uint160 location)
    {
        if (!_exists(aminalId)) revert AminalDoesNotExist();
        return uint160(ownerOf(aminalId));
    }

    function addressOf(uint256 aminalId)
        public
        view
        returns (address aminalAddress)
    {
        aminalAddress = address(
            uint160(
                uint256(keccak256(abi.encodePacked(address(this), aminalId)))
            )
        );
    }

    function spawn() public payable {
        if (currentAminalId == MAX_AMINALS) revert MaxAminalsSpawned();
        // TODO: Refactor this to overload the checkVRGDAInitialized function to
        // only require an action for spawn
        checkVRGDAInitialized(currentAminalId, spawn);
        uint256 price = spawnVRGDA.getVRGDAPrice(currentAminalId);
        bool excessPrice = checkExcessPrice(price);

        currentAminalId++;
        uint256 senderAffinity = updateAffinity(
            currentAminalId,
            msg.sender,
            msg.value
        );

        uint256 pseudorandomness = uint256(
            keccak256(
                abi.encodePacked(blockhash(block.number - 1), currentAminalId)
            )
        );
        address location = address(uint160(pseudorandomness % MAX_LOCATION));
        _mint(location, currentAminalId);

        if (excessPrice) {
            refundExcessPrice(price);
        }

        emit AminalSpawned(
            msg.sender,
            currentAminalId,
            msg.value,
            senderAffinity
        );
    }

    function feed(uint256 aminalId) public payable {
        uint256 senderAffinity = updateAffinity(
            aminalId,
            msg.sender,
            msg.value
        );

        bool newMax;
        if (senderAffinity > maxAffinity[aminalId]) {
            maxAffinity[aminalId] = senderAffinity;
            newMax = true;
        }

        emit AminalFed(msg.sender, aminalId, msg.value, senderAffinity, newMax);
    }

    function goTo(uint256 aminalId, uint160 location) public goingTo {
        if (!_exists(aminalId)) revert AminalDoesNotExist();
        if (affinity[aminalId][msg.sender] != maxAffinity[aminalId])
            revert SenderDoesNotHaveMaxAffinity();
        if (location > MAX_LOCATION) revert ExceedsMaxLocation();

        _transfer(ownerOf(aminalId), address(location), aminalId);
    }

    function updateAffinity(
        uint256 aminalId,
        address sender,
        uint256 value
    ) internal returns (uint256 senderAffinity) {
        // TODO how should affinity accumulate?
        affinity[aminalId][sender] += value;
        senderAffinity = affinity[aminalId][sender];
    }

    function checkVRGDAInitialized(uint256 aminalId, ActionTypes action)
        internal
    {
        if (action != ActionTypes.SPAWN) {
            vrgda = getMappingForAction(action)[aminalId];
        } else {
            vrgda = spawnVRGDA;
        }

        if (vrgda.perTimeUnit == 0) {
            initializeVRGDA(aminalId, action);
        }
    }

    function initializeVRGDA(LinearVRGDA vrgda, ActionTypes action) internal {
        if (ActionTypes == ActionTypes.SPAWN) {
            vrgda = new LinearVRGDA(
                spawnTargetPrice,
                spawnPriceDecayPercent,
                spawnPerTimeUnit
            );
        } else if (ActionTypes == ActionTypes.FEED) {
            vrgda = new LinearVRGDA(
                feedTargetPrice,
                feedPriceDecayPercent,
                feedPerTimeUnit
            );
        } else if (ActionTypes == ActionTypes.GO_TO) {
            vrgda = new LinearVRGDA(
                goToTargetPrice,
                goToPriceDecayPercent,
                goToPerTimeUnit
            );
        }
    }

    function getMappingForAction(ActionTypes action)
        internal
        returns (mapping(uint256 => LinearVRGDA))
    {
        if (action == ActionTypes.SPAWN) {
            return spawnVRGDA;
        } else if (action == ActionTypes.FEED) {
            return feedVRGDA;
        } else if (action == ActionTypes.GO_TO) {
            return goToVRGDA;
        }
    }

    // This takes care of users who have sent too much ETH between seeing a
    // transaction and confirming a transaction.
    // Returns true if there is excess, false if the price is exact, and reverts
    // if the price is too low We cannot refund here because refunding here
    // would open up a re-entrancy attack. We need to refund at the end of the
    // function.
    function checkExcessPrice(uint256 price) internal returns (bool) {
        if (msg.value > price) {
            msg.sender.transfer(msg.value - price);
            return true;
        } else if (msg.value < price) {
            revert PriceTooLow();
        } else {
            return false;
        }
    }

    function refundExcessPrice(uint256 price) internal {
        SafeTransferLib.safeTransferETH(msg.sender, msg.value - price);
    }

    // Protect against someone mining the location key by disallowing any tranfser besides goto
    function _beforeTokenTransfer(
        address,
        address,
        uint256
    ) internal view override(ERC721) {
        if (!going) revert OnlyMoveWithGoTo();
    }
}
