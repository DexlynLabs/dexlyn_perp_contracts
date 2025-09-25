script {
    use dexlyn::pair_types;
    use usdc_deployer::tusdc_coin;
    use dexlyn::managed_trading;
    use dexlyn::managed_price_oracle;
    use std::string::{utf8};

    fun main(sender: &signer) {

        // ETH USD CONF

        // set_rollover_fee_per_block
        // managed_trading::set_rollover_fee_per_block<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 0);
        managed_trading::set_taker_fee<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 600);
        managed_trading::set_maker_fee<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 300);
        managed_trading::set_max_interest<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 500000000000);
        managed_trading::set_min_leverage<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 3000000);
        managed_trading::set_max_leverage<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 150000000);
        managed_trading::set_market_depth_above<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 10000000000);
        managed_trading::set_market_depth_below<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 10000000000);
        managed_trading::set_execute_time_limit<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 300);
        managed_trading::set_liquidate_threshold<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 1000);
        managed_trading::set_maximum_profit<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 90000);
        managed_trading::set_skew_factor<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 600000000000000);
        managed_trading::set_max_funding_velocity<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 1910434897);
        managed_trading::set_minimum_order_collateral<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 1739129);
        managed_trading::set_minimum_position_collateral<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 1000000);
        managed_trading::set_minimum_position_size<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 260869499);
        managed_trading::set_maximum_position_collateral<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 1000000000000);
        // managed_trading::set_execution_fee<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, 0);

        managed_trading::set_param<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, utf8(b"maximum_skew_limit"), x"005cb2ec22000000");
        managed_trading::set_param<pair_types::ETH_USD, tusdc_coin::TUSDC>(sender, utf8(b"cooldown_period_second"), x"3c00000000000000");

        // ETH USD CONF

        // BTC USD CONF
        managed_trading::set_taker_fee<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 600);
        managed_trading::set_maker_fee<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 300);
        managed_trading::set_max_interest<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 500000000000);
        managed_trading::set_min_leverage<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 3000000);
        managed_trading::set_max_leverage<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 150000000);
        managed_trading::set_market_depth_above<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 10000000000);
        managed_trading::set_market_depth_below<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 10000000000);
        managed_trading::set_execute_time_limit<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 300);
        managed_trading::set_liquidate_threshold<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 1000);
        managed_trading::set_maximum_profit<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 90000);
        managed_trading::set_skew_factor<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 600000000000000);
        managed_trading::set_max_funding_velocity<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 924834110);
        managed_trading::set_minimum_order_collateral<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 1739129);
        managed_trading::set_minimum_position_collateral<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 1000000);
        managed_trading::set_minimum_position_size<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 260869499);
        managed_trading::set_maximum_position_collateral<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 1000000000000);
        // managed_trading::set_execution_fee<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, 0);

        managed_trading::set_param<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, utf8(b"maximum_skew_limit"), x"005cb2ec22000000");
        managed_trading::set_param<pair_types::BTC_USD, tusdc_coin::TUSDC>(sender, utf8(b"cooldown_period_second"), x"3c00000000000000");
        // BTC USD CONF

        // SUPRA USDT CONF
        managed_trading::set_taker_fee<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 800);
        managed_trading::set_maker_fee<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 400);
        managed_trading::set_max_interest<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 500000000000);
        managed_trading::set_min_leverage<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 3000000);
        managed_trading::set_max_leverage<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 150000000);
        managed_trading::set_market_depth_above<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 10000000000);
        managed_trading::set_market_depth_below<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 10000000000);
        managed_trading::set_execute_time_limit<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 300);
        managed_trading::set_liquidate_threshold<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 1000);
        managed_trading::set_maximum_profit<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 90000);
        managed_trading::set_skew_factor<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 20000000000000);
        managed_trading::set_max_funding_velocity<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 2000000000);
        managed_trading::set_minimum_order_collateral<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 1739129);
        managed_trading::set_minimum_position_collateral<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 1000000);
        managed_trading::set_minimum_position_size<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 260869499);
        managed_trading::set_maximum_position_collateral<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 1000000000000);
        managed_trading::set_execution_fee<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, 0);

        managed_trading::set_param<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, utf8(b"maximum_skew_limit"), x"005cb2ec22000000");
        managed_trading::set_param<pair_types::SUPRA_USDT, tusdc_coin::TUSDC>(sender, utf8(b"cooldown_period_second"), x"3c00000000000000");
        // SUPRA USDT CONF

        managed_price_oracle::set_update_supra_enabled<pair_types::ETH_USD>(sender, true);
        managed_price_oracle::set_supra_price_identifier<pair_types::ETH_USD>(sender, 19);

        managed_price_oracle::set_update_supra_enabled<pair_types::BTC_USD>(sender, true);
        managed_price_oracle::set_supra_price_identifier<pair_types::BTC_USD>(sender, 18);

        managed_price_oracle::set_update_supra_enabled<pair_types::SUPRA_USDT>(sender, true);
        managed_price_oracle::set_supra_price_identifier<pair_types::SUPRA_USDT>(sender, 500);
    }
}