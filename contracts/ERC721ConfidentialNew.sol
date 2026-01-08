// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC721Utils} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Utils.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint128, euint256, ebool, eaddress} from "@fhevm/solidity/lib/FHE.sol";

import "./FHEUtils.sol";

// import "hardhat/console.sol";

/**
 * @title ERC721Confidential
 *
 * @notice
 * Confidential implementation of the ERC-721 Non-Fungible Token standard
 * for the Zama FHEVM.
 *
 * @dev
 * This contract is derived from OpenZeppelin ERC721 (v5.4.0), but modified
 * to operate over fully homomorphic encrypted (FHE) state.
 *
 * Key differences from standard ERC-721:
 *
 * - Token ownership, balances, approvals, and operator approvals are stored
 *   as encrypted values (`eaddress`, `euint128`, `ebool`).
 *
 * - Control flow depending on encrypted values is implemented in a
 *   constant-time manner using homomorphic selection (`FHE.select`).
 *
 * - Invalid operations do NOT revert. Instead:
 *   - an encrypted error bit is set in `_errorMask`
 *   - subsequent state updates are homomorphically neutralized (no-ops)
 *
 * - Errors and encrypted return values are surfaced via events and explicit
 *   ACL grants (`FHE.allow`, `FHE.allowThis`) rather than Solidity return values.
 *
 * This contract is intended to be consumed via the Zama Relayer SDK.
 * It is NOT a drop-in replacement for plaintext ERC-721.
 */
