module dexlyn::managed_vault {
    use dexlyn::vault;

    public entry fun register_vault<VaultT, AssetT>(_host: &signer) {
        vault::register_vault<VaultT, AssetT>(_host);
    }
}