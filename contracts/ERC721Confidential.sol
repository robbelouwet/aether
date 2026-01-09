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
import "./FHEUtils.sol";

contract ERC721Confidential is Context, ERC165, IERC721Errors, ZamaEthereumConfig {
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => eaddress) private _owners;

    // Mapping owner address to token count
    FHEUtils.Balance[] private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => eaddress) private _tokenApprovals;

    // Mapping from owner to operator approvals
    // Counter
    uint256 private _approvalsCounter;
    // index => owner
    mapping(uint256 => eaddress) private _approvalOwners;
    // index => operator => approval
    mapping(uint256 => mapping(address => ebool)) _operatorApprovals;

    // A bitmask that can hold up to 256 bits each one referring to an error that occured during execution of the last transaction to this contract
    euint256 private _errorMask;

    eaddress private enulladdr;

    modifier resetErrors() {
        _errorMask = FHE.asEuint256(0);
        FHE.allowThis(_errorMask);
        _;
    }

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;

        enulladdr = FHE.asEaddress(address(0));
        _approvalsCounter = 0;
        FHE.allowThis(enulladdr);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function balanceOf(address owner) public virtual resetErrors {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(owner);
        }

        euint128 b = findBalance(FHE.asEaddress(owner));

        // Authorize the owner, not necessarily the caller
        FHE.allow(b, owner);

        emit FHEUtils.ObliviousError(getError());
        emit FHEUtils.BalanceResult(b);
    }

    function ownerOf(uint256 tokenId) public virtual resetErrors {
        eaddress owner = _ownerOf(tokenId);
        // require(owner != address(0), "ERC721: invalid token ID");

        FHE.allow(owner, _msgSender());
        emit FHEUtils.OwnerResult(owner);
        emit FHEUtils.ObliviousError(getError());
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

    function approve(address to, uint256 tokenId) public virtual resetErrors {
        _approve(to, tokenId, _msgSender());
        emit FHEUtils.ObliviousError(getError());
    }

    function getApproved(uint256 tokenId) public view virtual returns (eaddress) {
        // _requireOwned(tokenId);

        return _getApproved(tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual resetErrors {
        _setApprovalForAll(FHE.asEaddress(_msgSender()), operator, FHE.asEbool(approved));
        emit FHEUtils.ObliviousError(getError());
    }

    function isApprovedForAll(address owner, address operator) public virtual resetErrors returns (ebool) {
        eaddress e_owner = FHE.asEaddress(owner);
        ebool result = findOperatorApproval(e_owner, operator);

        emit FHEUtils.ObliviousError(getError());
        emit FHEUtils.ObliviousApprovalForAll(e_owner, operator, result);
        return result;
    }

    function mint(address to, uint256 tokenId) external resetErrors {
        _safeMint(to, tokenId);
        emit FHEUtils.ObliviousError(getError());
    }

    function _transferFrom(address from, address to, uint256 tokenId) internal virtual {
        // if (to == address(0)) {
        //     revert ERC721InvalidReceiver(address(0));
        // }
        setObliviousError(FHEUtils.eIsNull(to), FHEUtils.ERC721InvalidReceiver);

        // Setting an "auth" arguments enables the `_isAuthorized` check which verifies that the token exists
        // (from != 0). Therefore, it is not needed to verify that the return value is not 0 here.
        eaddress previousOwner = _ownerOf(tokenId);

        setObliviousError(FHE.not(FHE.eq(previousOwner, FHE.asEaddress(from))), FHEUtils.ERC721IncorrectOwner);
        _update(FHE.asEaddress(to), tokenId, _msgSender());

        // TODO: convert to confidential error handling
        // if (previousOwner != from) {
        //     revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        // }
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual resetErrors {
        _transferFrom(from, to, tokenId);
        emit FHEUtils.ObliviousError(getError());
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual resetErrors {
        _transferFrom(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, "");
        emit FHEUtils.ObliviousError(getError());
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual resetErrors {
        _transferFrom(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, data);
        emit FHEUtils.ObliviousError(getError());
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     *
     * IMPORTANT: Any overrides to this function that add ownership of tokens not tracked by the
     * core ERC-721 logic MUST be matched with the use of {_increaseBalance} to keep balances
     * consistent with ownership. The invariant to preserve is that for any address `a` the value returned by
     * `balanceOf(a)` must be equal to the number of tokens such that `_ownerOf(tokenId)` is `a`.
     */
    function _ownerOf(uint256 tokenId) internal virtual returns (eaddress) {
        if (!FHE.isInitialized(_owners[tokenId])) {
            return enulladdr;
        }

        return _owners[tokenId];
    }

    /**
     * @dev Returns the approved address for `tokenId`. Returns 0 if `tokenId` is not minted.
     */
    function _getApproved(uint256 tokenId) internal view virtual returns (eaddress) {
        if (!FHE.isInitialized(_tokenApprovals[tokenId])) {
            return enulladdr;
        }

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `owner`'s tokens, or `tokenId` in
     * particular (ignoring whether it is owned by `owner`).
     *
     * WARNING: This function assumes that `owner` is the actual owner of `tokenId` and does not verify this
     * assumption.
     */
    function _isAuthorized(eaddress owner, address spender, uint256 tokenId) internal virtual returns (ebool) {
        // return
        //     spender != address(0) &&
        //     (owner == spender || isApprovedForAll(owner, spender) || _getApproved(tokenId) == spender);

        // if spender != 0x0 and spender is approved on the specified token OR on all of owner's tokens
        return
            FHE.and(
                FHE.asEbool(spender != address(0)),
                FHE.or(
                    FHE.or(FHE.eq(owner, spender), findOperatorApproval(owner, spender)),
                    FHE.eq(_getApproved(tokenId), spender)
                )
            );
    }

    /**
     * @dev Checks if `spender` can operate on `tokenId`, assuming the provided `owner` is the actual owner.
     * Reverts if:
     * - `spender` does not have approval from `owner` for `tokenId`.
     * - `spender` does not have approval to manage all of `owner`'s assets.
     *
     * WARNING: This function assumes that `owner` is the actual owner of `tokenId` and does not verify this
     * assumption.
     */
    function _checkAuthorized(eaddress owner, address spender, uint256 tokenId) internal virtual returns (ebool) {
        ebool allowedToSpend = _isAuthorized(owner, spender, tokenId);
        ebool ownerIsZero = FHEUtils.isNull(owner);

        ebool unauthorized = FHE.and(FHE.not(allowedToSpend), FHE.not(shouldAbort()));

        ebool cond1 = FHE.and(unauthorized, ownerIsZero);
        // setObliviousError(cond1, FHEUtils.ERC721NonexistentToken);

        ebool cond2 = FHE.and(unauthorized, FHE.not(ownerIsZero));
        // setObliviousError(cond2, FHEUtils.ERC721InsufficientApproval);

        // if (!_isAuthorized(owner, spender, tokenId)) {
        //     if (owner == address(0)) {
        //         revert ERC721NonexistentToken(tokenId);
        //     } else {
        //         revert ERC721InsufficientApproval(spender, tokenId);
        //     }
        // }

        return FHE.not(FHE.or(cond1, cond2));
    }

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
    function _update(eaddress to, uint256 tokenId, address auth) internal virtual {
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
        _approve(address(0), tokenId, address(0), false);
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

        // Turn this into a nullop if some error has been raised before this point
        // ebool fromIsSender = FHE.eq(FHE.asEaddress(_msgSender()), from);
        _owners[tokenId] = FHE.select(FHE.not(shouldAbort()), to, _ownerOf(tokenId));

        euint256 e_tokenId = FHE.asEuint256(tokenId);

        FHE.allowThis(_owners[tokenId]);

        FHE.allowThis(e_tokenId);
        FHE.allowThis(from);
        FHE.allowThis(to);

        FHE.allow(e_tokenId, _msgSender());
        FHE.allow(from, _msgSender());
        FHE.allow(to, _msgSender());
        emit FHEUtils.ObliviousTransfer(from, to, e_tokenId);

        // return from;
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
    function _mint(eaddress to, uint256 tokenId) internal {
        // if (to == address(0)) {
        //     revert ERC721InvalidReceiver(address(0));
        // }
        setObliviousError(FHE.eq(to, enulladdr), FHEUtils.ERC721InvalidReceiver);

        // if (previousOwner != address(0)) {
        //     revert ERC721InvalidSender(address(0));
        // }
        setObliviousError(FHEUtils.notNull(_ownerOf(tokenId)), FHEUtils.ERC721InvalidReceiver);

        _update(to, tokenId, address(0));
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
        _mint(FHE.asEaddress(to), tokenId);
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
        eaddress previousOwner = _ownerOf(tokenId);

        // if (previousOwner == address(0)) {
        //     revert ERC721NonexistentToken(tokenId);
        // }
        setObliviousError(FHEUtils.isNull(previousOwner), FHEUtils.ERC721NonexistentToken);

        _update(enulladdr, tokenId, address(0));
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
    function _transfer(eaddress from, eaddress to, uint256 tokenId) internal {
        // if (to == address(0)) {
        //     revert ERC721InvalidReceiver(address(0));
        // }
        ebool isIllegal = FHEUtils.isNull(to);
        setObliviousError(isIllegal, FHEUtils.ERC721InvalidReceiver);

        eaddress previousOwner = _ownerOf(tokenId);

        // TODO: convert to confidential error handling
        // if (previousOwner == address(0)) {
        //     revert ERC721NonexistentToken(tokenId);
        // } else if (previousOwner != from) {
        //     revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        // }
        ebool prevOwnerNull = FHEUtils.isNull(previousOwner);
        setObliviousError(prevOwnerNull, FHEUtils.ERC721NonexistentToken);

        setObliviousError(
            FHE.and(FHE.not(FHE.eq(previousOwner, from)), FHE.not(prevOwnerNull)),
            FHEUtils.ERC721IncorrectOwner
        );

        _update(to, tokenId, address(0));
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
        _transfer(FHE.asEaddress(from), FHE.asEaddress(to), tokenId);
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
    function _approve(address to, uint256 tokenId, address auth) internal {
        _approve(to, tokenId, auth, true);
    }

    /**
     * @dev Variant of `_approve` with an optional flag to enable or disable the {Approval} event. The event is not
     * emitted in the context of transfers.
     */
    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual {
        // Avoid reading the owner unless necessary

        eaddress owner = _ownerOf(tokenId);

        // Mimic the branch where the approval should not take place
        ebool invalidApprover = FHE.and(
            FHE.asEbool(auth != address(0)),
            FHE.and(FHE.not(FHE.eq(owner, auth)), FHE.not(findOperatorApproval(owner, auth)))
        );
        setObliviousError(invalidApprover, FHEUtils.ERC721InvalidApprover);

        // if (emitEvent || auth != address(0)) {
        //     eaddress owner = _ownerOf(tokenId);

        //     // We do not use _isAuthorized because single-token approvals should not be able to call approve
        //     if (auth != address(0) && owner != auth && !isApprovedForAll(owner, auth)) {
        //         revert ERC721InvalidApprover(auth);
        //     }

        eaddress approver = FHE.select(shouldAbort(), _getApproved(tokenId), enulladdr);
        if (emitEvent) {
            emit FHEUtils.ObliviousApproval(owner, to, tokenId);
        }
        // }

        _tokenApprovals[tokenId] = approver;

        FHE.allowThis(_tokenApprovals[tokenId]);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Requirements:
     * - operator can't be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(eaddress owner, address operator, ebool approved) internal virtual {
        // Ensure at least 1 owner has granted an approval
        if (_approvalsCounter == 0) {
            _approvalOwners[_approvalsCounter] = enulladdr;
            _approvalsCounter += 1;
        }

        // Ensure last slot is empty
        eaddress last = _approvalOwners[_approvalsCounter - 1];
        if (FHE.isInitialized(last)) {
            _approvalOwners[_approvalsCounter] = enulladdr;
            _approvalsCounter += 1;
        }

        // Main logic
        ebool success = FHE.asEbool(false);
        for (uint256 i = 0; i < _approvalsCounter; i++) {
            ebool resultFound = FHE.eq(_approvalOwners[i], owner);
            success = FHE.or(success, resultFound);
            _operatorApprovals[i][operator] = FHE.select(resultFound, approved, _operatorApprovals[i][operator]);

            // We might've obliviously updated *an* approval, so authorize the contract, sender and operator to decrypt
            // for future use in findOperatorApproval
            FHE.allowThis(_operatorApprovals[i][operator]);
            FHE.allow(_operatorApprovals[i][operator], _msgSender());
            FHE.allow(_operatorApprovals[i][operator], operator);
        }

        // We might *not* have obliviously updated an approver if it didn't exist, so occupy the last empty slot
        _approvalOwners[_approvalsCounter - 1] = FHE.select(success, _approvalOwners[_approvalsCounter - 1], owner);
        _operatorApprovals[_approvalsCounter - 1][operator] = FHE.select(
            success,
            _operatorApprovals[_approvalsCounter - 1][operator],
            approved
        );

        // We might've obliviously updated the *last* owner and approval in _approvalOwners and _operatorApprovals,
        // So authorize again for future use in findOperatorApproval()
        FHE.allowThis(_approvalOwners[_approvalsCounter - 1]);

        // Sender and operator can decrypt owner of this approval (when decrypting event arg owner)
        FHE.allow(owner, _msgSender());
        FHE.allow(owner, operator);

        // Contract, owner and operator can decrypt this approval in future transactions (e.g. with findOperatorApproval())
        FHE.allowThis(_operatorApprovals[_approvalsCounter - 1][operator]);
        FHE.allow(_operatorApprovals[_approvalsCounter - 1][operator], _msgSender());
        FHE.allow(_operatorApprovals[_approvalsCounter - 1][operator], operator);

        // Because we don't know if we updated the last slot or any slot in the loop, approved is a different handle,
        // so allow sender and operator to decrypt approved from the event below
        FHE.allow(approved, _msgSender());
        FHE.allow(approved, operator);

        emit FHEUtils.ObliviousApprovalForAll(owner, operator, approved);
    }

    function findOperatorApproval(eaddress owner, address operator) internal virtual returns (ebool) {
        ebool result = FHE.asEbool(false);

        for (uint256 i = 0; i < _approvalsCounter; i++) {
            ebool resultFound = FHE.eq(_approvalOwners[i], owner);
            result = FHE.select(resultFound, _operatorApprovals[i][operator], result);
        }

        return result;
    }

    function findBalance(eaddress owner) internal virtual returns (euint128) {
        ebool success = FHE.asEbool(false);
        euint128 bal = FHE.asEuint128(0);

        for (uint256 i = 0; i < _balances.length; i++) {
            ebool foundMatch = FHE.eq(_balances[i].owner, owner);
            success = FHE.or(success, foundMatch);
            bal = FHE.select(foundMatch, _balances[i].balance, bal);
        }

        // Authorize this contract!
        FHE.allowThis(bal);

        return bal;
    }

    function addBalance(eaddress owner, euint128 delta) internal virtual returns (ebool) {
        ebool success = FHE.asEbool(false);
        // Ensure the last balance in the array is an "empty slot"

        if (_balances.length == 0) {
            _balances.push(FHEUtils.Balance(FHEUtils.nullEaddress(), FHEUtils.nullEuint128()));
        }

        FHEUtils.Balance storage last = _balances[_balances.length - 1];
        bool lastOneIsEmpty = !FHE.isInitialized(last.owner);
        if (!lastOneIsEmpty) {
            _balances.push(FHEUtils.Balance(FHEUtils.nullEaddress(), FHEUtils.nullEuint128()));
        }

        euint128 b = FHE.asEuint128(0);
        for (uint256 i = 0; i < _balances.length; i++) {
            ebool foundMatch = FHE.eq(_balances[i].owner, owner);
            success = FHE.or(success, foundMatch);
            _balances[i].balance = FHE.select(foundMatch, FHE.add(_balances[i].balance, delta), _balances[i].balance);
            b = FHE.select(foundMatch, _balances[i].balance, b);

            // Maybe we found a match and obliviously updated someone's balance,
            // so we need to re-authorize this contract every time!
            FHE.allowThis(_balances[i].balance);
        }

        // If no match was found, we occupy that last "empty slot"
        // Set owner & authorize contract
        _balances[_balances.length - 1].owner = FHE.select(
            FHE.not(success),
            owner,
            _balances[_balances.length - 1].owner
        );
        FHE.allowThis(_balances[_balances.length - 1].owner);

        _balances[_balances.length - 1].balance = FHE.select(
            FHE.not(success),
            delta,
            _balances[_balances.length - 1].balance
        );
        FHE.allowThis(_balances[_balances.length - 1].balance);

        // Authorize the contract after an update
        FHE.allowThis(b);

        return success;
    }

    function subtractBalance(eaddress owner, euint128 delta) internal virtual returns (ebool) {
        ebool success = FHE.asEbool(false);
        euint128 b = FHE.asEuint128(0);
        for (uint256 i = 0; i < _balances.length; i++) {
            ebool foundMatch = FHE.eq(_balances[i].owner, owner);
            success = FHE.or(success, foundMatch);
            _balances[i].balance = FHE.select(foundMatch, FHE.sub(_balances[i].balance, delta), _balances[i].balance);
            b = FHE.select(foundMatch, _balances[i].balance, b);
        }

        // If the owner does not have a balance yet
        setObliviousError(
            FHE.and(FHE.not(success), FHE.not(FHE.eq(FHE.asEuint128(0), delta))),
            FHEUtils.ERC721IncorrectOwner
        );

        // Authorize the contract after an update
        FHE.allowThis(b);

        return success;
    }

    function shouldAbort() internal returns (ebool) {
        return FHE.not(FHE.eq(_errorMask, FHE.asEuint256(0)));
    }

    function getError() internal returns (euint256) {
        FHE.allow(_errorMask, _msgSender());
        return _errorMask;
    }

    function setObliviousError(ebool cond, uint8 errorPos) internal {
        // Select the bit obliviously
        euint256 errorbit = FHE.select(cond, FHE.asEuint256(1), FHE.asEuint256(0));

        _errorMask = FHE.or(_errorMask, FHE.shl(errorbit, errorPos));

        // Authorize the contract again after updating!
        FHE.allowThis(_errorMask);
    }
}
