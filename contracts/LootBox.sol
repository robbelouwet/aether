// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
// import {LootboxUtils as ut} from "./utils.sol";
// import {console} from "hardhat/console.sol";
// import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
// import {FHE, euint128, euint256, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
// import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

// contract LootBox is ERC721, ZamaEthereumConfig {
//     // contract owner
//     address _owner;

//     // How much should rolling 1 box cost? (in wei!)
//     uint256 _ticket_price;

//     mapping(address => ut.Box) _registry2;

//     // A simple list of the item blueprints
//     ut.ItemBlueprint[] _blueprints;

//     // All parameters necessary to validate ownership of an item id against the owner's provided challenge string etc.
//     event minedSuccessfully(address indexed user, string blueprint_name);
//     event ClearBoxRequested(euint128 dice, euint128 bp);
//     event challengeFailed(address indexed user, string message);
//     event newOwner(address indexed from, address to);

//     modifier isOwner() {
//         require(msg.sender == _owner);
//         _;
//     }

//     constructor(uint ticket_price) ERC721("Lootbox", "LOOT") {
//         _owner = msg.sender;
//         _ticket_price = ticket_price;
//     }

//     function _isBoxConfidentialLogicExecuted() private view returns (bool) {
//         ut.Box memory box = _registry2[msg.sender];
//         return FHE.isInitialized(box.dice) && FHE.isInitialized(box.e_blueprint_id);
//     }

//     modifier whenConfidentialLogicExecuted() {
//         require(_isBoxConfidentialLogicExecuted(), "foo confidential logic not yet executed!");
//         _;
//     }

//     function loot() public payable {
//         euint128 dice = FHE.randEuint128();
//         euint128 e_blueprint_seed = FHE.randEuint128();

//         // We're overflowing from 256-bit into 128-bit here, but I doubt there'll ever be more than 2^128 blueprints.
//         uint256 temp_len = _blueprints.length;
//         uint128 len;
//         assembly {
//             len := temp_len
//         }

//         euint128 e_blueprint_index = FHE.rem(e_blueprint_seed, len);

//         euint128 e_id;
//         euint128 e_rarity;
//         euint128 e_supply;
//         (e_id, e_rarity, e_supply) = find_blueprint_enc(e_blueprint_index);

//         // Check the "coin toss": did the sender win
//         // ebool has_won = FHE.eq(FHE.mod(dice, e_rarity), FHE.asUint128(8));

//         ut.Box memory box = ut.Box(FHE.randEuint128(), FHE.randEuint128(), false);

//         _registry2[msg.sender] = box;

//         require(msg.value > _ticket_price, "Did not send enough wei to pay for lootbox!");

//         uint256 remainder = msg.value - _ticket_price;

//         (bool ok, ) = msg.sender.call{value: remainder}("");
//         require(ok, "ETH transfer failed");

//         FHE.makePubliclyDecryptable(box.dice);
//         FHE.makePubliclyDecryptable(box.e_blueprint_id);

//         emit ClearBoxRequested(box.dice, box.e_blueprint_id);
//     }

//     function find_blueprint_enc(euint128 e_blueprint_index) internal returns (euint128, euint128, euint128) {
//         euint128 e_blueprint_id = FHE.asEuint128(0);
//         euint128 e_blueprint_rarity = FHE.asEuint128(0);
//         euint128 e_blueprint_supply = FHE.asEuint128(0);
//         for (uint128 i = 0; i < _blueprints.length; i++) {
//             euint128 e_i = FHE.asEuint128(i);

//             // Find the ID of the matching blueprint
//             e_blueprint_id = FHE.select(FHE.eq(e_blueprint_index, e_i), _blueprints[i].id, e_blueprint_id);

//             // Find the rarity of the matching blueprint
//             e_blueprint_rarity = FHE.select(FHE.eq(e_blueprint_index, e_i), _blueprints[i].rarity, e_blueprint_rarity);

//             // Find the remaining supply of the matching blueprint
//             e_blueprint_rarity = FHE.select(
//                 FHE.eq(e_blueprint_index, e_i),
//                 _blueprints[i].remaining_supply,
//                 e_blueprint_supply
//             );
//         }

//         return (e_blueprint_id, e_blueprint_rarity, e_blueprint_supply);
//     }

//     function mine(
//         uint128 clear_dice,
//         uint128 clear_blueprint_id,
//         bytes memory publicDecryptionProof
//     ) external whenConfidentialLogicExecuted {
//         ut.Box memory box = _registry2[msg.sender];

//         require(!box.isFinalized, "Box already looted!");

//         // Verify KMS proof
//         bytes32[] memory e_box = new bytes32[](2);
//         e_box[0] = FHE.toBytes32(box.dice);
//         e_box[1] = FHE.toBytes32(box.e_blueprint_id);

//         bytes memory abiClearFooClearBar = abi.encode(box.dice, box.e_blueprint_id);
//         FHE.checkSignatures(e_box, abiClearFooClearBar, publicDecryptionProof);

//         box.isFinalized = true;

//         // Extract a random index for the blueprints array
//         uint256 rel_bp_target = clear_blueprint_id % _blueprints.length;
//         ut.ItemBlueprint storage bp = _blueprints[rel_bp_target];

//         uint256 itemID = (uint256(bp.id) << 64) | bp.remaining_supply;

//         if (bp.remaining_supply < 1) {
//             // failed, no supply
//             revert();
//         }

//         // Has the randomly generated value hit the target?
//         bool has_won = (clear_dice % bp.rarity) == 1;

//         if (has_won) {
//             _safeMint(msg.sender, itemID);
//             bp.remaining_supply = bp.remaining_supply - 1;
//             emit minedSuccessfully(msg.sender, bp.name);
//         } else {}
//     }

//     /**
//      * Adds a blueprint to the specified tier.
//      *
//      * @param rarity (= tier ID) The tier you want to add this blueprint to.
//      * @param name Name of this blueprint, e.g. "Sword".
//      * @param max_supply The max amount of item ID's that can be generated fom this blueprint.
//      */
//     function addBlueprint(uint128 rarity, string memory name, uint128 max_supply) public isOwner {
//         // Find the highest existing blueprint ID
//         euint128 id = FHE.randEuint128();

//         ut.ItemBlueprint memory bp = ut.ItemBlueprint(id, FHE.asEuint128(max_supply), name, FHE.asEuint128(rarity));
//         bp.remaining_supply = FHE.asEuint128(max_supply);
//         _blueprints.push(bp);
//     }

//     /**
//      * Transfer to new owner.
//      */
//     function transferOwnership(address to) public isOwner {
//         _owner = to;
//         emit newOwner(msg.sender, _owner);
//     }

//     /**
//      * Query the price of 1 ticket (in wei!)
//      */
//     function getTicketPrice() public view returns (uint256) {
//         return _ticket_price;
//     }

//     function containsString(string[] storage array, string memory target) private view returns (bool) {
//         for (uint256 index = 0; index < array.length; index++) {
//             if (keccak256(abi.encodePacked(array[index])) == keccak256(abi.encodePacked(target))) {
//                 return true;
//             }
//         }
//         return false;
//     }

//     function containsInt(uint256[] storage array, uint256 target) private view returns (bool) {
//         for (uint256 index = 0; index < array.length; index++) {
//             if (array[index] == target) {
//                 return true;
//             }
//         }

//         return false;
//     }
// }
