# sol-anchor-zig Roadmap

## ✅ v3.2.78 - Typed Constraint Overloads + Hex Bytes

- [x] Add pubkey overloads for typed constraints
- [x] Add bytesFromHex helper for typed constraints
- [x] Update docs and tests

## ✅ v3.2.77 - Typed Constraint Pubkey Values

- [x] Add pubkeyValue/pubkeyBytes helpers to typed constraints
- [x] Add pubkey_bytes literal parsing
- [x] Update docs and tests

## ✅ v3.2.76 - Typed Constraint Builder Enhancements

- [x] Add pubkey literal helper for typed constraints
- [x] Add asInt/asBytes helpers for explicit type assertions
- [x] Update docs and tests

## ✅ v3.2.75 - Typed Constraint Builder + CPI Signed Reset

- [x] Add typed constraint builder API
- [x] Add signed reset helpers for CPI context
- [x] Update docs and tests

## ✅ v3.2.74 - Constraint CI Helpers + CPI Remaining Reset

- [x] Add ASCII case-insensitive constraint helpers
- [x] Add reset + append + invoke helpers for CPI context
- [x] Update docs and tests

## ✅ v3.2.73 - Constraint Expr + CPI Context Extensions

- [x] Add constraint helper functions (contains/is_empty/min/max/clamp)
- [x] Add remaining account collection with pooling support for CPI context
- [x] Update docs and tests

## ✅ v3.2.72 - Constraint Expr Helpers + CPI Context Ergonomics

- [x] Add arithmetic operators and helper functions to constraint expressions
- [x] Add inline remaining helpers to CPI context builder
- [x] Update docs and tests

## ✅ v3.2.71 - Batch Init Helpers

- [x] Add `createAccounts` batch wrapper for system program init
- [x] Add `createBatchIdempotent` for ATA setup
- [x] Update docs and examples

## ✅ v3.2.70 - Constraint Expr Extensions

- [x] Add short-circuit evaluation for logical operators
- [x] Update tests and docs

## ✅ v3.2.69 - CPI Context Builder

- [x] Add `CpiContext` and `CpiContextWithConfig`
- [x] Update docs and examples

## ✅ v3.2.68 - Sysvar Data Aliases

- [x] Add common SysvarData aliases (Clock/Rent/EpochSchedule/etc.)
- [x] Add sysvar id-only wrappers
- [x] Update docs and examples

## ✅ v3.2.67 - Transfer Checked Sugar

- [x] Add `transferCheckedWithMint` helper for token CPI
- [x] Update docs

## ✅ v3.2.66 - ATA Init/Payer Semantics

- [x] Add associated token CPI helpers
- [x] Add ATA init/if_needed support in typed DSL
- [x] Update docs and examples

## ✅ v3.2.65 - SPL Memo + Stake Wrappers

- [x] Add `anchor.memo` CPI helpers for memo program
- [x] Add `anchor.stake` CPI helpers for stake program
- [x] Add `StakeAccount` wrappers
- [x] Update docs and examples

## ✅ v3.2.64 - Token Helpers + SystemAccount + Sysvar Parsing

- [x] Add SPL token wrappers for TokenAccount/Mint
- [x] Add `anchor.token` CPI helpers for common token instructions
- [x] Add SystemAccount wrappers
- [x] Add SysvarData parsing wrapper
- [x] Update docs and examples

## ✅ v3.2.63 - Event Emission + Realloc Safety + Bumps Improvements

- [x] **Event Runtime Emission**: Add `ctx.emit()` and `emitEvent()` for Anchor-compatible event logging
  - New `event.zig` module with discriminator + Borsh serialization
  - Context.emit() method for convenient event emission
  - Events logged via `sol_log_data` syscall
- [x] **Realloc Safety Fixes**: Critical security improvements to account reallocation
  - Add `PayerRequired` error when growing accounts without payer
  - Add `ReallocIncreaseTooLarge` error for 10KB single-increase limit (matches Solana runtime)
  - Fix silent failure when payer is null during rent-requiring growth
- [x] **Bumps Storage Improvements**: Enhanced PDA bump management
  - Increase `MAX_BUMPS` from 16 to 32 for complex programs
  - Replace simple polynomial hash with FNV-1a 64-bit for better collision resistance
- [x] **PDA/Seeds Automation**: Runtime seed resolution and validation
  - Add `loadAccountsWithDependencies` for seedAccount/seedField/seedBump resolution
  - Validate PDA addresses using runtime seed slices

## ✅ v3.2.62 - InterfaceProgram Unchecked

