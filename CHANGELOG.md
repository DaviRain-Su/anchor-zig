# Changelog

All notable changes to sol-anchor-zig will be documented in this file.

### Session 2026-01-17-035

**Date**: 2026-01-17
**Goal**: Add TS end-to-end mint + ATA example

#### Completed Work
1. Added TS client that creates mint + ATA and invokes program
2. Updated docs tracking

#### Test Results
- Not run in this session

### Session 2026-01-17-034

**Date**: 2026-01-17
**Goal**: Expand ATA mint/transfer example

#### Completed Work
1. Added validator/deploy steps and TS client walkthrough
2. Added PDA authority variant for token transfer
3. Updated docs tracking

#### Test Results
- Not run in this session

### Session 2026-01-17-033

**Date**: 2026-01-17
**Goal**: Add token CPI example + bootstrap script docs

#### Completed Work
1. Added ATA init + mintTo + transferChecked example doc
2. Added bootstrap project script and updated example steps
3. Updated docs index and references

#### Test Results
- Not run in this session

### Session 2026-01-17-032

**Date**: 2026-01-17
**Goal**: Add PDA + Token CPI example and standardize doc steps

#### Completed Work
1. Added PDA + Token CPI end-to-end example doc
2. Added docs index links and example references
3. Updated Counter example to use standard workflow scripts

#### Test Results
- Not run in this session

### Session 2026-01-17-031

**Date**: 2026-01-17
**Goal**: Split DSL docs and add end-to-end example

#### Completed Work
1. Added docs index and split DSL/CPI/IDL topics
2. Added end-to-end Counter example guide
3. Updated DSL usage entry point links

#### Test Results
- Not run in this session

### Session 2026-01-17-030

**Date**: 2026-01-17
**Goal**: Expand DSL usage documentation

#### Completed Work
1. Added comprehensive DSL/framework usage guide
2. Linked the guide from README

#### Test Results
- Not run in this session

### Session 2026-01-15-029

**Date**: 2026-01-15
**Goal**: Add typed constraint overloads and hex bytes helper

#### Completed Work
1. Added pubkey overloads for typed constraints
2. Added bytesFromHex helper for typed constraints
3. Updated docs and tests

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-028

**Date**: 2026-01-15
**Goal**: Add typed constraint pubkey helpers

#### Completed Work
1. Added pubkeyValue/pubkeyBytes helpers for typed constraints
2. Added pubkey_bytes literal parsing
3. Updated docs and tests

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-027

**Date**: 2026-01-15
**Goal**: Add typed constraint pubkey literals and type assertions

#### Completed Work
1. Added pubkey literal helper for typed constraints
2. Added as_int/as_bytes helpers for explicit type assertions
3. Updated docs and tests

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-026

**Date**: 2026-01-15
**Goal**: Fix anchor test compilation after Account.Info changes

