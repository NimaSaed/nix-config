{ config, lib, pkgs, ... }:

{
  options.services.pods.nextcloud._redisConfigFile = lib.mkOption {
    type = lib.types.package;
    internal = true;
    default = pkgs.writeText "redis.conf" ''
      # Redis configuration for Nextcloud
      # Password is injected via sops template
      requirepass ${config.sops.placeholder."nextcloud/redis_password"}

      # Memory management
      maxmemory 512mb
      maxmemory-policy allkeys-lru

      # Persistence (AOF)
      appendonly yes
      appendfsync everysec

      # Network
      bind 127.0.0.1
      port 6379

      # Logging
      loglevel notice
    '';
    description = "Generated Redis configuration file for Nextcloud";
  };
}
