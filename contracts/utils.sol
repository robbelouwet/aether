// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {FHE, euint128, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";

library LootboxUtils {
    struct Tier {
        string name;
        // this should be 0 or at least as small as possible
        // if you set this to 10 for example, you wan't create masks with rarity < 10
        // Also, this acts like a 'label', this doesn't really hold a value,
        uint256 modulo_target;
        // this should be unique with every tier, acts like an unique ID
        // cannot be 0
        uint256 rarity;
        // this basically tells how big the buffer should be so that it can hold all the id's of the blueprints of
        // this tier in other words, 2^n-1 needs to be smaller than ItemBlueprint[].length of this tier, see
        // mapping tier_blueprints
        string[] blueprint_names;
    }

    struct ItemBlueprint {
        // How many NFT tokens of this blueprint that should be available
        euint128 id;
        euint128 remaining_supply;
        string name;
        euint128 rarity;
    }

    struct Box {
        euint128 dice;
        euint128 e_blueprint_id;
        bool isFinalized;
    }

    struct Ticket {
        uint256 block_number; // we can only specify a blocknumber of max 256 to request the hash from
        bytes32 seed_digest;
    }

    // amount of bits that makes up the default buffer size
    // for holding things like the max supply of a blueprint, max amount
    // of blueprints in a tier
    uint256 public constant default_buffer_size = 32;
}
