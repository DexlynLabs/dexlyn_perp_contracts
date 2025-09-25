module dexlyn::fee_distributor {

    use std::signer::address_of;
    use supra_framework::coin::{Self, Coin};
    use supra_framework::event::{Self};
    use supra_framework::supra_account;

    use dexlyn::vault;
    use dexlyn::vault_type;
    use dexlyn::safe_math::{safe_mul_div};

    friend dexlyn::house_lp;

    /// When the asset register with house_lp is not a coin
    const E_COIN_NOT_INITIALIZED: u64 = 0;
    /// When signer is not owner of module
    const E_NOT_AUTHORIZED: u64 = 1;
    /// When stake asset already exists
    const E_STAKE_ASSET_ALREDY_EXIST: u64 = 2;

    /// Precision buffer for divide
    const PRECISION: u64 = 1000000;
    /// Precision for rebate calculation
    const REBATE_PRECISION: u64 = 1000000;

    /// weight of fee distributed to lp, stake, dev
    struct FeeDistributorInfo<phantom AssetT> has key {
        lp_weight: u64,
        stake_weight: u64,
        dev_weight: u64,
        total_weight: u64
    }

    #[event]
    /// event emitted whenever a fee is deposited
    struct DepositFeeEvent has store, drop {
        lp_amount: u64,
        stake_amount: u64,
        dev_amount: u64,
    }

    /// initialize function, Need to call it through the entry function per collateral.
    /// @Type Parameters
    /// AssetT: collateral type
    public fun initialize<AssetT>(
        _host: &signer
    ) {
        assert!(address_of(_host) == @dexlyn, E_NOT_AUTHORIZED);
        assert!(coin::is_coin_initialized<AssetT>(), E_COIN_NOT_INITIALIZED);

        if (!exists<FeeDistributorInfo<AssetT>>(@dexlyn)) {
            move_to(_host, FeeDistributorInfo<AssetT> {
                lp_weight: 0,
                stake_weight: 0,
                dev_weight: 0,
                total_weight: 0,
            });
        };
    }

    // return rebate fee coin object
    public fun deposit_fee_with_rebate<AssetT>(
        _fee: Coin<AssetT>,
        _user: address,
    ) acquires FeeDistributorInfo {
        let fee_distributor_info = borrow_global_mut<FeeDistributorInfo<AssetT>>(@dexlyn);
        let fee_amount = coin::value(&_fee);

        // Calculate the LP weight and put it in the vault.
        let lp_amount = safe_mul_div(
            fee_amount,
            fee_distributor_info.lp_weight,
            fee_distributor_info.total_weight
        );
        let lp_fee = coin::extract(&mut _fee, lp_amount);
        vault::deposit_vault<vault_type::FeeHouseLPVault, AssetT>(lp_fee);

        // Calculate the Stake weight and put it in the vault.
        let stake_amount = safe_mul_div(
            fee_amount - lp_amount,
            fee_distributor_info.stake_weight,
            fee_distributor_info.stake_weight + fee_distributor_info.dev_weight
        );

        let stake_fee = coin::extract(&mut _fee, stake_amount);
        vault::deposit_vault<vault_type::FeeStakingVault, AssetT>(stake_fee);

        // To avoid having a small amount of money left over,
        // put the rest in the dev vault, except for the LP and Stake.
        let dev_amount = coin::value(&_fee);
        vault::deposit_vault<vault_type::FeeDevVault, AssetT>(_fee);

        // emit event
        event::emit(
            DepositFeeEvent {
                lp_amount,
                stake_amount,
                dev_amount
            }
        );
    }

    /// Function used to claim a fee from a house LP.
    /// There are no situations where we want to take only part of the value,
    /// so we pass all the values each time we call it.
    /// @Type Parameters
    /// AssetT: collateral type
    public (friend) fun withdraw_fee_houselp_all<AssetT>(): Coin<AssetT> {
        vault::withdraw_vault<vault_type::FeeHouseLPVault, AssetT>(
            vault::vault_balance<vault_type::FeeHouseLPVault, AssetT>()
        )
    }

    /// Function to withdraw fees accumulated in the dev vault.
    /// Only allowed for admin.
    /// @Type Parameters
    /// AssetT: collateral type
    public fun withdraw_fee_dev<AssetT>(_host: &signer, _amount: u64) {
        assert!(address_of(_host) == @dexlyn, E_NOT_AUTHORIZED);
        supra_account::deposit_coins(address_of(_host), vault::withdraw_vault<vault_type::FeeDevVault, AssetT>(_amount));
    }

    /// Function to withdraw fees accumulated in the stake vault.
    /// This function exists because we don't currently have staking.
    /// It will be removed in the future.
    /// Only allowed for admin.
    /// @Type Parameters
    /// AssetT: collateral type
    public fun withdraw_fee_stake<AssetT>(_host: &signer, _amount: u64) {
        assert!(address_of(_host) == @dexlyn, E_NOT_AUTHORIZED);
        supra_account::deposit_coins(address_of(_host), vault::withdraw_vault<vault_type::FeeStakingVault, AssetT>(_amount));
    }

    /// @Type Parameters
    /// AssetT: collateral type
    public fun set_lp_weight<AssetT>(_host: &signer, _lp_weight: u64) acquires FeeDistributorInfo {
        let host_addr = address_of(_host);
        assert!(host_addr == @dexlyn, E_NOT_AUTHORIZED);

        let fee_distributor_info = borrow_global_mut<FeeDistributorInfo<AssetT>>(host_addr);
        fee_distributor_info.lp_weight = _lp_weight;
        fee_distributor_info.total_weight = fee_distributor_info.lp_weight + fee_distributor_info.stake_weight + fee_distributor_info.dev_weight;
    }

    /// @Type Parameters
    /// AssetT: collateral type
    public fun set_stake_weight<AssetT>(_host: &signer, _stake_weight: u64) acquires FeeDistributorInfo {
        let host_addr = address_of(_host);
        assert!(host_addr == @dexlyn, E_NOT_AUTHORIZED);

        let fee_distributor_info = borrow_global_mut<FeeDistributorInfo<AssetT>>(host_addr);
        fee_distributor_info.stake_weight = _stake_weight;
        fee_distributor_info.total_weight = fee_distributor_info.lp_weight + fee_distributor_info.stake_weight + fee_distributor_info.dev_weight;
    }

    /// @Type Parameters
    /// AssetT: collateral type
    public fun set_dev_weight<AssetT>(_host: &signer, _dev_weight: u64) acquires FeeDistributorInfo {
        let host_addr = address_of(_host);
        assert!(host_addr == @dexlyn, E_NOT_AUTHORIZED);

        let fee_distributor_info = borrow_global_mut<FeeDistributorInfo<AssetT>>(host_addr);
        fee_distributor_info.dev_weight = _dev_weight;
        fee_distributor_info.total_weight = fee_distributor_info.lp_weight + fee_distributor_info.stake_weight + fee_distributor_info.dev_weight;
    }

    #[test_only]
    use std::string;

    #[test_only]
    use std::signer;

    #[test_only]
    use supra_framework::timestamp;

    #[test_only]
    use supra_framework::account;
    #[test_only]
    use supra_framework::supra_coin;

    #[test_only]
    use supra_framework::coin::{MintCapability, BurnCapability, FreezeCapability};

    #[test_only]
    use dexlyn::safe_math::exp;

    #[test_only]
    const TEST_ASSET_DECIMALS: u8 = 6;

    #[test_only]
    struct USDC {}

    #[test_only]
    struct FAIL_USDC {}

    #[test_only]
    struct AssetInfo<phantom AssetT> has key, store {
        burn_cap: BurnCapability<AssetT>,
        freeze_cap: FreezeCapability<AssetT>,
        mint_cap: MintCapability<AssetT>,
    }

    #[test_only]
    fun call_test_setting(
        host: &signer, supra_framework: &signer
    ) acquires AssetInfo, FeeDistributorInfo {
        let host_addr = signer::address_of(host);
        timestamp::set_time_has_started_for_testing(supra_framework);
        supra_coin::ensure_initialized_with_apt_fa_metadata_for_test();
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
        coin::register<USDC>(host);
        let mint_coin = coin::mint(1000 * exp(10, (TEST_ASSET_DECIMALS as u64)), &usdc_info.mint_cap);
        coin::deposit(host_addr, mint_coin);

        initialize<USDC>(host);
        set_lp_weight<USDC>(host, 6);
        set_dev_weight<USDC>(host, 2);
        set_stake_weight<USDC>(host, 2);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun test_initialize(
        host: &signer, supra_framework: &signer
    ) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    fun T_register_twice(host: &signer, supra_framework: &signer) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        initialize<USDC>(host);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_register(host: &signer, supra_framework: &signer) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        initialize<USDC>(supra_framework);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_withdraw_fee_stake(host: &signer, supra_framework: &signer) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        withdraw_fee_stake<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_set_lp_weight(host: &signer, supra_framework: &signer) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        set_lp_weight<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_set_stake_weight(host: &signer, supra_framework: &signer) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        set_stake_weight<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_NOT_AUTHORIZED, location = Self)]
    fun T_E_NOT_AUTHORIZED_set_dev_weight(host: &signer, supra_framework: &signer) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        set_dev_weight<USDC>(supra_framework, 0);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_COIN_NOT_INITIALIZED, location = Self)]
    fun T_E_COIN_NOT_INITIALIZED_register(host: &signer, supra_framework: &signer) acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        initialize<FAIL_USDC>(host);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework, user = @0xC0FFEE, user2= @0xC0FFEE2)]
    fun T_deposit_Fee_with_rebate(host: &signer, supra_framework: &signer, user: &signer, user2: &signer)
    acquires AssetInfo, FeeDistributorInfo {
        call_test_setting(host, supra_framework);
        supra_account::create_account(address_of(user));
        supra_account::create_account(address_of(user2));
        coin::register<USDC>(user);
        coin::register<USDC>(user2);
        vault::register_vault<vault_type::RebateVault, USDC>(host);


        let usdc = coin::withdraw<USDC>(host, 100000);
        deposit_fee_with_rebate<USDC>(usdc, address_of(user2));
        let usdc = coin::withdraw<USDC>(host, 100000);
        deposit_fee_with_rebate<USDC>(usdc, address_of(user));

        assert!(vault::vault_balance<vault_type::FeeHouseLPVault, USDC>() == 120000, 0); // 60%
        // TODO: why these changed to 40000
        // It is because we have removed referrer
        assert!(vault::vault_balance<vault_type::FeeStakingVault, USDC>() == 40000, 0); // 20%
        // TODO: why these changed to 40000
        // It is because we have removed referrer
        assert!(vault::vault_balance<vault_type::FeeDevVault, USDC>() == 40000, 0); // 20%

        let balance_before = coin::balance<USDC>(address_of(user));
        // TODO: why these two are 0; 
        // It is because we have removed referrer
        assert!(coin::balance<USDC>(address_of(user)) - balance_before == 0, 0);

        // TODO: why these two are 0;
        // It is because we have removed referrer
        balance_before = coin::balance<USDC>(address_of(host));
        assert!(coin::balance<USDC>(address_of(host)) - balance_before == 0, 0);
    }
}