contract ERC721ConfidentialNew is Context, ERC165, IERC721Errors, ZamaEthereumConfig {
    using Strings for uint256;

    string private _name;
    string private _symbol;

    mapping(uint256 => eaddress) private _owners;
    FHEUtils.Balance[] private _balances;

    mapping(uint256 => eaddress) private _tokenApprovals;
    FHEUtils.OperatorApprovals[] private _operatorApprovals;

    euint256 private _errorMask;
    eaddress private enulladdr;

    /**
     * @dev
     * Resets the encrypted error bitmask at the beginning of a public entrypoint.
     *
     * Because this contract does not revert on invalid encrypted conditions,
     * all public/external functions must start from a clean error state.
     */
    modifier resetErrors() {
        _errorMask = FHE.asEuint256(0);
        FHE.allowThis(_errorMask);
        _;
    }

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;

        enulladdr = FHE.asEaddress(address(0));
        FHE.allowThis(enulladdr);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /*──────────────────────────
      ERC-721 public API
    ──────────────────────────*/

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @notice
     * Emits the encrypted balance of `owner`.
     *
     * @dev
     * Because encrypted values cannot be returned from non-view functions,
     * the balance is emitted as an event and access is granted to `owner`.
     *
     * If `owner` has no balance entry, an encrypted error is set instead of reverting
     * and an encryption of 0 is emitted as result.
     */
    function balanceOf(address owner) public resetErrors {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(address(0));
        }

        (euint128 bal, ebool found) = findBalance(FHE.asEaddress(owner));

        setObliviousError(FHE.not(found), FHEUtils.ERC721IncorrectOwner);

        // Authorize the owner to decrypt their balance
        FHE.allow(bal, owner);

        emit FHEUtils.ObliviousError(getError());
        emit FHEUtils.BalanceResult(bal);
    }

    /**
     * @notice
     * Returns the encrypted owner of `tokenId`.
     *
     * @dev
     * This function does not revert if the token does not exist.
     * The caller must decrypt the returned value and interpret errors separately.
     */
    function ownerOf(uint256 tokenId) public returns (eaddress) {
        eaddress owner = _owners[tokenId];
        FHE.allow(owner, _msgSender());
        return owner;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        string memory base = _baseURI();
        return bytes(base).length > 0 ? string.concat(base, tokenId.toString()) : "";
    }

    function approve(eaddress to, uint256 tokenId) public resetErrors {
        _approve(to, tokenId, _msgSender());
        emit FHEUtils.ObliviousError(getError());
    }

    function getApproved(uint256 tokenId) public view returns (eaddress) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, ebool approved) public resetErrors {
        _setApprovalForAll(FHE.asEaddress(_msgSender()), operator, approved);
        emit FHEUtils.ObliviousError(getError());
    }

    function isApprovedForAll(eaddress owner, address operator) public resetErrors returns (ebool) {
        (ebool found, ebool value) = findOperatorApproval(owner, operator);

        return FHE.select(found, value, FHE.asEbool(false));
    }

    function mint(address to, uint256 tokenId) external resetErrors {
        _safeMint(to, tokenId);
        emit FHEUtils.ObliviousError(getError());
    }

    /**
     * @notice
     * Confidential transfer of a token.
     *
     * @dev
     * All authorization checks are performed homomorphically.
     * If any check fails, the transfer is converted into a no-op and
     * the corresponding encrypted error is recorded.
     */
    function transferFrom(address from, address to, uint256 tokenId) public resetErrors {
        setObliviousError(FHEUtils.eIsNull(to), FHEUtils.ERC721InvalidReceiver);

        eaddress prev = _owners[tokenId];
        setObliviousError(FHE.not(FHE.eq(prev, FHE.asEaddress(from))), FHEUtils.ERC721IncorrectOwner);

        _update(FHE.asEaddress(to), tokenId, _msgSender());
        emit FHEUtils.ObliviousError(getError());
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public resetErrors {
        safeTransferFrom(from, to, tokenId, "");
        emit FHEUtils.ObliviousError(getError());
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, data);
        emit FHEUtils.ObliviousError(getError());
    }

    /*──────────────────────────
      Internal helpers
    ──────────────────────────*/

    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    function _ownerOf(uint256 tokenId) internal view returns (eaddress) {
        return _owners[tokenId];
    }

    function _isAuthorized(eaddress owner, address spender, uint256 tokenId) internal returns (ebool) {
        return
            FHE.and(
                FHE.asEbool(spender != address(0)),
                FHE.or(
                    FHE.or(FHE.eq(owner, spender), isApprovedForAll(owner, spender)),
                    FHE.eq(_tokenApprovals[tokenId], spender)
                )
            );
    }

    // function _checkAuthorized(eaddress owner, address spender, uint256 tokenId) internal returns (ebool) {
    //     ebool isAuthorized = _isAuthorized(owner, spender, tokenId);
    //     ebool ownerNull = FHEUtils.isNull(owner);

    //     ebool unauthorized = FHE.and(FHE.not(isAuthorized), FHE.not(shouldAbort()));

    //     return isAuthorized;
    // }

    /**
     * @dev
     * Core state transition function used for minting, burning, and transfers.
     *
     * This function NEVER reverts.
     * Instead:
     * - authorization failures set encrypted error bits
     * - all state updates are conditionally neutralized using `shouldAbort()`
     *
     * This preserves constant-time execution under FHE.
     */
    function _update(eaddress to, uint256 tokenId, address auth) internal {
        eaddress from = _ownerOf(tokenId);
        // eaddress e_to = FHE.asEaddress(to);

        // Perform (optional) operator check
        // if (auth != address(0)) {
        //     _checkAuthorized(from, auth, tokenId);
        // }
        // This will possibly update the _errorMask

        // Set an error if auth is not zero AND auth is unauthorized
        setObliviousError(
            FHE.and(FHE.asEbool(auth != address(0)), FHE.not(_isAuthorized(from, auth, tokenId))),
            FHEUtils.ERC721InvalidApprover
        );

        // Execute the update
        // If this is a transfer
        // if (from != address(0)) {
        //     // Clear approval. No need to re-authorize or emit the Approval event
        //     _approve(address(0), tokenId, address(0), false);
        // }

        ebool fromNotNull = FHEUtils.notNull(from);
        ebool toNotNull = FHEUtils.notNull(to);

        // if (from != address(0))
        _approve(enulladdr, tokenId, address(0), false);
        unchecked {
            euint128 delta = FHE.select(
                FHE.and(fromNotNull, FHE.not(shouldAbort())),
                FHE.asEuint128(1),
                FHE.asEuint128(0)
            );
            subtractBalance(from, delta);
        }

        // if (to != address(0))
        unchecked {
            euint128 delta = FHE.select(
                FHE.and(toNotNull, FHE.not(shouldAbort())),
                FHE.asEuint128(1),
                FHE.asEuint128(0)
            );
            addBalance(to, delta);
        }

        // Turn this into a nullop if the sender is not the owner OR if the caller already wants to cancel due to some reason
        ebool fromIsSender = FHE.eq(FHE.asEaddress(_msgSender()), from);
        _owners[tokenId] = FHE.select(FHE.and(fromIsSender, FHE.not(shouldAbort())), to, _owners[tokenId]);

        emit FHEUtils.ObliviousTransfer(from, to, tokenId);
    }

    function _mint(eaddress to, uint256 tokenId) internal {
        setObliviousError(FHE.eq(to, enulladdr), FHEUtils.ERC721InvalidReceiver);

        setObliviousError(FHEUtils.notNull(_owners[tokenId]), FHEUtils.ERC721InvalidReceiver);

        _update(to, tokenId, address(0));
    }

    function _safeMint(address to, uint256 tokenId) internal {
        _safeMint(to, tokenId, "");
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data) internal {
        _mint(FHE.asEaddress(to), tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), address(0), to, tokenId, data);
    }

    function _approve(eaddress to, uint256 tokenId, address auth) internal {
        _approve(to, tokenId, auth, true);
    }

    function _approve(eaddress to, uint256 tokenId, address auth, bool emitEvent) internal {
        eaddress owner = _owners[tokenId];

        ebool invalid = FHE.and(
            FHE.asEbool(auth != address(0)),
            FHE.and(FHE.not(FHE.eq(owner, auth)), FHE.not(isApprovedForAll(owner, auth)))
        );
        setObliviousError(invalid, FHEUtils.ERC721InvalidApprover);

        to = FHE.select(shouldAbort(), _tokenApprovals[tokenId], to);

        if (emitEvent) {
            emit FHEUtils.ObliviousApproval(owner, to, tokenId);
        }

        _tokenApprovals[tokenId] = to;
    }

    function _setApprovalForAll(eaddress owner, address operator, ebool approved) internal returns (ebool) {
        ebool success = FHE.asEbool(false);

        for (uint256 i = 0; i < _operatorApprovals.length; i++) {
            ebool matchFound = FHE.eq(owner, _operatorApprovals[i].owner);
            success = FHE.or(matchFound, success);

            _operatorApprovals[i].approvals[operator] = FHE.select(
                matchFound,
                approved,
                _operatorApprovals[i].approvals[operator]
            );
        }

        emit FHEUtils.ObliviousApprovalForAll(owner, operator, approved);

        return success;
    }

    function findOperatorApproval(eaddress owner, address operator) internal returns (ebool, ebool) {
        ebool found = FHE.asEbool(false);
        ebool value = FHE.asEbool(false);

        for (uint256 i = 0; i < _operatorApprovals.length; i++) {
            ebool matchFound = FHE.eq(owner, _operatorApprovals[i].owner);
            found = FHE.or(found, matchFound);
            value = _operatorApprovals[i].approvals[operator];
        }

        return (found, value);
    }

    /**
     * @dev
     * Finds the encrypted balance entry for `owner`.
     *
     * @notice
     * Because encrypted addresses cannot be used as mapping keys,
     * balances are stored in a linear array and searched using encrypted equality checks.
     */
    function findBalance(eaddress owner) internal returns (euint128, ebool) {
        ebool found = FHE.asEbool(false);
        euint128 bal = FHE.asEuint128(0);

        for (uint256 i = 0; i < _balances.length; i++) {
            ebool matchFound = FHE.eq(_balances[i].owner, owner);
            found = FHE.or(found, matchFound);
            bal = FHE.select(matchFound, _balances[i].balance, bal);
        }

        FHE.allowThis(bal);
        return (bal, found);
    }

    function addBalance(eaddress owner, euint128 delta) internal returns (ebool) {
        ebool success = FHE.asEbool(false);

        if (_balances.length == 0) {
            _balances.push(FHEUtils.Balance(FHEUtils.nullEaddress(), FHEUtils.nullEuint128()));
        }

        FHEUtils.Balance memory last = _balances[_balances.length - 1];

        if (!FHE.isInitialized(last.owner)) {
            _balances.push(FHEUtils.Balance(FHEUtils.nullEaddress(), FHEUtils.nullEuint128()));
        }

        euint128 b = FHE.asEuint128(0);

        for (uint256 i = 0; i < _balances.length; i++) {
            ebool matchFound = FHE.eq(_balances[i].owner, owner);
            success = FHE.or(success, matchFound);

            _balances[i].balance = FHE.select(matchFound, FHE.add(_balances[i].balance, delta), _balances[i].balance);
            b = FHE.select(matchFound, _balances[i].balance, b);
        }

        // Because balance might be updated and it might not
        FHE.allowThis(owner);
        FHE.allowThis(delta);
        FHE.allowThis(_balances[_balances.length - 1].owner);
        FHE.allowThis(_balances[_balances.length - 1].balance);

        // If no match was found, create a new balance object in the last empty slot
        // And authorize the contract on its owner and balance
        _balances[_balances.length - 1].owner = FHE.select(
            FHE.not(success),
            owner,
            _balances[_balances.length - 1].owner
        );

        _balances[_balances.length - 1].balance = FHE.select(
            FHE.not(success),
            delta,
            _balances[_balances.length - 1].balance
        );

        FHE.allowThis(b);
        return success;
    }

    function subtractBalance(eaddress owner, euint128 delta) internal returns (ebool) {
        ebool success = FHE.asEbool(false);
        euint128 b = FHE.asEuint128(0);

        for (uint256 i = 0; i < _balances.length; i++) {
            ebool matchFound = FHE.eq(_balances[i].owner, owner);
            success = FHE.or(success, matchFound);

            _balances[i].balance = FHE.select(matchFound, FHE.sub(_balances[i].balance, delta), _balances[i].balance);
            b = FHE.select(matchFound, _balances[i].balance, b);
        }

        setObliviousError(
            FHE.and(FHE.not(success), FHE.not(FHE.eq(delta, FHE.asEuint128(0)))),
            FHEUtils.ERC721IncorrectOwner
        );

        FHE.allowThis(b);
        return success;
    }

    /**
     * @dev
     * Returns whether execution should be logically aborted due to a previously
     * detected encrypted error.
     *
     * Note: This does NOT revert. It is used to obliviously nullify state writes.
     */
    function shouldAbort() internal returns (ebool) {
        return FHE.not(FHE.eq(_errorMask, FHE.asEuint256(0)));
    }

    function getError() internal returns (euint256) {
        FHE.allow(_errorMask, _msgSender());
        return _errorMask;
    }

    /**
     * @dev
     * Obliviously sets an error bit if `cond` is true.
     */
    function setObliviousError(ebool cond, uint8 errorPos) internal {
        euint256 bit = FHE.select(cond, FHE.asEuint256(1), FHE.asEuint256(0));

        _errorMask = FHE.or(_errorMask, FHE.shl(bit, errorPos));

        FHE.allowThis(_errorMask);
    }
}
