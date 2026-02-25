{ config, lib, pkgs, ... }:

let
  cfg = config.services.pods.nextcloud;
in
{
  options.services.pods.nextcloud._nginxConfigFile = lib.mkOption {
    type = lib.types.package;
    internal = true;
    default = pkgs.writeText "nextcloud-nginx.conf" ''
      # Official Nextcloud FPM nginx configuration
      # Source: https://github.com/nextcloud/docker/blob/master/.examples/docker-compose/insecure/mariadb/fpm/web/nginx.conf
      # Modified for rootless Podman (port 8080)

      worker_processes auto;
      error_log /var/log/nginx/error.log warn;
      pid /tmp/nginx.pid;

      events {
          worker_connections 1024;
      }

      http {
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          types {
              text/javascript mjs;
          }

          log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for"';

          access_log /var/log/nginx/access.log main;
          sendfile on;
          server_tokens off;
          keepalive_timeout 65;

          # Use /tmp for cache directories (writable in rootless containers)
          client_body_temp_path /tmp/client_temp;
          proxy_temp_path /tmp/proxy_temp;
          fastcgi_temp_path /tmp/fastcgi_temp;
          uwsgi_temp_path /tmp/uwsgi_temp;
          scgi_temp_path /tmp/scgi_temp;

          map $arg_v $asset_immutable {
              "" "";
              default ", immutable";
          }

          upstream php-handler {
              server 127.0.0.1:9000;
          }

          server {
              listen 8080;  # Non-privileged port for rootless Podman

              client_max_body_size 10G;  # Match PHP_UPLOAD_LIMIT
              client_body_timeout 300s;
              fastcgi_buffers 64 4K;
              client_body_buffer_size 512k;

              # Gzip compression
              gzip on;
              gzip_vary on;
              gzip_comp_level 4;
              gzip_min_length 256;
              gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
              gzip_types application/atom+xml text/javascript application/javascript
                         application/json application/ld+json application/manifest+json
                         application/rss+xml application/vnd.geo+json
                         application/vnd.ms-fontobject application/wasm
                         application/x-font-ttf application/x-web-app-manifest+json
                         application/xhtml+xml application/xml font/opentype image/bmp
                         image/svg+xml image/x-icon text/cache-manifest text/css
                         text/plain text/vcard text/vnd.rim.location.xloc text/vtt
                         text/x-component text/x-cross-domain-policy;

              # Security headers (Traefik adds HSTS)
              add_header Referrer-Policy "no-referrer" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header X-Frame-Options "SAMEORIGIN" always;
              add_header X-Permitted-Cross-Domain-Policies "none" always;
              add_header X-Robots-Tag "noindex, nofollow" always;
              add_header X-XSS-Protection "1; mode=block" always;

              fastcgi_hide_header X-Powered-By;

              root /var/www/html;
              index index.php index.html /index.php$request_uri;

              # WebDAV redirect for desktop clients
              location = / {
                  if ($http_user_agent ~ ^DavClnt) {
                      return 302 /remote.php/webdav/$is_args$args;
                  }
              }

              location = /robots.txt {
                  allow all;
                  log_not_found off;
                  access_log off;
              }

              # .well-known URLs (handled by Traefik middleware in main config)
              location ^~ /.well-known {
                  location = /.well-known/carddav   { return 301 /remote.php/dav/; }
                  location = /.well-known/caldav    { return 301 /remote.php/dav/; }
                  location = /.well-known/webfinger { return 301 /index.php$request_uri; }
                  location = /.well-known/nodeinfo  { return 301 /index.php$request_uri; }
                  location /.well-known/acme-challenge  { try_files $uri $uri/ =404; }
                  location /.well-known/pki-validation  { try_files $uri $uri/ =404; }
                  return 301 /index.php$request_uri;
              }

              # Block access to sensitive directories
              location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/) {
                  return 404;
              }
              location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) {
                  return 404;
              }

              # PHP-FPM proxy
              location ~ \.php(?:$|/) {
                  rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode(_arm64)?\/proxy) /index.php$request_uri;

                  fastcgi_split_path_info ^(.+?\.php)(/.*?)$;
                  set $path_info $fastcgi_path_info;

                  try_files $fastcgi_script_name =404;

                  include /etc/nginx/fastcgi_params;
                  fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                  fastcgi_param PATH_INFO $path_info;
                  fastcgi_param modHeadersAvailable true;
                  fastcgi_param front_controller_active true;
                  fastcgi_pass php-handler;

                  fastcgi_intercept_errors on;
                  fastcgi_request_buffering off;
                  fastcgi_max_temp_file_size 0;
              }

              # Static assets with caching
              location ~ \.(?:css|js|mjs|svg|gif|ico|jpg|png|webp|wasm|tflite|map|ogg|flac)$ {
                  try_files $uri /index.php$request_uri;
                  add_header Cache-Control "public, max-age=15778463$asset_immutable";
                  access_log off;

                  location ~ \.wasm$ {
                      default_type application/wasm;
                  }
              }

              # Fonts
              location ~ \.(otf|woff2?)$ {
                  try_files $uri /index.php$request_uri;
                  expires 7d;
                  access_log off;
              }

              location /remote {
                  return 301 /remote.php$request_uri;
              }

              location / {
                  try_files $uri $uri/ /index.php$request_uri;
              }
          }
      }
    '';
    description = "Generated nginx configuration for Nextcloud FPM";
  };
}