- [x] Add InterfaceProgramAny/InterfaceProgramUnchecked helpers
- [x] Update docs and tests

## ✅ v3.2.61 - Interface Meta Merge

- [x] Add duplicate meta merge strategy
- [x] Update docs and tests

## ✅ v3.2.60 - Interface Rent Exempt

- [x] Add rent_exempt checks for InterfaceAccount/InterfaceAccountInfo
- [x] Update docs and tests

## ✅ v3.2.59 - Interface/CPI Invoke + Executable + Overrides

- [x] Add executable checks for InterfaceAccount/InterfaceAccountInfo
- [x] Add AccountMeta override wrapper
- [x] Add invoke/invokeSigned helpers
- [x] Update docs and tests

## ✅ v3.2.58 - Interface/CPI AccountMeta Support

- [x] Accept AccountMeta inputs for Interface CPI
- [x] Update docs and tests

## ✅ v3.2.57 - Interface/CPI Extensions

- [x] Add InterfaceAccountInfo wrapper
- [x] Add remaining accounts support in Interface CPI builder
- [x] Update docs and tests

## ✅ v3.2.56 - Interface + CPI Helpers

- [x] Add InterfaceProgram/InterfaceAccount wrappers
- [x] Add Interface CPI instruction builder
- [x] Update docs and tests

## ✅ v3.2.53 - Program Entry Dispatch

- [x] Comptime dispatch by instruction discriminator
- [x] Fallback handler support
- [x] Optional error mapping to ProgramError

## ✅ v3.2.54 - AccountLoader (Zero-Copy)

- [x] Add AccountLoader API for zero-copy access

## ✅ v3.2.55 - LazyAccount

- [x] Add LazyAccount API for on-demand deserialization

## ✅ v3.2.52 - Constraint Expr Expansion

- [x] Expand constraint expression parsing for boolean/comparison ops

## ✅ v3.2.51 - AccountsDerive Program Auto Bindings (Typed)

- [x] Auto-bind Program fields by alias name

## ✅ v3.2.50 - AccountsDerive Token Alias Expansion

- [x] Expand token/mint authority alias inference

## ✅ v3.2.49 - Anchor Associated Token Constraint Runtime

- [x] Validate ATA address derivation and token owner

## ✅ v3.2.48 - Anchor Token/Mint Constraint Runtime

- [x] Validate token account state for token constraints
- [x] Validate mint state for mint constraints
- [x] Validate token/mint program owner constraints

## ✅ v3.2.47 - AccountsDerive Program Auto Bindings (Extended)

- [x] Add auto bindings for compute budget/address lookup table/ed25519/secp256/vote/feature gate
- [x] Extend AccountsDerive tests and docs

## ✅ v3.2.46 - Anchor Zero/Space/Dup Constraints

- [x] Enforce zero constraint via discriminator check
- [x] Enforce explicit space constraint with exact size
- [x] Reject duplicate mutable accounts without dup

## ✅ v3.0.4 - Anchor IDL + Zig Client

- [x] IDL JSON generation
- [x] Zig client codegen

## ✅ v3.1.2 - Anchor Account Attrs

- [x] Account attribute DSL
- [x] Account attrs example

## ✅ v3.1.1 - Anchor Event Index Rules

- [x] Event index limit (<=4)
- [x] Multi-index tests

## ✅ v3.1.0 - Anchor Event Index

- [x] eventField wrapper
- [x] IDL event index output

## ✅ v3.0.9 - Anchor Constraint DSL

- [x] Constraint expression helper
- [x] IDL constraint output

## ✅ v3.0.8 - Anchor IDL Output

- [x] IDL file output helper
- [x] Build step for IDL generation

## ✅ v3.0.7 - Anchor Zig Client (High-level)

- [x] ProgramClient RPC wrapper
- [x] Account decode helpers
- [x] Client module integration

## ✅ v3.0.6 - Anchor IDL Extensions

- [x] IDL events/constants/metadata
- [x] Account constraint hints

## ✅ v3.0.5 - Anchor Comptime Derives

- [x] Accounts/Event DSL helpers
- [x] Documentation updates

## ⏳ v3.0.1 - Anchor Extraction (Monorepo)

- [x] Build as standalone subpackage in `anchor/`
- [x] Path dependency on `solana_program_sdk`
- [ ] CI workflow for anchor tests

## ✅ v3.0.0 - Anchor Framework Core

Phases 1-3 implemented and tracked in stories:
- `stories/v3.0.0-anchor-phase1.md`
- `stories/v3.0.0-anchor-phase2.md`
- `stories/v3.0.0-anchor-phase3.md`
