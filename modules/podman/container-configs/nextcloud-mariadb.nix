{ config, lib, pkgs, ... }:

{
  options.services.pods.nextcloud._mariadbConfigFile = lib.mkOption {
    type = lib.types.package;
    internal = true;
    default = pkgs.writeText "nextcloud.cnf" ''
      [mysqld]
      # Nextcloud-optimized MariaDB configuration
      innodb_file_per_table = 1
      innodb_buffer_pool_size = 512M
      innodb_log_file_size = 128M

      # Character set and collation (utf8mb4 for full Unicode support including emoji)
      character_set_server = utf8mb4
      collation_server = utf8mb4_unicode_ci

      # Transaction isolation required by Nextcloud
      transaction_isolation = READ-COMMITTED

      # Connection limits
      max_connections = 100

      [client]
      default_character_set = utf8mb4
    '';
    description = "Generated MariaDB configuration file for Nextcloud optimization";
  };
}
