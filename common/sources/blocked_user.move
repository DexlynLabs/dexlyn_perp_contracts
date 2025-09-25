module dexlyn::blocked_user {
    use std::signer::address_of;
    use std::vector;

    /// When signer is not owner of module
    const E_NOT_AUTHORIZED: u64 = 1;
    /// Contact to team for more information
    const E_BLOCKED: u64 = 2;

    struct BlockedUsers has key {
        users: vector<address>
    }

    public entry fun register_blocked_user(_admin: &signer, _blocked_user: address)
    acquires BlockedUsers {
        assert!(address_of(_admin) == @dexlyn, E_NOT_AUTHORIZED);
        if (!exists<BlockedUsers>(address_of(_admin))) {
            move_to(_admin, BlockedUsers {
                users: vector::empty()
            });
        };
        let blocked_users = borrow_global_mut<BlockedUsers>(address_of(_admin));
        if (!vector::contains(&blocked_users.users, &_blocked_user)) {
            vector::push_back(&mut blocked_users.users, _blocked_user);
        };
    }

    public entry fun remove_blocked_user(_admin: &signer, _blocked_user: address)
    acquires BlockedUsers {
        assert!(address_of(_admin) == @dexlyn, E_NOT_AUTHORIZED);
        let blocked_users = borrow_global_mut<BlockedUsers>(address_of(_admin));
        if (vector::contains(&blocked_users.users, &_blocked_user)) {
            vector::remove_value(&mut blocked_users.users, &_blocked_user);
        };
    }

    public fun is_blocked(_user_address: address)
    acquires BlockedUsers {
        if (exists<BlockedUsers>(@dexlyn)) {
            let blocked_users = borrow_global<BlockedUsers>(@dexlyn);
            assert!(!vector::contains(&blocked_users.users, &_user_address), E_BLOCKED);
        };
    }

    #[test_only]
    use supra_framework::account;
    #[test_only]
    use supra_framework::supra_account;
    #[test_only]
    use supra_framework::supra_coin;
    #[test_only]
    use supra_framework::timestamp;

    #[test_only]
    fun call_test_setting(host: &signer, supra_framework: &signer) {
        timestamp::set_time_has_started_for_testing(supra_framework);
        supra_coin::ensure_initialized_with_apt_fa_metadata_for_test();
        if (!account::exists_at(address_of(host))) {
            supra_account::create_account(address_of(host));
        };
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    public fun T_register_blocked_user(host: &signer, supra_framework: &signer) acquires BlockedUsers {
        call_test_setting(host, supra_framework);
        register_blocked_user(host, @0x111);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    #[expected_failure(abort_code = E_BLOCKED)]
    public fun T_check_blocked_user(host: &signer, supra_framework: &signer) acquires BlockedUsers {
        call_test_setting(host, supra_framework);
        register_blocked_user(host, @0x111);
        is_blocked(@0x111);
    }

    #[test(host = @dexlyn, supra_framework = @supra_framework)]
    public fun T_check_non_blocked_user(host: &signer, supra_framework: &signer) acquires BlockedUsers {
        call_test_setting(host, supra_framework);
        register_blocked_user(host, @0x111);
        is_blocked(@0x222);
    }
}