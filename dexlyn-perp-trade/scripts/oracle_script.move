// script {
//     use dexlyn::pair_types;
//     use dexlyn::managed_price_oracle;

//     fun main(sender: &signer) {

//         managed_price_oracle::initialize_module(sender);
//         managed_price_oracle::set_update_supra_enabled<pair_types::ETH_USD>(sender, true);
//         managed_price_oracle::set_supra_price_identifier<pair_types::ETH_USD>(sender, 19);

//         managed_price_oracle::set_update_supra_enabled<pair_types::BTC_USD>(sender, true);
//         managed_price_oracle::set_supra_price_identifier<pair_types::BTC_USD>(sender, 18)
//     }
// }