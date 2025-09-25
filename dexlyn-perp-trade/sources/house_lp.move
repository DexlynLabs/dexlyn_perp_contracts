module dexlyn::house_lp {
    use std::signer::address_of;
    use std::option;
    use std::string;
    use aptos_std::event::{Self};
    use aptos_std::type_info::{Self, TypeInfo};
    use supra_framework::timestamp;
    use supra_framework::supra_account;
    use supra_framework::account;
    use supra_framework::account::SignerCapability;
    use supra_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
    use dexlyn::vault_type::HouseLPVault;

    use dexlyn::fee_distributor;
    use dexlyn::safe_math::{safe_mul_div};
    use dexlyn::vault;
    use dexlyn::vault_type;

    friend dexlyn::trading;

    const DXLP_DECIMALS: u8 = 6;
    const FEE_POINTS_DIVISOR: u64 = 1000000;
    const WITHDRAW_DIVISION_DIVISOR: u64 = 1000000;
    const LP_PRICE_PRECISION: u64 = 1000000;
    const BREAK_PRECISION: u64 = 100000;
    const DAY_SECONDS: u64 = 86400;
    const DEFAULT_DEPOSIT_AMOUNT: u64 = 1000000;
    const MININUM_REDEEM_REGISTER_AMOUNT: u64 = 100000;

    // <-- ERROR CODE ----->
    /// When signer is not owner of module
    const E_NOT_AUTHORIZED: u64 = 0;
    /// When over withdrawal limit
    const E_WITHDRAW_LIMIT: u64 = 1;
    /// When the deposit amount is too small and the DXLP mint amount is 0
    const E_DEPOSIT_TOO_SMALL: u64 = 2;
    /// When Houselp runs out of the collateral it contains
    const E_HOUSE_LP_AMOUNT_NOT_ENOUGH: u64 = 3;
    /// When the asset register with house_lp is not a coin
    const E_COIN_NOT_INITIALIZED: u64 = 4;
    /// When MDD crosses the hard break threshold
    const E_HARD_BREAK_EXCEEDED: u64 = 5;
    /// When DXLP Already initialized, since only 1 collateral asset will be use for now
    const E_DXLP_ALREADY_INITIALIZED: u64 = 6;
    /// When cannot redeem
    const E_UNREDEEMABLE: u64 = 7;
    /// When cannot cancel
    const E_UNCANCELABLE: u64 = 8;
    /// When less than minimum redeem amount
    const E_MINIMUM_REDEEM_LIMIT: u64 = 9;
    /// When fee resource is not initialised
    const E_FEE_RESOURCE_MISSING: u64 = 10;

    /// Seed for resource account
    const SEED_FOR_FEES_LP_RESOURCE: vector<u8> = b"DEXLYN::PERP::LP_FEES_RESOURCE_SEED";

    // <-- Fee Type ------->
    const T_FEE_TYPE_DEPOSIT_FEE: u64 = 1;
    const T_FEE_TYPE_WITHDRAW_FEE: u64 = 2;
    const T_FEE_TYPE_PNL_FEE: u64 = 3;
    const T_FEE_TYPE_TRADING_FEE: u64 = 4;

    struct DXLP<phantom AssetT> {}

    #[resource_group_member(group = supra_framework::object::ObjectGroup)]
    struct LPTokenFeesResource has key {
        signer_cap: SignerCapability
    }

    /// Struct that stores the capability and withdraw_division associated with DXLP.
    struct HouseLPConfig<phantom AssetT> has key {
        mint_capability: MintCapability<DXLP<AssetT>>,
        burn_capability: BurnCapability<DXLP<AssetT>>,
        freeze_capability: FreezeCapability<DXLP<AssetT>>,
        withdraw_division: u64,  // 1000000 = 100% default 200000
        minimum_deposit: u64,
        soft_break: u64, // 100000 = 100%
        hard_break: u64 // 100000 = 100%
    }

    /// Struct to store the fee percentage for each asset
    struct HouseLP<phantom AssetT> has key {
        deposit_fee: u64,  // 1000000 = 100% default 0
        withdraw_fee: u64,  // 1000000 = 100% default 0
        highest_price: u64
    }

    struct RedeemPlan<phantom AssetT> has key {
        dxlp: Coin<DXLP<AssetT>>,
        started_at: u64,
        redeem_count: u64,
        initial_amount: u64,
        withdraw_amount: u64
    }

    #[event]
    struct DepositEvent has drop, store {
        /// deposit asset type
        asset_type: TypeInfo,
        /// address of deposit user.
        user: address,
        /// amount of deposit asset
        deposit_amount: u64,
        /// amount of mint asset
        mint_amount: u64,
        /// amount of deposit fee
        deposit_fee: u64,
        /// timestamp
        timestamp: u64,
        /// total vault balance
        vault_balance: u64,
        /// total DXLP supply
        lp_supply: u64,
        /// Deposite auto index
        id: u64
    }

    #[event]
    struct FeeEvent has drop, store {
        /// deposit fee type
        fee_type: u64,
        /// deposit asset type
        asset_type: TypeInfo,
        /// amount of fee
        amount: u64,
        /// sign of amount true = positive, false = negative
        amount_sign: bool,
        /// timestamp
        timestamp: u64,
        /// total vault balance
        vault_balance: u64,
        /// total DXLP supply
        lp_supply: u64,
        /// Deposite auto index
        id: u64
    }

    #[event]
    struct RedeemEvent has drop, store {
        /// user address
        user: address,
        /// withdraw asset type
        asset_type: TypeInfo,
        /// burn amount
        burn_amount: u64,
        /// withdraw amount
        withdraw_amount: u64,
        /// left redeem amount
        redeem_amount_left: u64,
        /// amount of withdraw fee
        withdraw_fee: u64,
        /// start at second
        started_at_sec: u64,
        /// timestamp
        timestamp: u64,
        /// total vault balance
        vault_balance: u64,
        /// total DXLP supply
        lp_supply: u64,
        /// Deposite auto index
        id: u64
    }

    #[event]
    struct RedeemCancelEvent has drop, store {
        /// user address
        user: address,
        /// return DXLP amount
        return_amount: u64,
        /// initial redeem amount
        initial_amount: u64,
        /// start at second
        started_at_sec: u64,
        /// timestamp
        timestamp: u64,
        /// total vault balance
        vault_balance: u64,
        /// total DXLP supply
        lp_supply: u64,
        /// Deposite auto index
        id: u64
    }

    struct EventIndexes has key{
        deposit_index: u64,
        redeem_index: u64,
        fee_index: u64,
        redeem_cancel_index: u64
    }

    /// register function, Need to call it through the entry function per collateral.
    /// @Type Parameters
    /// AssetT: collateral type
    public fun register<AssetT>(host: &signer) {
        let host_addr = address_of(host);
        assert!(@dexlyn == host_addr, E_NOT_AUTHORIZED);
        assert!(coin::is_coin_initialized<AssetT>(), E_COIN_NOT_INITIALIZED);

        if (!exists<LPTokenFeesResource>(host_addr)) {
            let (_resource_obj, signer_cap) = account::create_resource_account(host, SEED_FOR_FEES_LP_RESOURCE);
            move_to(host, LPTokenFeesResource {
                signer_cap: signer_cap
            });
        };

        if (!exists<HouseLPConfig<AssetT>>(host_addr)) {
            let (burn_capability, freeze_capability, mint_capability) = coin::initialize<DXLP<AssetT>>(
                host,
                string::utf8(b"Dexlyn LP"),
                string::utf8(b"DXLP"),
                DXLP_DECIMALS,
                true,
            );
            move_to(host, HouseLPConfig<AssetT> {
                mint_capability,
                burn_capability,
                freeze_capability,
                withdraw_division: 200000,  // 20%
                minimum_deposit: DEFAULT_DEPOSIT_AMOUNT,
                soft_break: 20000,  // 20%
                hard_break: 30000,  // 30%
            });
        };
        if (!exists<HouseLP<AssetT>>(host_addr)) {
            move_to(host, HouseLP<AssetT> {
                deposit_fee: 0,
                withdraw_fee: 1000,  // 0.1%
                highest_price: 0,
            });
        };
        if (!exists<EventIndexes>(host_addr)) {
            // creating event indexes resource to assign index to event for uniqueness
            move_to(host, EventIndexes {
                deposit_index : 0,
                redeem_index : 0,
                fee_index : 0,
                redeem_cancel_index : 0,
            });
        };
    }

    public fun deposit_without_mint<AssetT>(_user: &signer, _amount: u64) acquires HouseLP, EventIndexes {
        assert!(address_of(_user) == @dexlyn, E_NOT_AUTHORIZED);

        let deposit_coin = coin::withdraw<AssetT>(_user, _amount);
        // Put the deposited collateral into the vault.
        vault::deposit_vault<vault_type::HouseLPVault, AssetT>(deposit_coin);
        update_highest_price<AssetT>();
        
        let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);

        event::emit(
            DepositEvent {
                asset_type: type_info::type_of<AssetT>(),
                user: address_of(_user),
                deposit_amount: _amount,
                mint_amount: 0,
                deposit_fee: 0,
                timestamp: timestamp::now_seconds(),
                vault_balance: vault_balance, 
                lp_supply: lp_supply,
                id: event_indexes.deposit_index
            }
        );
        event_indexes.deposit_index = event_indexes.deposit_index + 1;
    }

    /// Functions to deposit collateral and receive DXLP
    /// @Type Parameters
    /// AssetT: collateral type
    public fun deposit<AssetT>(_user: &signer, _amount: u64) acquires HouseLPConfig, HouseLP, EventIndexes {
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        let house_lp = borrow_global_mut<HouseLP<AssetT>>(@dexlyn);
        let user_addr = address_of(_user);
        // If too small a value is deposited
        assert!(_amount >= house_lp_config.minimum_deposit, E_DEPOSIT_TOO_SMALL);
        let deposit_coin = coin::withdraw<AssetT>(_user, _amount);

        // Put the fees accumulated in fee_distributor into house_lp.
        deposit_trading_fee(fee_distributor::withdraw_fee_houselp_all<AssetT>());
        // Put the deposited collateral into the vault.
        vault::deposit_vault<vault_type::HouseLPVault, AssetT>(deposit_coin);

        // mint DXLP
        if (!coin::is_account_registered<DXLP<AssetT>>(user_addr)) {
            coin::register<DXLP<AssetT>>(_user);
        };

        let house_lp_coin_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let fee = safe_mul_div(_amount, house_lp.deposit_fee, FEE_POINTS_DIVISOR);
        _amount = _amount - fee;
        let mintAmount: u64;
        if (supply == 0) {
            mintAmount = _amount;
        } else {
            mintAmount = safe_mul_div(supply, _amount, (house_lp_coin_balance - (_amount + fee)));
        };
        // If too small a value is deposited and the amount of mint is zero, assert.
        assert!(mintAmount > 0, E_DEPOSIT_TOO_SMALL);
        let dxlp = coin::mint<DXLP<AssetT>>(mintAmount, &house_lp_config.mint_capability);
        coin::deposit(user_addr, dxlp);

        update_highest_price<AssetT>();
        let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);

        // emit event
        if (fee > 0) {
            event::emit(
                FeeEvent {
                    fee_type: T_FEE_TYPE_DEPOSIT_FEE,
                    asset_type: type_info::type_of<AssetT>(),
                    amount: fee,
                    amount_sign: true,
                    timestamp: timestamp::now_seconds(),
                    vault_balance: vault_balance, 
                    lp_supply: lp_supply,
                    id: event_indexes.fee_index
                }
            );
            event_indexes.fee_index = event_indexes.fee_index + 1;
        };
        event::emit(
            DepositEvent {
                asset_type: type_info::type_of<AssetT>(),
                user: user_addr,
                deposit_amount: _amount,
                mint_amount: mintAmount,
                deposit_fee: fee,
                timestamp: timestamp::now_seconds(),
                vault_balance: vault_balance, 
                lp_supply: lp_supply,
                id: event_indexes.deposit_index
            }
        );
        event_indexes.deposit_index = event_indexes.deposit_index + 1;
    }

    public fun register_redeem_plan<AssetT>(_user: &signer, _amount: u64) {
        assert!(_amount >= MININUM_REDEEM_REGISTER_AMOUNT, E_MINIMUM_REDEEM_LIMIT);
        move_to(_user, RedeemPlan<AssetT> {
            dxlp: coin::withdraw<DXLP<AssetT>>(_user, _amount),
            started_at: timestamp::now_seconds(),
            redeem_count: 0,
            initial_amount: _amount,
            withdraw_amount: 0
        });
    }

    public fun redeem<AssetT>(_user: &signer)
    acquires RedeemPlan, HouseLPConfig, HouseLP, EventIndexes, LPTokenFeesResource {
        if (!exists<LPTokenFeesResource>(@dexlyn)) {
            abort E_FEE_RESOURCE_MISSING
        };
        let lp_fee_resource = borrow_global<LPTokenFeesResource>(@dexlyn);
        let lp_resource_signer = account::create_signer_with_capability(&lp_fee_resource.signer_cap);
        let redeem_plan = borrow_global_mut<RedeemPlan<AssetT>>(address_of(_user));
        assert!((timestamp::now_seconds() - redeem_plan.started_at) / DAY_SECONDS == redeem_plan.redeem_count, E_UNREDEEMABLE);

        // Put the fees accumulated in fee_distributor into house_lp.
        deposit_trading_fee(fee_distributor::withdraw_fee_houselp_all<AssetT>());

        // extract DXLP
        let dxlp = coin::extract(&mut redeem_plan.dxlp, redeem_plan.initial_amount / 5);
        if (redeem_plan.redeem_count == 4) {
             // Extract all remaining DXLP
            coin::merge(&mut dxlp, coin::extract_all(&mut redeem_plan.dxlp));
        };
        let dxlp_amount = coin::value(&dxlp);

        // calculate withdraw amount
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        let house_lp = borrow_global_mut<HouseLP<AssetT>>(@dexlyn);
        let coin_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let return_amount = safe_mul_div(coin_balance, dxlp_amount, supply);
        let fee = safe_mul_div(return_amount, house_lp.withdraw_fee, FEE_POINTS_DIVISOR);
        return_amount = return_amount - fee;

        //calculate dxlp that need to be extract from resource as it contains fee portion for this withdraw
        let fees_total_dxlp = coin::balance<DXLP<AssetT>>(address_of(&lp_resource_signer));
        // No need to check for substraction underflow as supply > fess_total_dxlp
        let lp_pool_supply = supply - fees_total_dxlp;
        let fee_percentage_for_dxlp = safe_mul_div(dxlp_amount , FEE_POINTS_DIVISOR, lp_pool_supply);
        let dxlp_of_fees = safe_mul_div(fees_total_dxlp, fee_percentage_for_dxlp,  FEE_POINTS_DIVISOR);
        
        let fees_dxlp = coin::withdraw<DXLP<AssetT>>(&lp_resource_signer, dxlp_of_fees);
        let fees_amount = safe_mul_div(coin_balance, dxlp_of_fees, supply);
        return_amount = return_amount + fees_amount;

        //calculate dxlp for withrawal fee
        let dxlp_to_submit_for_fees = safe_mul_div(supply , fee , coin_balance);
        let dxlp_to_deposit_to_resource = coin::extract(&mut dxlp, dxlp_to_submit_for_fees);
        supra_account::deposit_coins(address_of(&lp_resource_signer), dxlp_to_deposit_to_resource);
        coin::merge(&mut dxlp, fees_dxlp);        

        assert!(coin_balance >= return_amount, E_HOUSE_LP_AMOUNT_NOT_ENOUGH);

        // withdraw asset
        let withdraw_coin = vault::withdraw_vault<vault_type::HouseLPVault, AssetT>(return_amount);
        let withdraw_amount = coin::value(&withdraw_coin);
        redeem_plan.withdraw_amount = redeem_plan.withdraw_amount + withdraw_amount;
        supra_account::deposit_coins(address_of(_user), withdraw_coin);
        redeem_plan.redeem_count = redeem_plan.redeem_count + 1;

        // burn DXLP
        coin::burn(dxlp, &house_lp_config.burn_capability);
        update_highest_price<AssetT>();
        let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);

        event::emit(
            RedeemEvent {
                user: address_of(_user),
                asset_type: type_info::type_of<AssetT>(),
                burn_amount: dxlp_amount,
                withdraw_amount,
                redeem_amount_left: coin::value(&redeem_plan.dxlp),
                withdraw_fee: fee,
                started_at_sec: redeem_plan.started_at,
                timestamp: timestamp::now_seconds(),
                vault_balance: vault_balance, 
                lp_supply: lp_supply,
                id: event_indexes.redeem_index
            }
        );
        event_indexes.redeem_index = event_indexes.redeem_index + 1;

        if (coin::value(&redeem_plan.dxlp) == 0) {
            drop_redeem_plan(move_from<RedeemPlan<AssetT>>(address_of(_user)));
        };
    }

    public fun cancel_redeem_plan<AssetT>(_user: &signer)
    acquires RedeemPlan, EventIndexes {
        let redeem_plan = move_from<RedeemPlan<AssetT>>(address_of(_user));
        assert!((timestamp::now_seconds() - redeem_plan.started_at) / DAY_SECONDS >= redeem_plan.redeem_count, E_UNCANCELABLE);
        let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);

        event::emit(
            RedeemCancelEvent {
                user: address_of(_user),
                return_amount: coin::value(&redeem_plan.dxlp),
                initial_amount: redeem_plan.initial_amount,
                started_at_sec: redeem_plan.started_at,
                timestamp: timestamp::now_seconds(),
                vault_balance: vault_balance, 
                lp_supply: lp_supply,
                id: event_indexes.redeem_index
            }
        );
        event_indexes.redeem_index = event_indexes.redeem_index + 1;
        if (coin::value(&redeem_plan.dxlp) > 0) {
            supra_account::deposit_coins(address_of(_user), coin::extract_all(&mut redeem_plan.dxlp));
        };
        drop_redeem_plan(redeem_plan);
    }

    public fun drop_redeem_plan<AssetT>(_redeem_plan: RedeemPlan<AssetT>) {
        let RedeemPlan<AssetT> {
            dxlp,
            started_at: _,
            redeem_count: _,
            initial_amount: _,
            withdraw_amount: _
        } = _redeem_plan;
        coin::destroy_zero(dxlp);
    }

    /// Transfer losses from trading to house_lp
    /// @Type Parameters
    /// AssetT: collateral type
    public (friend) fun pnl_deposit_to_lp<AssetT>(coin: Coin<AssetT>) acquires HouseLP, HouseLPConfig, EventIndexes {
        // Put the fees accumulated in fee_distributor into house_lp.
        deposit_trading_fee(fee_distributor::withdraw_fee_houselp_all<AssetT>());
        let amount = coin::value(&coin);
        vault::deposit_vault<vault_type::HouseLPVault, AssetT>(coin);
        let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);
        if (amount > 0) {
            // emit event
            event::emit(
                FeeEvent {
                    fee_type: T_FEE_TYPE_PNL_FEE,
                    asset_type: type_info::type_of<AssetT>(),
                    amount,
                    amount_sign: true,
                    timestamp: timestamp::now_seconds(),
                    vault_balance: vault_balance, 
                    lp_supply: lp_supply,
                    id: event_indexes.fee_index
                }
            );
            event_indexes.fee_index = event_indexes.fee_index + 1;
        };
        update_highest_price<AssetT>();
        assert!(!check_hard_break_exceeded<AssetT>(), E_HARD_BREAK_EXCEEDED);
    }

    /// Withdraw profit from trading from house_lp
    /// @Type Parameters
    /// AssetT: collateral type
    public (friend) fun pnl_withdraw_from_lp<AssetT>(amount: u64): Coin<AssetT> acquires HouseLP, HouseLPConfig, EventIndexes {
        // Put the fees accumulated in fee_distributor into house_lp.
        deposit_trading_fee(fee_distributor::withdraw_fee_houselp_all<AssetT>());
        update_highest_price<AssetT>();
        let asset = vault::withdraw_vault<vault_type::HouseLPVault, AssetT>(amount);
        let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);
        if (amount > 0) {
            // emit event
            event::emit(
                FeeEvent {
                    fee_type: T_FEE_TYPE_PNL_FEE,
                    asset_type: type_info::type_of<AssetT>(),
                    amount,
                    amount_sign: false,
                    timestamp: timestamp::now_seconds(),
                    vault_balance: vault_balance, 
                    lp_supply: lp_supply,
                    id: event_indexes.fee_index
                }
            );
            event_indexes.fee_index = event_indexes.fee_index + 1;
        };
        assert!(!check_hard_break_exceeded<AssetT>(), E_HARD_BREAK_EXCEEDED);
        return asset
    }

    /// check mdd price exceed soft break
    public fun check_soft_break_exceeded<AssetT>(): bool acquires HouseLP, HouseLPConfig {
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        return get_mdd<AssetT>() > house_lp_config.soft_break
    }

    /// check mdd price exceed hard break
    public fun check_hard_break_exceeded<AssetT>(): bool acquires HouseLP, HouseLPConfig {
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        return get_mdd<AssetT>() > house_lp_config.hard_break
    }

    /// mdd = (highest price - current price) / highest price
    fun get_mdd<AssetT>(): u64 acquires HouseLP {
        let supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        if (supply == 0) {
            return 0
        };
        let dxlp_price = safe_mul_div(
            vault::vault_balance<HouseLPVault, AssetT>(),
            LP_PRICE_PRECISION,
            (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64)
        );
        let house_lp = borrow_global_mut<HouseLP<AssetT>>(@dexlyn);
        if (house_lp.highest_price == 0) {
            return BREAK_PRECISION
        };
        return safe_mul_div(
            house_lp.highest_price - dxlp_price,
            BREAK_PRECISION,
            house_lp.highest_price
        )
    }

    /// Deposit fee to house_lp
    fun deposit_trading_fee<AssetT>(coin: Coin<AssetT>) acquires EventIndexes {
        // emit event
        let coin_value = coin::value(&coin);
        vault::deposit_vault<vault_type::HouseLPVault, AssetT>(coin);
        if (coin_value > 0) {
            let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
            let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
            let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);
            event::emit(
                FeeEvent {
                    fee_type: T_FEE_TYPE_TRADING_FEE,
                    asset_type: type_info::type_of<AssetT>(),
                    amount: coin_value,
                    amount_sign: true,
                    timestamp: timestamp::now_seconds(),
                    vault_balance: vault_balance, 
                    lp_supply: lp_supply,
                    id: event_indexes.fee_index
                }
            );
            event_indexes.fee_index = event_indexes.fee_index + 1;
        };
    }

    /// Update highest price if needed
    fun update_highest_price<AssetT>() acquires HouseLP {
        let supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        if (supply == 0) {
            return
        };
        let dxlp_price = safe_mul_div(
            vault::vault_balance<HouseLPVault, AssetT>(),
            LP_PRICE_PRECISION,
            supply
        );
        let house_lp = borrow_global_mut<HouseLP<AssetT>>(@dexlyn);
        if (dxlp_price > house_lp.highest_price) {
            house_lp.highest_price = dxlp_price;
        };
    }

    /// @Type Parameters
    /// AssetT: collateral type
    public fun set_house_lp_deposit_fee<AssetT>(_host: &signer, _deposit_fee: u64) acquires HouseLP {
        assert!(@dexlyn == address_of(_host), E_NOT_AUTHORIZED);
        let house_lp = borrow_global_mut<HouseLP<AssetT>>(@dexlyn);
        house_lp.deposit_fee = _deposit_fee;
    }

    /// @Type Parameters
    /// AssetT: collateral type
    public fun set_house_lp_withdraw_fee<AssetT>(_host: &signer, _withdraw_fee: u64) acquires HouseLP {
        assert!(@dexlyn == address_of(_host), E_NOT_AUTHORIZED);
        let house_lp = borrow_global_mut<HouseLP<AssetT>>(@dexlyn);
        house_lp.withdraw_fee = _withdraw_fee;
    }

    public fun set_house_lp_withdraw_division<AssetT>(_host: &signer, _withdraw_division: u64) acquires HouseLPConfig {
        assert!(@dexlyn == address_of(_host), E_NOT_AUTHORIZED);
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        house_lp_config.withdraw_division = _withdraw_division;
    }

    public fun set_house_lp_minimum_deposit<AssetT>(_host: &signer, _minimum_deposit: u64) acquires HouseLPConfig {
        assert!(@dexlyn == address_of(_host), E_NOT_AUTHORIZED);
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        house_lp_config.minimum_deposit = _minimum_deposit;
    }

    public fun set_house_lp_soft_break<AssetT>(_host: &signer, _soft_break: u64) acquires HouseLPConfig {
        assert!(@dexlyn == address_of(_host), E_NOT_AUTHORIZED);
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        house_lp_config.soft_break = _soft_break;
    }

    public fun set_house_lp_hard_break<AssetT>(_host: &signer, _hard_break: u64) acquires HouseLPConfig {
        assert!(@dexlyn == address_of(_host), E_NOT_AUTHORIZED);
        let house_lp_config = borrow_global_mut<HouseLPConfig<AssetT>>(@dexlyn);
        house_lp_config.hard_break = _hard_break;
    }

    #[test_only]
    use supra_framework::supra_coin;

    #[test_only]
    use dexlyn::safe_math::exp;

    #[test_only]
    struct USDC has key {}

    #[test_only]
    struct FAIL_USDC has key {}

    #[test_only]
    const TEST_ASSET_DECIMALS: u8 = 6;

    #[test_only]
    struct AssetInfo<phantom AssetT> has key, store {
        burn_cap: BurnCapability<AssetT>,
        freeze_cap: FreezeCapability<AssetT>,
        mint_cap: MintCapability<AssetT>,
    }

    #[test_only]
    fun call_test_setting(host: &signer, supra_framework: &signer) acquires AssetInfo, HouseLPConfig, HouseLP {
        let host_addr = address_of(host);
        timestamp::set_time_has_started_for_testing(supra_framework);
        supra_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        timestamp::fast_forward_seconds(DAY_SECONDS * 10);
        account::create_account_for_test(host_addr);
        vault::register_vault<vault_type::CollateralVault, USDC>(host);
        vault::register_vault<vault_type::HouseLPVault, USDC>(host);
        vault::register_vault<vault_type::FeeHouseLPVault, USDC>(host);
        vault::register_vault<vault_type::FeeStakingVault, USDC>(host);
        vault::register_vault<vault_type::FeeDevVault, USDC>(host);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<USDC>(
            host,
            string::utf8(b"USDC"),
            string::utf8(b"USDC"),
            TEST_ASSET_DECIMALS,
            false,
        );
        move_to(host, AssetInfo {
            burn_cap,
            freeze_cap,
            mint_cap
        });
        let usdc_info = borrow_global<AssetInfo<USDC>>(host_addr);
        let mint_coin = coin::mint(100000 * exp(10, (TEST_ASSET_DECIMALS as u64)), &usdc_info.mint_cap);
        supra_account::deposit_coins(host_addr, mint_coin);

        register<USDC>(host);
        set_house_lp_withdraw_division<USDC>(host, 1000000);
        set_house_lp_deposit_fee<USDC>(host, 0);
        set_house_lp_withdraw_fee<USDC>(host, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_register(host: &signer, supra_framework: &signer) acquires HouseLPConfig, AssetInfo, HouseLP {
        let host_addr = address_of(host);
        call_test_setting(host, supra_framework);
        assert!(exists<HouseLPConfig<USDC>>(host_addr) == true, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_deposit(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo, EventIndexes {
        let host_addr = address_of(host);
        call_test_setting(host, supra_framework);

        let usdc_amount = coin::balance<USDC>(host_addr);
        let deposit_amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, deposit_amount);

        assert!(coin::balance<DXLP<USDC>>(host_addr) == deposit_amount, 0);
        assert!(coin::balance<USDC>(host_addr) == usdc_amount - deposit_amount, 1);
        assert!(vault::vault_balance<vault_type::HouseLPVault, USDC>() == deposit_amount, 2);
        assert!(option::extract<u128>(&mut coin::supply<DXLP<USDC>>()) == (deposit_amount as u128), 1);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_DEPOSIT_TOO_SMALL, location = Self)]
    fun test_deposit_too_small(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo, EventIndexes {
        call_test_setting(host, supra_framework);
        set_house_lp_minimum_deposit<USDC>(host, 100);
        deposit<USDC>(host, 10);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_set_configs(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
    let host_addr = address_of(host);
        call_test_setting(host, supra_framework);

        let house_lp_config = borrow_global<HouseLPConfig<USDC>>(host_addr);
        let house_lp = borrow_global<HouseLP<USDC>>(host_addr);
        assert!(house_lp_config.withdraw_division == 1000000, 0);
        assert!(house_lp.deposit_fee == 0, 1);
        assert!(house_lp.withdraw_fee == 0, 2);

        set_house_lp_deposit_fee<USDC>(host, 100);
        set_house_lp_withdraw_fee<USDC>(host, 200);
        set_house_lp_withdraw_division<USDC>(host, 333333);


        house_lp_config = borrow_global<HouseLPConfig<USDC>>(host_addr);
        house_lp = borrow_global<HouseLP<USDC>>(host_addr);
        assert!(house_lp.deposit_fee == 100, 6);
        assert!(house_lp.withdraw_fee == 200, 7);
        assert!(house_lp_config.withdraw_division == 333333, 12);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_profit_loss(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo, EventIndexes {
        let host_addr = address_of(host);
        call_test_setting(host, supra_framework);

        let usdc_info = borrow_global<AssetInfo<USDC>>(host_addr);
        let mint_coin = coin::mint(100 * exp(10, (TEST_ASSET_DECIMALS as u64)), &usdc_info.mint_cap);
        pnl_deposit_to_lp(mint_coin);
        assert!(vault::vault_balance<vault_type::HouseLPVault, USDC>() == 100 * exp(10, (TEST_ASSET_DECIMALS as u64)), 0);

        let withdraw_coin = pnl_withdraw_from_lp<USDC>(100 * exp(10, (TEST_ASSET_DECIMALS as u64)));
        assert!(coin::value(&withdraw_coin) == 100 * exp(10, (TEST_ASSET_DECIMALS as u64)), 1);
        assert!(vault::vault_balance<vault_type::HouseLPVault, USDC>() == 0, 2);

        coin::burn(withdraw_coin, &usdc_info.burn_cap);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_DEPOSIT_TOO_SMALL, location = Self)]
    fun test_deposit_small_rate_should_fail(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo, EventIndexes {
        let host_addr = address_of(host);
        call_test_setting(host, supra_framework);

        deposit<USDC>(host, 100 * exp(10, (TEST_ASSET_DECIMALS as u64)));
        assert!(coin::balance<DXLP<USDC>>(host_addr) == 100 * exp(10, (DXLP_DECIMALS as u64)), 0);

        let usdc_info = borrow_global<AssetInfo<USDC>>(host_addr);
        let mint_coin = coin::mint(1000 * exp(10, (TEST_ASSET_DECIMALS as u64)), &usdc_info.mint_cap);
        pnl_deposit_to_lp(mint_coin);

        deposit<USDC>(host, 1);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_deposit_fee(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo, EventIndexes {
        let host_addr = address_of(host);
        call_test_setting(host, supra_framework);
        set_house_lp_deposit_fee<USDC>(host, 1000);  // 0.1%

        let deposit_amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        let deposit_fee: u64;
        let coin_value: u64;
        deposit<USDC>(host, deposit_amount);
        {
            let house_lp = borrow_global<HouseLP<USDC>>(host_addr);
            coin_value = vault::vault_balance<vault_type::HouseLPVault, USDC>();
            deposit_fee = deposit_amount * house_lp.deposit_fee / FEE_POINTS_DIVISOR;
            assert!(coin_value == deposit_amount, 0);
            assert!(coin::balance<DXLP<USDC>>(host_addr) == deposit_amount - deposit_fee, 0);
        };
    }
    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun T_register_twice(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
        call_test_setting(host, supra_framework);
        register<USDC>(host);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_register(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
        call_test_setting(host, supra_framework);
        register<USDC>(supra_framework);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_set_house_lp_deposit_fee(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
        call_test_setting(host, supra_framework);
        set_house_lp_deposit_fee<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_set_house_lp_withdraw_fee(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
        call_test_setting(host, supra_framework);
        set_house_lp_withdraw_fee<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_set_house_lp_withdraw_division(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
        call_test_setting(host, supra_framework);
        set_house_lp_withdraw_division<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_set_house_lp_minimum_deposit(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
        call_test_setting(host, supra_framework);
        set_house_lp_minimum_deposit<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_COIN_NOT_INITIALIZED, location = Self)]
    fun T_E_COIN_NOT_INITIALIZED_register(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo {
        call_test_setting(host, supra_framework);
        register<FAIL_USDC>(host);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_HARD_BREAK_EXCEEDED, location = Self)]
    fun test_breaks(host: &signer, supra_framework: &signer) acquires HouseLPConfig, HouseLP, AssetInfo, EventIndexes {
        let host_addr = address_of(host);
        call_test_setting(host, supra_framework);

        deposit<USDC>(host, 1000 * exp(10, (TEST_ASSET_DECIMALS as u64)));
        assert!(check_soft_break_exceeded<USDC>() == false, 0);

        let pnl = pnl_withdraw_from_lp<USDC>(201 * exp(10, (TEST_ASSET_DECIMALS as u64)));
        coin::deposit(host_addr, pnl);
        assert!(check_soft_break_exceeded<USDC>(), 0);

        let pnl2 = pnl_withdraw_from_lp<USDC>(100 * exp(10, (TEST_ASSET_DECIMALS as u64)));
        coin::deposit(host_addr, pnl2);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_register_redeem_plan(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes {
        call_test_setting(host, supra_framework);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        register_redeem_plan<USDC>(host, amount);
        let redeem_plan = borrow_global<RedeemPlan<USDC>>(address_of(host));
        assert!(coin::value(&redeem_plan.dxlp) == amount, 0);
        assert!(redeem_plan.redeem_count == 0, 0);
        assert!(redeem_plan.initial_amount == amount, 0);
        assert!(redeem_plan.withdraw_amount == 0, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_redeem(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));
        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host);
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount / 5, 0);

        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host);
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount / 5 * 2, 0);

        let redeem_plan = borrow_global<RedeemPlan<USDC>>(address_of(host));
        assert!(coin::value(&redeem_plan.dxlp) == amount * 3 / 5, 0);
        assert!(redeem_plan.withdraw_amount == amount * 2 / 5, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_UNREDEEMABLE, location = Self)]
    fun test_redeem_already_redeem_E_UNREDEEMABLE(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));
        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host);
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount / 5, 0);
        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host);
        redeem<USDC>(host);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_UNREDEEMABLE, location = Self)]
    fun test_redeem_passed_E_UNREDEEMABLE(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));
        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host);
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount / 5, 0);
        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds((DAY_SECONDS + 10) * 2); // passed 2 days
        redeem<USDC>(host);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_redeem_with_withdraw_fee(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);
        set_house_lp_withdraw_fee<USDC>(host, 100);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));

        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host);

        std::debug::print(&string::utf8(b"before: "));
        std::debug::print(&(amount * (FEE_POINTS_DIVISOR - 20) / FEE_POINTS_DIVISOR));

        std::debug::print(&string::utf8(b"after: "));
        std::debug::print(&(coin::balance<USDC>(address_of(host)) - before_usdc_amount));

        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount * (FEE_POINTS_DIVISOR - 20) / FEE_POINTS_DIVISOR, 0);
        assert!(!exists<RedeemPlan<USDC>>(address_of(host)), 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_cancel(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        let before_DXLP_amount_for_cancel = coin::balance<DXLP<USDC>>(address_of(host));
        register_redeem_plan<USDC>(host, amount);
        assert!(coin::balance<DXLP<USDC>>(address_of(host)) == 0, 0);
        cancel_redeem_plan<USDC>(host);
        assert!(coin::balance<DXLP<USDC>>(address_of(host)) == before_DXLP_amount_for_cancel, 0);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));
        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host);
        let before_DXLP_amount = coin::balance<DXLP<USDC>>(address_of(host));
        timestamp::fast_forward_seconds(DAY_SECONDS * 3 + 10);
        cancel_redeem_plan<USDC>(host);
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount / 5, 0);
        assert!(coin::balance<DXLP<USDC>>(address_of(host)) - before_DXLP_amount == amount * 4 / 5, 0);
        assert!(!exists<RedeemPlan<USDC>>(address_of(host)), 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_UNCANCELABLE, location = Self)]
    fun test_E_UNCANCELABLE(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host);
        cancel_redeem_plan<USDC>(host);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework, coffee = @0xC0FFEE)]
    fun test_redeem_deposit_more(host: &signer, supra_framework: &signer, coffee: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);
        account::create_account_for_test(address_of(coffee));

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        supra_account::transfer_coins<USDC>(host, address_of(coffee), amount * 5);
        deposit<USDC>(host, amount);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));
        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host);
        deposit<USDC>(coffee, amount);
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS);
        deposit<USDC>(coffee, amount);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS);
        deposit<USDC>(coffee, amount);
        redeem<USDC>(host);
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount, 0)
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_redeem_with_profit(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        let profit = coin::withdraw<USDC>(host, amount * 2);
        deposit<USDC>(host, amount);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));
        register_redeem_plan<USDC>(host, amount); // balance 80, withdraw 20
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host); // balance 60, withdraw 20
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host); // balance 40, withdraw 20
        pnl_deposit_to_lp(coin::extract(&mut profit, amount)); // balance 140
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host); // balance 70, withdraw 70
        timestamp::fast_forward_seconds(DAY_SECONDS);
        pnl_deposit_to_lp(profit); // balance 170
        redeem<USDC>(host); // balance 0, withdraw 0
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount * 3, 0)
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_redeem_with_loss(host: &signer, supra_framework: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);
        account::create_account_for_test(@0x001);

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, amount);

        let before_usdc_amount = coin::balance<USDC>(address_of(host));
        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host); // balance 80, withdraw 20
        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host); // balance 60, withdraw 20
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host); // balance 40, withdraw 20
        supra_account::deposit_coins(@0x001, pnl_withdraw_from_lp<USDC>(amount / 100)); // balance 39
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host); // balance 19.5, withdraw 19.5
        timestamp::fast_forward_seconds(DAY_SECONDS);
        supra_account::deposit_coins(@0x001, pnl_withdraw_from_lp<USDC>(amount / 100)); // balance 18.5
        redeem<USDC>(host); // balance 0, withdraw 18.5
        assert!(coin::balance<USDC>(address_of(host)) - before_usdc_amount == amount * 98 / 100, 0)
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework, coffee = @0xC0FFEE, coffee2 = @0xC0FFEE2)]
    fun test_redeem_with_multiple_user(host: &signer, supra_framework: &signer, coffee: &signer, coffee2: &signer)
    acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);
        account::create_account_for_test(address_of(coffee));
        account::create_account_for_test(address_of(coffee2));

        let amount = 100 * exp(10, (TEST_ASSET_DECIMALS as u64));
        let profit = coin::withdraw<USDC>(host, amount * 3);
        supra_account::transfer_coins<USDC>(host, address_of(coffee), amount);
        supra_account::transfer_coins<USDC>(host, address_of(coffee2), amount);

        deposit<USDC>(host, amount); // balance 100, DXLP 100
        deposit<USDC>(coffee, amount); // balance 200, DXLP 200
        pnl_deposit_to_lp(coin::extract(&mut profit, amount)); // balance 300, DXLP 200
        pnl_deposit_to_lp(coin::extract(&mut profit, amount)); // balance 400, DXLP 200

        register_redeem_plan<USDC>(host, amount);
        redeem<USDC>(host); // balance 360, withdraw 40
        timestamp::fast_forward_seconds(DAY_SECONDS + 10);
        redeem<USDC>(host); // balance 320, withdraw 40
        timestamp::fast_forward_seconds(DAY_SECONDS);
        deposit<USDC>(coffee2, amount); // balance 420, DXLP 210
        redeem<USDC>(host);
        supra_account::deposit_coins(address_of(coffee2), pnl_withdraw_from_lp<USDC>(amount / 100));
        timestamp::fast_forward_seconds(DAY_SECONDS);
        redeem<USDC>(host);
        timestamp::fast_forward_seconds(DAY_SECONDS);
        supra_account::deposit_coins(address_of(coffee2), pnl_withdraw_from_lp<USDC>(amount / 100));
        pnl_deposit_to_lp(profit);
        redeem<USDC>(host);
    }

    #[test_only]
    fun force_pnl_withdraw_from_lp<AssetT>(amount: u64): Coin<AssetT> acquires HouseLP, EventIndexes {
    deposit_trading_fee(fee_distributor::withdraw_fee_houselp_all<AssetT>());
        update_highest_price<AssetT>();
        let asset = vault::withdraw_vault<vault_type::HouseLPVault, AssetT>(amount);
        let vault_balance = vault::vault_balance<vault_type::HouseLPVault, AssetT>();
        let lp_supply = (option::extract<u128>(&mut coin::supply<DXLP<AssetT>>()) as u64);
        let event_indexes = borrow_global_mut<EventIndexes>(@dexlyn);
        if (amount > 0) {
            event::emit(
            FeeEvent {
                fee_type: T_FEE_TYPE_PNL_FEE,
                asset_type: type_info::type_of<AssetT>(),
                amount,
                amount_sign: false,
                timestamp: timestamp::now_seconds(),
                vault_balance: vault_balance,
                lp_supply: lp_supply,
                id: event_indexes.fee_index
                }
            );
            event_indexes.fee_index = event_indexes.fee_index + 1;
        };
        return asset
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = 100, location = Self)] // #check_hard_break_exceeded is not getting affected during withdrawal
    fun test_mdd_distortion_by_withdraw_fee(host: &signer, supra_framework: &signer)
        acquires HouseLPConfig, HouseLP, AssetInfo, RedeemPlan, EventIndexes, LPTokenFeesResource {
        call_test_setting(host, supra_framework);
        set_house_lp_withdraw_fee<USDC>(host, 900000);

        let deposit_amount = 1000 * exp(10, (TEST_ASSET_DECIMALS as u64));
        deposit<USDC>(host, deposit_amount);

        let loss_amount = 400 * exp(10, (TEST_ASSET_DECIMALS as u64));
        let pnl_coin = force_pnl_withdraw_from_lp<USDC>(loss_amount);
        let host_addr = address_of(host);
        let usdc_info = borrow_global<AssetInfo<USDC>>(host_addr);
        coin::burn(pnl_coin, &usdc_info.burn_cap);
        assert!(check_hard_break_exceeded<USDC>(), 0);

        register_redeem_plan<USDC>(host, deposit_amount);
        redeem<USDC>(host);

        assert!(!check_hard_break_exceeded<USDC>(), 100);
    }

}
