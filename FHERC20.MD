# FHERC20 Standard

## Motivation

This standard aims to bring Fully Homomorphic Encryption to the ERC20 standard. The FHERC20 standard has 3 goals:

- Confidentiality of token balances using FHE operations.
- Maximum compatibility with existing ERC20 infrastructure (wallets and etherscans)
- Reduction of potential conflict with existing ERC20s integrations.

## Concepts

### 1. Encrypted Balances.

Using the Fhenix CoFHE coprocessor, FHE operations are brought into the blockchain environment. Thus, the balance of an ERC20 token can remain in an encrypted state, only accessible under certain circumstances as follows:

#### A. Manually decrypted.

A user or contract can request to decrypt their own balance. This decrypted balance will be publicly available, so care must be taken to only decrypt a balance when necessary.

#### B. Decrypted with sealing.

A user or contract can provide the `publicKey` component of a `sealingKey` pair. The `privateKey` component is stored locally and privately by the user. Thus, when the sealed result is made available, it is only viewable by an entity that knows the `privateKey` component of the `sealingKey` pair. The sealed balance is thus only available to the requestor.

#### C. As part of an FHE operation.

The encrypted value can be used as part of an FHE operation, such as FHE.add, FHE.sub, or FHE.select (branching). The value remains encrypted throughout these FHE operations, and no data is revealed at any stage.

### 2. Indicated Balances.

The ERC20 standard is mature, and has existing for over a decade. As such, infrastructure has evolved around this standard. Public block scanners such as etherscan have integrated ERC20 balances and transfers as a core part of the blockchain protocol. The FHERC20 standard, while maintaining confidentiality of the true encrypted balance, aims to expose a minimally leaking `indicator` of an address's encrypted balance. The indicated balance is designed to maintain compatibility of FHERC20s with existing ERC20 infrastructure, mainly targeting wallets, portfolios, and block scanners.

Existing ERC20 functions and events expose a balance indicator instead of the true underlying encrypted balances. The indicated balance has two states: non-interacted which returns a `balanceOf` (indicatedBalance) of 0, and interacted which returns a `balanceOf` in the range of 0.0001 to 0.9999 inclusive. The first user interaction with an FHERC20 switches the state from non-interacted to interacted by setting the indicated balance to 0.5001. Subsequent interactions increment or decrement this value by 0.0001. For example, receiving any amount of an FHERC20 token will increase the indicated balance from 0.5001 to 0.5002 (+0.0001), while emitting a `Transfer` event with the `value` field set to 0.0001.

Users will be able to see that their balance has increased in their wallet when they receive FHERC20 tokens, but the true encrypted balance remains hidden. On etherscan, the ERC20 transfer will show that Bob transferred 0.0001 FHERC20 to Alice. Bob's FHERC20 balance will have been reduced by 0.0001, and Alice's FHERC20 balance will have been increased by 0.0001. These balance changes will be reflected in the balances they see in their existing wallets.

In the future, as the FHERC20 standard matures and infrastructure evolves to provide an interface that allows secure access to the true encrypted balances of users, the `indicatedBalance` returned by `balanceOf` can be left behind as a vestigial relic of interoperability and backwards compatibility. Indicated balances are opt out and can be disabled at any time as part of exposed FHERC20 hooks.

### 3. Existing ERC20 transfer functions revert.

`mint`, `burn`, `transfer` functions revert by default. This breaks backwards compatibility in favor of preventing an FHERC20 from accidentally being treated and acted upon as if it were a standard ERC20. These functions have been superseded by `enc` prefixed functions, including `encMint`, `encBurn` and `encTransfer` (more on `encTransfer` below).

Breaking backwards compatibility here works to prevent the `indicatedBalance`s from being unintentionally interpreted and used as a real balance by existing smart contracts.

As an example, a user trying to deploy liquidity on UniSwap using an FHERC20 will find that their transaction reverts, as `transfer` reverts when the `UniV2Pair` contract calls it. This prevents the FHERC20 from unintentionally being treated as an ERC20 (with a balance between 0.0000 and 0.9999).

### 4. Removal of allowances.

Allowances in ERC20 tokens are a necessary way to permit smart contracts to withdraw a user's funds. The `approve` function is necessary to grant permission to a smart contract to withdraw a users funds, however with the introduction of EIP712, permission can be granted by another method. Allowances have been removed from the FHERC20 standard, as a change in a user's allowance reveals how much of a user's encrypted balance has been transferred. As a result, allowances will have to be encrypted to preserve the confidentiality of the encrypted balances. This introduces the necessity for additional FHE operations.

The FHERC20 standard instead uses only EIP712 permissions as the exclusive way to grant access to funds. The existing ERC20 transfer function has been split into `transfer` and `transferFrom`. `transfer` is only callable by the owner of the funds being transferred. `transferFrom` function can be called by any user or contract, but requires a valid EIP712 permission to be included specifying the maximum amount that can be transferred in the current transaction. The permission does not grant future access to funds, regardless of the relationship (greater than, less than, or equal) between the permitted amount and the transferred amount.

## Additional Standards

The FHERC20 contract is designed as the core standard, however it is being released along side EncryptionWrappedFHERC20, which is a wrapping standard for an FHERC20 around an underlying existing ERC20. As an example, `wETH` is an ERC20, but can be wrapped into an encrypted FHERC20 as an EncryptionWrappedFHERC20 named eETH. In this case, the eETH contract exposes an `encrypt` function that withdraws `wETH` from an address, stores that `wETH` in the `eETH` contract, and `encMint`s the appropriate amount of encrypted balance for the user. A `decrypt` function is also exposed which performs the reciprocal action, burning `eETH` and sending `wETH` back to the users address.

In its simplest form `EncryptionWrappedFHERC20` holds the cleartext ERC20 funds within itself while the encrypted funds exist. There are situations in which the ERC20 may want to be handled differently (for example to generate yield elsewhere in a rebasing FHERC20). The hooks `_encryptHandleCleartextERC20` and `_decryptHandleCleartextERC20` provide an interface to manage the underlying cleartext ERC20 during the `encrypt`ing and `decrypt`ing functions.
