// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC721Utils} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Utils.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint128, euint256, ebool, eaddress, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC-721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
abstract contract ERC721Confidential is Context, ERC165, IERC721Errors {
    using Strings for uint256;

    struct Balance {
        eaddress owner;
        euint128 balance;
    }

    struct OperatorApproval {
        eaddress operator;
        ebool value;
    }

    struct OperatorApprovals {
        eaddress owner;
        OperatorApproval[] approvals;
    }

    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(eaddress indexed from, eaddress indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(eaddress indexed owner, eaddress indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(eaddress indexed owner, eaddress indexed operator, ebool approved);

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => eaddress) private _owners;

    // Mapping owner address to token count
    Balance[] private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => eaddress) private _tokenApprovals;

    // Mapping from owner to operator approvals
    // mapping(eaddress => mapping(eaddress => ebool)) private _operatorApprovals;
    OperatorApprovals[] private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function balanceOf(address owner) public virtual returns (euint128) {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(address(0));
        }
        return findBalance(FHE.asEaddress(owner));
    }

    function ownerOf(uint256 tokenId) public view virtual returns (eaddress) {
        eaddress owner = _ownerOf(tokenId);
        // require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        // _requireOwned(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toString()) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    function approve(eaddress to, uint256 tokenId) public virtual {
        _approve(to, tokenId, FHE.asEaddress(_msgSender()));
    }

    function getApproved(uint256 tokenId) public view virtual returns (eaddress) {
        // _requireOwned(tokenId);

        return _getApproved(tokenId);
    }

    function setApprovalForAll(eaddress operator, ebool approved) public virtual {
        _setApprovalForAll(FHE.asEaddress(_msgSender()), operator, approved);
    }

    function isApprovedForAll(eaddress owner, eaddress operator) public virtual returns (ebool) {
        ebool resultFound;
        ebool result;
        (resultFound, result) = findOperatorApproval(owner, operator);
        return FHE.select(resultFound, result, FHE.asEbool(false));
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        // Setting an "auth" arguments enables the `_isAuthorized` check which verifies that the token exists
        // (from != 0). Therefore, it is not needed to verify that the return value is not 0 here.
        eaddress previousOwner = _update(to, tokenId, _msgSender());
        // TODO: convert to confidential error handling
        // if (previousOwner != from) {
        //     revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        // }
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        transferFrom(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, data);
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     *
     * IMPORTANT: Any overrides to this function that add ownership of tokens not tracked by the
     * core ERC-721 logic MUST be matched with the use of {_increaseBalance} to keep balances
     * consistent with ownership. The invariant to preserve is that for any address `a` the value returned by
     * `balanceOf(a)` must be equal to the number of tokens such that `_ownerOf(tokenId)` is `a`.
     */
    function _ownerOf(uint256 tokenId) internal view virtual returns (eaddress) {
        return _owners[tokenId];
    }

    /**
     * @dev Returns the approved address for `tokenId`. Returns 0 if `tokenId` is not minted.
     */
    function _getApproved(uint256 tokenId) internal view virtual returns (eaddress) {
        return _tokenApprovals[tokenId];
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `owner`'s tokens, or `tokenId` in
     * particular (ignoring whether it is owned by `owner`).
     *
     * WARNING: This function assumes that `owner` is the actual owner of `tokenId` and does not verify this
     * assumption.
     */
    function _isAuthorized(address owner, address spender, uint256 tokenId) internal virtual returns (ebool) {
        // return
        //     spender != address(0) &&
        //     (owner == spender || isApprovedForAll(owner, spender) || _getApproved(tokenId) == spender);

        eaddress e_spender = FHE.asEaddress(spender);
        eaddress e_owner = FHE.asEaddress(owner);
        return
            FHE.and(
                FHE.not(FHE.eq(e_spender, FHE.asEaddress(address(0)))),
                FHE.or(
                    FHE.or(FHE.eq(e_owner, e_spender), isApprovedForAll(e_owner, e_spender)),
                    FHE.eq(_getApproved(tokenId), e_spender)
                )
            );
    }

    // /**
    //  * @dev Checks if `spender` can operate on `tokenId`, assuming the provided `owner` is the actual owner.
    //  * Reverts if:
    //  * - `spender` does not have approval from `owner` for `tokenId`.
    //  * - `spender` does not have approval to manage all of `owner`'s assets.
    //  *
    //  * WARNING: This function assumes that `owner` is the actual owner of `tokenId` and does not verify this
    //  * assumption.
    //  */
    // function _checkAuthorized(address owner, address spender, uint256 tokenId) internal view virtual returns(ebool) {
    //     if (!_isAuthorized(owner, spender, tokenId)) {
    //         if (owner == address(0)) {
    //             revert ERC721NonexistentToken(tokenId);
    //         } else {
    //             revert ERC721InsufficientApproval(spender, tokenId);
    //         }
    //     }
    // }

    // /**
    //  * @dev Unsafe write access to the balances, used by extensions that "mint" tokens using an {ownerOf} override.
    //  *
    //  * NOTE: the value is limited to type(uint128).max. This protect against _balance overflow. It is unrealistic that
    //  * a uint256 would ever overflow from increments when these increments are bounded to uint128 values.
    //  *
    //  * WARNING: Increasing an account's balance using this function tends to be paired with an override of the
    //  * {_ownerOf} function to resolve the ownership of the corresponding tokens so that balances and ownership
    //  * remain consistent with one another.
    //  */
    // function _increaseBalance(address account, uint128 value) internal virtual {
    //     unchecked {
    //         _balances[account] += value;
    //     }
    // }

    /**
     * @dev Transfers `tokenId` from its current owner to `to`, or alternatively mints (or burns) if the current owner
     * (or `to`) is the zero address. Returns the owner of the `tokenId` before the update.
     *
     * The `auth` argument is optional. If the value passed is non 0, then this function will check that
     * `auth` is either the owner of the token, or approved to operate on the token (by the owner).
     *
     * Emits a {Transfer} event.
     *
     * NOTE: If overriding this function in a way that tracks balances, see also {_increaseBalance}.
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual returns (eaddress) {
        eaddress from = _ownerOf(tokenId);
        eaddress e_to = FHE.asEaddress(to);

        // Perform (optional) operator check
        // if (auth != address(0)) {
        //     _checkAuthorized(from, auth, tokenId);
        // }

        // Execute the update
        // If this is a transfer
        // if (from != address(0)) {
        //     // Clear approval. No need to re-authorize or emit the Approval event
        //     _approve(address(0), tokenId, address(0), false);
        // }

        _approve(FHE.asEaddress(address(0)), tokenId, FHE.asEaddress(address(0)), false);

        unchecked {
            euint128 delta = FHE.select(
                FHE.not(FHE.eq(from, FHE.asEaddress(address(0)))),
                FHE.asEuint128(1),
                FHE.asEuint128(0)
            );
            subtractBalance(from, delta);
        }

        // If this is a burning
        unchecked {
            euint128 delta = FHE.select(
                FHE.not(FHE.eq(e_to, FHE.asEaddress(address(0)))),
                FHE.asEuint128(1),
                FHE.asEuint128(0)
            );
            addBalance(from, delta);
        }

        // turn this into a nullop if the sender is not the owner
        _owners[tokenId] = FHE.select(FHE.eq(FHE.asEaddress(_msgSender()), from), e_to, _owners[tokenId]);

        emit Transfer(from, e_to, tokenId);

        return from;
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }

        eaddress previousOwner = _update(to, tokenId, address(0));
        // TODO: convert to confidential error handling
        // if (previousOwner != address(0)) {
        //     revert ERC721InvalidSender(address(0));
        // }
    }

    /**
     * @dev Mints `tokenId`, transfers it to `to` and checks for `to` acceptance.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual {
        _mint(to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), address(0), to, tokenId, data);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     * This is an internal function that does not check if the sender is authorized to operate on the token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal {
        eaddress previousOwner = _update(address(0), tokenId, address(0));
        // TODO: convert to confidential error handling
        // if (previousOwner == address(0)) {
        //     revert ERC721NonexistentToken(tokenId);
        // }
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        eaddress previousOwner = _update(to, tokenId, address(0));
        // TODO: convert to confidential error handling
        // if (previousOwner == address(0)) {
        //     revert ERC721NonexistentToken(tokenId);
        // } else if (previousOwner != from) {
        //     revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        // }
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking that contract recipients
     * are aware of the ERC-721 standard to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is like {safeTransferFrom} in the sense that it invokes
     * {IERC721Receiver-onERC721Received} on the receiver, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `tokenId` token must exist and be owned by `from`.
     * - `to` cannot be the zero address.
     * - `from` cannot be the zero address.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId) internal {
        _safeTransfer(from, to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeTransfer-address-address-uint256-}[`_safeTransfer`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, data);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * The `auth` argument is optional. If the value passed is non 0, then this function will check that `auth` is
     * either the owner of the token, or approved to operate on all tokens held by this owner.
     *
     * Emits an {Approval} event.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(eaddress to, uint256 tokenId, eaddress auth) internal {
        _approve(to, tokenId, auth, true);
    }

    /**
     * @dev Variant of `_approve` with an optional flag to enable or disable the {Approval} event. The event is not
     * emitted in the context of transfers.
     */
    function _approve(eaddress to, uint256 tokenId, eaddress auth, bool emitEvent) internal virtual {
        // Avoid reading the owner unless necessary

        eaddress owner = _ownerOf(tokenId);

        // Mimic the branch where the approval should not take place
        ebool cond1 = FHE.or(FHE.asEbool(emitEvent), FHE.not(FHE.eq(auth, FHE.asEaddress(address(0)))));
        ebool cond2 = FHE.and(
            FHE.and(FHE.not(FHE.eq(auth, FHE.asEaddress(address(0)))), FHE.not(FHE.eq(owner, auth))),
            FHE.not(isApprovedForAll(owner, auth))
        );

        // Turn the approval into a null operation
        to = FHE.select(FHE.and(cond1, cond2), _tokenApprovals[tokenId], to);
        // if (emitEvent || auth != address(0)) {
        //     eaddress owner = _ownerOf(tokenId);

        //     // We do not use _isAuthorized because single-token approvals should not be able to call approve
        //     if (auth != address(0) && owner != auth && !isApprovedForAll(owner, auth)) {
        //         revert ERC721InvalidApprover(auth);
        //     }

        if (emitEvent) {
            emit Approval(owner, to, tokenId);
        }
        // }

        _tokenApprovals[tokenId] = to;
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Requirements:
     * - operator can't be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(eaddress owner, eaddress operator, ebool approved) internal virtual returns (ebool) {
        ebool resultFound = FHE.asEbool(false);

        for (uint256 i = 0; i < _operatorApprovals.length; i++) {
            for (uint256 j = 0; j < _operatorApprovals[i].approvals.length; j++) {
                resultFound = FHE.select(
                    FHE.and(
                        FHE.eq(owner, _operatorApprovals[i].owner),
                        FHE.eq(operator, _operatorApprovals[i].approvals[j].operator)
                    ),
                    FHE.asEbool(true),
                    resultFound
                );

                _operatorApprovals[i].approvals[j].value = FHE.select(
                    resultFound,
                    approved,
                    _operatorApprovals[i].approvals[j].value
                );
            }
        }

        emit ApprovalForAll(owner, operator, approved);

        return resultFound;
    }

    // /**
    //  * @dev Reverts if the `tokenId` doesn't have a current owner (it hasn't been minted, or it has been burned).
    //  * Returns the owner.
    //  *
    //  * Overrides to ownership logic should be done to {_ownerOf}.
    //  */
    // function _requireOwned(uint256 tokenId) internal view returns (address) {
    //     eaddress owner = _ownerOf(tokenId);
    //     return owner;
    // }

    function findOperatorApproval(eaddress owner, eaddress operator) internal virtual returns (ebool, ebool) {
        ebool resultFound = FHE.asEbool(false);
        ebool result = FHE.asEbool(false);

        for (uint256 i = 0; i < _operatorApprovals.length; i++) {
            for (uint256 j = 0; j < _operatorApprovals[i].approvals.length; j++) {
                resultFound = FHE.select(
                    FHE.and(
                        FHE.eq(owner, _operatorApprovals[i].owner),
                        FHE.eq(operator, _operatorApprovals[i].approvals[j].operator)
                    ),
                    FHE.asEbool(true),
                    resultFound
                );

                result = FHE.select(resultFound, _operatorApprovals[i].approvals[j].value, resultFound);
            }
        }

        return (resultFound, result);
    }

    function findBalance(eaddress owner) internal virtual returns (euint128 ret) {
        for (uint256 i = 0; i < _balances.length; i++) {
            ebool foundMatch = FHE.eq(_balances[i].owner, owner);
            ret = FHE.select(foundMatch, _balances[i].balance, ret);
        }
    }

    function addBalance(eaddress owner, euint128 delta) internal virtual returns (ebool success) {
        for (uint256 i = 0; i < _balances.length; i++) {
            ebool foundMatch = FHE.eq(_balances[i].owner, owner);
            success = FHE.select(foundMatch, FHE.asEbool(true), success);
            _balances[i].balance = FHE.select(foundMatch, FHE.add(_balances[i].balance, delta), _balances[i].balance);
        }
    }

    function subtractBalance(eaddress owner, euint128 delta) internal virtual returns (ebool success) {
        for (uint256 i = 0; i < _balances.length; i++) {
            ebool foundMatch = FHE.eq(_balances[i].owner, owner);
            success = FHE.select(foundMatch, FHE.asEbool(true), success);
            _balances[i].balance = FHE.select(foundMatch, FHE.sub(_balances[i].balance, delta), _balances[i].balance);
        }
    }
}