#### Completed Work
1. Added Rent.Data id for sysvar wrappers
2. Removed obsolete rent_epoch field from anchor test fixtures

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ./solana-zig/zig build test --summary all`

### Session 2026-01-15-025

**Date**: 2026-01-15
**Goal**: Add typed constraint builder and CPI signed reset helpers

#### Completed Work
1. Added typed constraint builder API with fluent expression helpers
2. Added signed reset helpers for CPI context
3. Updated docs and tests

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-024

**Date**: 2026-01-15
**Goal**: Add constraint CI helpers and CPI remaining reset

#### Completed Work
1. Added ASCII case-insensitive helpers for constraint expressions
2. Added reset + append + invoke helpers for CPI context
3. Updated docs and tests

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-023

**Date**: 2026-01-15
**Goal**: Extend constraint helpers and CPI remaining pooling

#### Completed Work
1. Added constraint helpers: contains/is_empty/min/max/clamp
2. Added pooled remaining account collection for CPI context
3. Updated docs and tests

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-022

**Date**: 2026-01-15
**Goal**: Extend constraint expressions and CPI builder ergonomics

#### Completed Work
1. Added arithmetic operators and helper functions to constraint expressions
2. Added inline remaining helpers to CPI context builder
3. Updated docs and tests

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-021

**Date**: 2026-01-15
**Goal**: Add batch init helpers

#### Completed Work
1. Added batch init configs and helpers for system account initialization
2. Added batch ATA init helper for associated token accounts
3. Updated docs and exports

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-020

**Date**: 2026-01-15
**Goal**: Extend constraint expression evaluation

#### Completed Work
1. Added short-circuit evaluation for logical operators
2. Added tests for optional access guards

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-019

**Date**: 2026-01-15
**Goal**: Add CPI context builder

#### Completed Work
1. Added `CpiContext` and `CpiContextWithConfig`
2. Updated docs and examples

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-018

**Date**: 2026-01-15
**Goal**: Add sysvar data aliases

#### Completed Work
1. Added pre-defined SysvarData aliases (Clock/Rent/EpochSchedule/etc.)
2. Added sysvar id-only wrappers
3. Updated docs and examples

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-017

**Date**: 2026-01-15
**Goal**: Add transferChecked DSL sugar

#### Completed Work
1. Added `transferCheckedWithMint` helper
2. Updated docs

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-016

**Date**: 2026-01-15
**Goal**: Add ATA init/payer semantics

#### Completed Work
1. Added associated token CPI helpers
2. Added ATA init/if_needed config + validation in TokenAccount/typed DSL
3. Updated docs and examples

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-015

**Date**: 2026-01-15
**Goal**: Improve token CPI error detail

#### Completed Work
1. Added `InvokeFailedWithCode` branch to `TokenCpiError`
2. Updated token CPI helpers and examples to surface error codes

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-014

**Date**: 2026-01-15
**Goal**: Add Memo/Stake wrappers and CPI helpers

#### Completed Work
1. Added `anchor.memo` CPI helpers for SPL Memo program
2. Added `anchor.stake` CPI helpers for SPL Stake program
3. Added StakeAccount wrapper and DSL markers
4. Updated docs and examples

#### Test Results
- `./solana-zig/zig build test --summary all`

### Session 2026-01-15-012

**Date**: 2026-01-15
**Goal**: Add event emission, realloc safety, and PDA seed automation

#### Completed Work
1. Added event emission helpers with runtime logging support
2. Hardened realloc with payer requirement and 10KB growth limit
3. Added runtime seed resolution with PDA validation helpers
4. Updated docs, exports, and examples

#### Test Results
- Not run in this session (user-reported: anchor 195/195, sdk 363/363)

### Session 2026-01-15-013

**Date**: 2026-01-15
**Goal**: Add token helpers, system account wrappers, and sysvar parsing

#### Completed Work
1. Added SPL token wrappers and token CPI helpers
2. Added SystemAccount wrappers
3. Added SysvarData parsing helper
4. Updated docs and examples

#### Test Results
- Not run in this session

### Session 2026-01-13-011

**Date**: 2026-01-13
**Goal**: Add InterfaceProgram unchecked variants

#### Completed Work
1. Added InterfaceProgramAny and InterfaceProgramUnchecked wrappers
2. Exported helpers and updated docs
3. Added tests for executable/unchecked behavior

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-010

**Date**: 2026-01-13
**Goal**: Add meta merge strategy for interface CPI

#### Completed Work
1. Added meta merge strategy for Interface CPI builders
2. Applied merge to instruction metas and invoke infos
3. Updated docs and roadmap tracking

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-009

**Date**: 2026-01-13
**Goal**: Add rent_exempt checks for interface accounts

#### Completed Work
1. Added rent_exempt config for InterfaceAccount/InterfaceAccountInfo
2. Enforced rent exemption via Rent.getOrDefault
3. Updated docs and roadmap tracking

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-008

**Date**: 2026-01-13
**Goal**: Extend interface CPI invoke helpers

#### Completed Work
1. Added executable checks for InterfaceAccount/InterfaceAccountInfo
2. Added AccountMeta override wrapper for CPI metas
3. Added invoke/invokeSigned helpers and updated docs

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-007

**Date**: 2026-01-13
**Goal**: Add AccountMeta support to interface CPI

#### Completed Work
1. Allowed AccountMeta inputs for Interface CPI accounts
2. Allowed AccountMeta slices for remaining accounts
3. Updated docs and roadmap tracking

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-006

**Date**: 2026-01-13
**Goal**: Extend interface CPI helpers

#### Completed Work
1. Added `InterfaceAccountInfo` wrapper
2. Added remaining accounts support in Interface CPI builder
3. Updated docs and roadmap tracking

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-005

**Date**: 2026-01-13
**Goal**: Add interface accounts and CPI helpers

#### Completed Work
1. Added `InterfaceProgram`/`InterfaceAccount` wrappers
2. Added `Interface` CPI instruction builder
3. Updated docs and roadmap tracking

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-002

**Date**: 2026-01-13
**Goal**: Add typed program entry dispatch

#### Completed Work
1. Added `ProgramEntry` for discriminator-based dispatch
2. Added fallback handler support and optional error mapping
3. Added tests and documentation updates

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-003

**Date**: 2026-01-13
**Goal**: Add AccountLoader zero-copy access

#### Completed Work
1. Added `AccountLoader` for zero-copy account access
2. Exported loader from anchor root module
3. Updated docs and roadmap tracking

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-004

**Date**: 2026-01-13
**Goal**: Add LazyAccount on-demand deserialization

#### Completed Work
1. Added `LazyAccount` with cached Borsh decoding
2. Exported LazyAccount from anchor root module
3. Updated docs and roadmap tracking

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-13-001

**Date**: 2026-01-13
**Goal**: Expand constraint expression parsing

#### Completed Work
1. Expanded constraint expression parsing with boolean/comparison ops
2. Added tests and documentation updates

#### Test Results
- `ZIG_GLOBAL_CACHE_DIR=.zig-cache ZIG_LOCAL_CACHE_DIR=.zig-cache ../solana-zig/zig build test --summary all`

### Session 2026-01-12-001

**Date**: 2026-01-12
**Goal**: Extract anchor into monorepo subpackage

#### Completed Work
1. Initialized `anchor/` subpackage structure and build files
2. Migrated anchor sources to `anchor/src`
3. Updated imports to use `solana_program_sdk`
4. Removed noisy rent log via `Rent.getOrDefault()`
5. Re-exported SDK as `anchor.sdk`
6. Updated stories and roadmap for new layout

#### Test Results
- `zig build test` 152 passed
