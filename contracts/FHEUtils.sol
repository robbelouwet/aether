// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {FHE, euint256, eaddress, ebool, euint128, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";

library FHEUtils {
    uint8 public constant ERC721InvalidReceiver = 1;

    uint8 public constant ERC721NonexistentToken = 2;

    uint8 public constant ERC721InsufficientApproval = 3;

    uint8 public constant ERC721IncorrectOwner = 4;

    uint8 public constant ERC721InvalidApprover = 5;

    struct Balance {
        eaddress owner;
        euint128 balance;
    }

    struct OperatorApprovals {
        eaddress owner;
        mapping(address => ebool) approvals;
    }

    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event ObliviousTransfer(eaddress from, eaddress to, euint256 tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event ObliviousApproval(eaddress owner, eaddress approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ObliviousApprovalForAll(eaddress owner, address operator, ebool approved);

    /**
     * @dev emitted right before the top-level stack frame returns and the transaction ends. A way to notify the caller of an oblivious error.
     */
    event ObliviousError(euint256 error);

    event BalanceResult(euint128 balance);

    // Confidential AND plaintext checks
    function isNull(eaddress a) internal returns (ebool) {
        return FHE.not(notNull(a));
    }

    function notNull(eaddress a) internal returns (ebool) {
        return FHE.and(FHE.asEbool(notNullRaw(a)), notNullConfidential(a));
    }

    // ----------------
    // Plaintext nullcheck on confidential address
    function isNullRaw(eaddress a) internal pure returns (bool) {
        return (!notNullRaw(a));
    }

    function notNullRaw(eaddress a) internal pure returns (bool) {
        bytes32 temp;

        // The default null value of type `eaddress` is an underlying bytes32[]{0}
        // So cast it into a bytes32 variable in order to compare
        assembly {
            temp := a
        }

        return temp != bytes32(0);
    }

    // ----------------
    // Confidential checks on plaintext address
    function isNull(address a) internal pure returns (bool) {
        return a == address(0);
    }

    function eIsNull(address a) internal returns (ebool) {
        return FHE.asEbool(a == address(0));
    }

    // ----------------
    // Confidential check on confidential address
    function notNullConfidential(eaddress a) internal returns (ebool) {
        return FHE.not(FHE.eq(a, FHE.asEaddress(address(0))));
    }

    function nullEaddress() internal pure returns (eaddress) {
        bytes32 b = bytes32(0);

        eaddress a;

        assembly {
            a := b
        }

        return a;
    }

    function nullEuint128() internal pure returns (euint128) {
        bytes32 b = bytes32(0);

        euint128 a;

        assembly {
            a := b
        }

        return a;
    }
}
