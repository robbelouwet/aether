// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {LootboxUtils as ut} from "./utils.sol";

contract LootBox is ERC721 {
    // contract owner
    address _owner;

    // How much should rolling 1 box cost? (in wei!)
    uint256 _ticket_price;

    // The ticket registry, players consume a ticket when rolling a box.
    // looting is free, tickets are what players actually buy.
    mapping(address => ut.Ticket[]) _registry;

    // Keep a mapping of all the tiers by their rarity, rarity acts like an UID for every tier.
    // We also need to store the tier names adn ID's seperately to easily check for duplicate tiers.
    mapping(uint256 => ut.Tier) _tiers;
    uint256[] _tier_rarities;
    string[] _tier_names;

    // For every tier rarity, store that tier's blueprints.
    mapping(uint256 => ut.ItemBlueprint[]) _tier_blueprints;

    // All parameters necessary to validate ownership of an item id against the owner's provided challenge string etc.
    event minedSuccessfully(
        address indexed user,
        string challenge,
        uint256 blocknumber,
        string tier_name,
        string blueprint_name,
        uint256 rarity
    );
    event challengeFailed(address indexed user, string message);
    event newOwner(address indexed from, address to);

    modifier isOwner() {
        require(msg.sender == _owner);
        _;
    }

    constructor(uint ticket_price) ERC721("Lootbox", "LBX") {
        _owner = msg.sender;
        _ticket_price = ticket_price;
    }

    /**
     * This is the entrypoint for users that have >= 1 tickets, and want to roll a lootbox.
     * First, the last ticket of the user is popped, if it exists.
     * This returns a random bytes32 hash, this represents the lootbox. The rest of the code
     * is just checking what the user has won.
     */
    function loot() public {
        bytes32 challenge = popTicket(msg.sender);

        // the combined input to hash. Should be challenge string and latest block hash and timestamp
        bytes memory input = abi.encodePacked(challenge, blockhash(block.number - 1));

        // hash of the challenge input
        bytes32 hashed_challenge = keccak256(input);

        uint256 int_hash;
        assembly {
            int_hash := shr(0, hashed_challenge)
        }

        mine(int_hash);
    }

    /**
     * This function is called by loot().
     * Checks whether the sender has won something.
     * We first assume the challenge is now a resulted hash that is completely random and no one could've predicted.
     * Not the user, not the miner.
     *
     * This functions is done in 2 steps. First, the challenge is treated as: challenge = *rarity tier*|*random item ID*
     * 1) First we bit mask the lower half to extract a random item ID
     * 2) We extract the upper half to obtain a random number, this random number is treated as an element in a finite field
     *    and if it matches ZERO within the field (specified by the item's blueprint), the lootbox "rolled this item successfully) and the NFT is minted
     *
     */
    function mine(uint256 challenge) internal {
        bytes32 hashed_challenge;
        assembly {
            hashed_challenge := shr(0, challenge)
        }

        // detect if we match a tier, and which one
        uint256 tier_rarity = findPresentTier(hashed_challenge); // returns mask_bits
        if (tier_rarity == 0) {
            emit challengeFailed(msg.sender, "Did not crack the challenge with the specified challenge string.");
            return;
        }

        // we know the tier, now figure out which blueprint they mined
        uint256 blueprint_id = findPresentBlueprint(hashed_challenge, tier_rarity);

        // we know which blueprint, now which exact blueprint instance (aka which blueprint instance id) did they mine?
        uint256 itemID = constructItemID(hashed_challenge, tier_rarity, blueprint_id);

        if (_ownerOf(itemID) != address(0)) {
            emit challengeFailed(msg.sender, "Mined successfully, but item already exists.");
            return;
        }

        _safeMint(msg.sender, itemID);

        // emit an event with all necessary information to validate that this user did in fact mine this itemID
        // in other words, validate ownership of this user with the token minted and placed in items mapping (see Lootbox.sol)
        //
        // you can re-hash the challenge with block hash and derive the blueprint_id, tier_id and blueprint instance id that matches the token
        emit minedSuccessfully(
            msg.sender,
            "appel",
            block.number,
            _tiers[tier_rarity].name,
            _tier_blueprints[_tiers[tier_rarity].rarity][blueprint_id].name,
            tier_rarity
        );
    }

    /**
     * Buys a ticket. Whenever a ticket is bought, that ticket grabs block.number+1 and stores it.
     * Whenever this ticket is popped, the hash of that blocknumber is calculated. This is the actual source of randomness.
     * It lies in predicting future blockhashes (which is extremely improbable).
     *
     * Combine this with a committed seed provided by the user, and neither the user or the miner can mess with the system
     */
    function buyTicket(string memory _seed, uint256 amount) public payable {
        require(amount > 0, "specify an amount greater than 0.");
        if (amount * _ticket_price > msg.value) {
            revert("Didn't send enough wei");
        }

        uint256 remainder = msg.value - (amount * _ticket_price);

        bytes32 seed = keccak256(abi.encodePacked(_seed));
        for (uint256 i = 0; i < amount; i++) {
            _registry[msg.sender].push(ut.Ticket(block.number + 1, seed));

            bytes32 latest_seed = keccak256(abi.encodePacked(seed));
            assembly {
                seed := shr(0, latest_seed)
            }
        }

        (bool ok, ) = msg.sender.call{value: remainder}("");
        require(ok, "ETH transfer failed");
    }

    /**
     * Pops the last ticket from the array of tickets of the address. In other words,
     * the random seed is calculated (see buyTicket()), then the ticket is removed
     * and the random seed is returned.
     */
    function popTicket(address adr) public isOwner returns (bytes32 seed) {
        ut.Ticket[] memory arr = _registry[adr];

        require(arr.length > 0 && arr[arr.length - 1].block_number != 0, "address doesn't have any tickets.");

        ut.Ticket memory t = arr[arr.length - 1];

        seed = keccak256(abi.encodePacked(t.personal_seed, blockhash(t.block_number)));

        _registry[adr].pop();
    }

    /**
     * This method checks which tier the bytes32 hash challenge aka lootbox covers.
     * If none is found, it returns 0.
     *
     * This happens by bit masking the challenge
     */
    function findPresentTier(bytes32 _hash) public view returns (uint256) {
        // Get all "rarity" random numbers in an array
        uint256[] memory rarities = getTierRarities();

        uint256 rarest_tier;
        for (uint256 i = 0; i < rarities.length; i++) {
            ut.Tier memory tier = _tiers[rarities[i]];
            uint256 r = rarities[i];

            // Move the upper half of the challenge in a buffer
            bytes32 hash_tier_buffer;
            uint256 offset = 256 - ut.default_buffer_size;
            assembly {
                hash_tier_buffer := shl(offset, _hash)
                hash_tier_buffer := shr(offset, hash_tier_buffer)
            }

            uint256 b_hash_tier_buffer;
            assembly {
                b_hash_tier_buffer := shr(0, hash_tier_buffer)
            }

            require(r != 0, "Cannot perform modulo 0.");

            // Here's where the magic happens:
            // We now have the specific Tier's finite field size, and this specific tier has a "modulo target", now we see if the challenge c
            uint256 modulo = b_hash_tier_buffer % r;
            if (modulo == tier.modulo_target) {
                // if this is the first match, or we match with a tier with higher rarity,
                // then set this new tier as the rarest one
                if (rarest_tier == 0 || tier.rarity > rarest_tier) {
                    rarest_tier = tier.rarity;
                }
            }
        }

        return rarest_tier;
    }

    /**
     * Like findpresentTier, but with blueprint.
     * Only difference is: if a tier was present, we already know the challenge hash contains an item.
     * In other words, we know for certain this method will return a blueprint.
     */
    function findPresentBlueprint(bytes32 _hash, uint256 tier_rarity) private view returns (uint256) {
        uint256 size = getTierBlueprintCount(tier_rarity); // returns 0-based length
        uint256 buffer_size = ut.default_buffer_size;

        // 1 buffer was for tier, and 1 holding the blueprint_id, keep those 2 buffers on memory
        uint256 left_offset = 256 - 2 * buffer_size;

        // then shift tier off memory
        uint256 right_offset = buffer_size;

        // convert the hash to an int, and shift the mask bits outside the buffer
        uint256 sliced_hash;
        assembly {
            sliced_hash := shl(left_offset, _hash)
            sliced_hash := shr(left_offset, sliced_hash)
            sliced_hash := shr(right_offset, sliced_hash)
        }

        // if we now calculate the hash % amount_items, we should result in a random, existing, constructItemID
        return sliced_hash % size;
    }

    /**
     * When a tier and blueprint are found in the challenge hash, we can construct an item ID.
     * It is basically a concatenation of the tier rarity, blueprint id, and blueprint's supply identifier.
     * The blueprint supply identifier is the 3rd and last piece of information we need to extract from the challenge hash.
     * THe concatenation of these 3 results in a unique ID that represents this specific item.
     * It's also the NFT that will be minted to the sender IF the item ID doesn't already exist.
     */
    function constructItemID(bytes32 _hash, uint256 tier_rarity, uint256 blueprint_id) private view returns (uint256) {
        // how many instances hould exist of this blueprint?
        uint256 blueprint_supply = getBlueprintMaxSupply(tier_rarity, blueprint_id);
        uint256 buff_size = ut.default_buffer_size;

        // Now we want to shift the tier's buffer and blueprint's buffer off memory
        uint256 shifted_hash;
        assembly {
            shifted_hash := shr(buff_size, _hash)
            shifted_hash := shr(buff_size, shifted_hash)
        }

        // now what remains are random bits of the hash which represent the blueprint's instance id
        // so modulo with the blueprint's max supply and we have our id
        uint256 id = shifted_hash % blueprint_supply;

        // now we have the tier, the blueprint id and the blueprint's instance id
        // concatenate them all to form the ultimate constructItemID or NFT token
        assembly {
            id := shl(buff_size, id)
            id := add(id, blueprint_id)
            id := shl(buff_size, id)
            id := add(id, tier_rarity)
        }

        return id;
    }

    /**
     * Creates a new tier.
     * @param name The name of the new tier, e.g.: "Exotic"
     * @param modulo_target Some number smaller than the rarity. Essentialy, the modulo of the challenge against the rarity
     *                      will be calculated. If it matches this modulo_target, the player has successfully looted this tier.
     * @param rarity How rare do you want this tier to be? E.g.: 50 will have odds of 1/50 for looting this tier.
     *               This is not the total odds someone has of looting an exact specific item, this also depends on whether
     *               or not that item already exists
     */
    function addTier(string memory name, uint256 modulo_target, uint256 rarity) public isOwner returns (uint256) {
        require(rarity != 0, "A rarity value for a tier cannot be 0.");
        require(_tiers[rarity].rarity == 0, "This tier exists.");
        require(containsInt(_tier_rarities, rarity) == false, "This is already a known rarity value");
        require(containsString(_tier_names, name) == false, "A tier with this name already exists");

        ut.Tier memory tier;
        tier.name = name;
        tier.modulo_target = modulo_target;
        tier.rarity = rarity;

        _tiers[rarity] = tier;
        _tier_rarities.push(rarity);
        _tier_names.push(name);

        return rarity;
    }

    /**
     * Adds a blueprint to the specified tier.
     *
     * @param tier_rarity (= tier ID) The tier you want to add this blueprint to.
     * @param name Name of this blueprint, e.g. "Sword".
     * @param max_supply The max amount of item ID's that can be generated fom this blueprint.
     */
    function addBlueprint(uint256 tier_rarity, string memory name, uint256 max_supply) public isOwner {
        require(_tiers[tier_rarity].rarity != 0, "Adding BluePrint to nonexist, uint supply_buffer_size, ent tier!");
        require(
            containsString(_tiers[tier_rarity].blueprint_names, name) == false,
            "A Blueprint with this name already exists in this tier!"
        );

        ut.ItemBlueprint memory bp = ut.ItemBlueprint(max_supply, name);
        _tiers[tier_rarity].blueprint_names.push(name);
        _tier_blueprints[tier_rarity].push(bp);
    }

    /**
     * Get the max supply of the specified blueprint of the specified tier.
     * Remember, tier_rarity acts like the tier_id.
     */
    function getBlueprintMaxSupply(uint256 tier_rarity, uint256 blueprint_id) public view returns (uint256) {
        require(_tiers[tier_rarity].rarity != 0, "Tier doesn't exist!");
        require(_tier_blueprints[tier_rarity].length > blueprint_id, "Blueprint ID doesn't exist!");
        return _tier_blueprints[tier_rarity][blueprint_id].max_supply;
    }

    /**
     * Get the amount of blueprints in the specified tier.
     */
    function getTierBlueprintCount(uint256 tier_rarity) public view returns (uint256) {
        require(_tiers[tier_rarity].rarity != 0, "This tier doesn't exist!");
        require(_tiers[tier_rarity].rarity == tier_rarity, "Something went wrong, tier not indexed by its rarity.");
        uint256 size = _tier_blueprints[tier_rarity].length;
        require(size != 0, "This tier doesn't have any blueprints!");
        return size;
    }

    /**
     * List the rarities of all the tiers.
     */
    function getTierRarities() public view returns (uint256[] memory) {
        return _tier_rarities;
    }

    /**
     * Transfer to new owner.
     */
    function transferOwnership(address to) public isOwner {
        _owner = to;
        emit newOwner(msg.sender, _owner);
    }

    /**
     * Query the price of 1 ticket (in wei!)
     */
    function getTicketPrice() public view returns (uint256) {
        return _ticket_price;
    }

    function containsString(string[] storage array, string memory target) private view returns (bool) {
        for (uint256 index = 0; index < array.length; index++) {
            if (keccak256(abi.encodePacked(array[index])) == keccak256(abi.encodePacked(target))) {
                return true;
            }
        }
        return false;
    }

    function containsInt(uint256[] storage array, uint256 target) private view returns (bool) {
        for (uint256 index = 0; index < array.length; index++) {
            if (array[index] == target) {
                return true;
            }
        }

        return false;
    }
}
