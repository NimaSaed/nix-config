{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.media.nzbget;
  yesNo = b: if b then "yes" else "no";

  # ---------------------------------------------------------------------------
  # NestedUnpack - post-processing extension
  #
  # NZBGet only unpacks archives in the top level of a job directory. Some
  # posters pack an entire release folder (which itself holds a multi-volume
  # RAR set) into one outer archive: NZBGet extracts that outer layer, stops,
  # and Sonarr/Radarr only ever see the .nfo and the Sample. This extension
  # runs after NZBGet's own unpack and extracts whatever archives are left in
  # sub-folders, repeating for multi-level nesting.
  #
  # Layout NZBGet expects under ScriptDir: <Name>/manifest.json + the script
  # named in "main". Exit codes: 93 = success, 94 = error, 95 = nothing done.
  # ---------------------------------------------------------------------------
  nestedUnpackManifest = (pkgs.formats.json { }).generate "manifest.json" {
    main = "main.sh";
    name = "NestedUnpack";
    homepage = "";
    kind = "POST-PROCESSING";
    displayName = "Nested Unpack";
    version = "1.0.0";
    nzbgetMinVersion = "24";
    author = "nima";
    license = "MIT";
    about = "Extracts archives left in sub-folders after the main unpack (double-packed releases).";
    queueEvents = "";
    taskTime = "";
    requirements = [ "Requires bash, unrar and 7z (all present in the linuxserver/nzbget image)." ];
    description = [
      "NZBGet only unpacks archives in the top level of a job directory."
      "Some releases are double-packed: an outer archive contains a folder that"
      "itself holds a multi-volume RAR set. This extension walks the job directory"
      "after NZBGet's own unpack and extracts any archives found in sub-folders,"
      "repeating until nothing is left to extract."
    ];
    options = [
      {
        name = "Cleanup";
        displayName = "Cleanup";
        value = yesNo cfg.nestedUnpack.cleanup;
        description = [ "Delete archive volumes after they were extracted successfully." ];
        select = [
          "yes"
          "no"
        ];
      }
      {
        name = "MaxPasses";
        displayName = "MaxPasses";
        value = cfg.nestedUnpack.maxPasses;
        description = [ "Maximum number of extraction passes (each pass handles one level of nesting)." ];
        select = [
          1
          10
        ];
      }
    ];
    commands = [ ];
  };

  # Gets a store-path shebang like any writeShellScript; inside the container
  # (no /nix/store) NZBGet runs it via ShellOverride=.sh=/bin/bash instead.
  nestedUnpackScript = pkgs.writeShellScript "nzbget-nested-unpack.sh" ''
    set -o nounset
    set -o pipefail

    POSTPROCESS_SUCCESS=93
    POSTPROCESS_ERROR=94
    POSTPROCESS_NONE=95

    log() { printf '[%s] NestedUnpack: %s\n' "$1" "$2"; }

    dir="''${NZBPP_DIRECTORY:-}"
    cleanup="''${NZBPO_CLEANUP:-yes}"
    max_passes="''${NZBPO_MAXPASSES:-3}"
    # UnrarCmd/SevenZipCmd may contain extra arguments, so split on whitespace.
    read -r -a unrar_cmd <<<"''${NZBOP_UNRARCMD:-unrar}"
    read -r -a sevenzip_cmd <<<"''${NZBOP_SEVENZIPCMD:-7z}"

    if [[ "''${NZBPP_TOTALSTATUS:-}" != "SUCCESS" ]]; then
      log INFO "Skipping, job status is ''${NZBPP_STATUS:-unknown}"
      exit $POSTPROCESS_NONE
    fi

    if [[ -z "$dir" || ! -d "$dir" ]]; then
      log ERROR "Destination directory not found: '$dir'"
      exit $POSTPROCESS_ERROR
    fi

    # Only the first volume of a set should be handed to unrar/7z.
    is_first_volume() {
      local name="''${1,,}"
      case "$name" in
        *.part*.rar) [[ "$name" =~ \.part0*1\.rar$ ]] ;;
        *.rar | *.7z | *.7z.001 | *.zip) return 0 ;;
        *) return 1 ;;
      esac
    }

    # Extract an archive into the directory it lives in.
    extract() {
      local archive="$1" dest
      dest="$(dirname -- "$archive")"
      case "''${archive,,}" in
        *.rar) "''${unrar_cmd[@]}" x -o+ -p- -y -idp -- "$archive" "$dest/" </dev/null ;;
        *) "''${sevenzip_cmd[@]}" x -y -p- -o"$dest" -- "$archive" </dev/null ;;
      esac
    }

    # Remove all volumes belonging to a successfully extracted archive.
    cleanup_archive() {
      local archive="$1" base
      local -a volumes=()
      case "''${archive,,}" in
        *.part*.rar)
          base="''${archive%.[pP][aA][rR][tT]*}"
          volumes=("$base".[pP][aA][rR][tT]*.[rR][aA][rR])
          ;;
        *.rar)
          base="''${archive%.*}"
          volumes=("$archive" "$base".[rR][0-9][0-9]* "$base".[sS][0-9][0-9]*)
          ;;
        *.7z.001)
          base="''${archive%.001}"
          volumes=("$base".[0-9][0-9][0-9])
          ;;
        *.zip)
          base="''${archive%.*}"
          volumes=("$archive" "$base".[zZ][0-9][0-9])
          ;;
        *)
          volumes=("$archive")
          ;;
      esac
      local f
      for f in "''${volumes[@]}"; do
        [[ -f "$f" ]] && rm -f -- "$f"
      done
    }

    declare -A seen=()
    total_ok=0
    total_fail=0
    pass=0

    while ((pass < max_passes)); do
      pass=$((pass + 1))
      found_new=0

      while IFS= read -r -d ''' archive; do
        [[ -n "''${seen[$archive]:-}" ]] && continue
        seen[$archive]=1
        is_first_volume "$archive" || continue
        found_new=1

        rel="''${archive#"$dir"/}"
        log INFO "Pass $pass: extracting $rel"
        if output=$(extract "$archive" 2>&1); then
          total_ok=$((total_ok + 1))
          log INFO "Extracted $rel"
          [[ "$cleanup" == "yes" ]] && cleanup_archive "$archive"
        else
          rc=$?
          total_fail=$((total_fail + 1))
          log ERROR "Extraction failed (exit $rc): $rel"
          printf '%s\n' "$output" | tail -n 15 | sed 's/^/[DETAIL] /'
        fi
      done < <(find "$dir" -mindepth 2 -type f \
        \( -iname '*.rar' -o -iname '*.7z' -o -iname '*.7z.001' -o -iname '*.zip' \) \
        -print0 | sort -z)

      ((found_new)) || break
    done

    if ((total_fail > 0)); then
      log ERROR "$total_fail nested archive(s) failed to extract ($total_ok succeeded)"
      exit $POSTPROCESS_ERROR
    elif ((total_ok > 0)); then
      log INFO "Extracted $total_ok nested archive(s)"
      exit $POSTPROCESS_SUCCESS
    else
      log DETAIL "No nested archives found"
      exit $POSTPROCESS_NONE
    fi
  '';

  # Extensions directory, one sub-directory per extension. NZBGet's health
  # check insists ScriptDir is writable (the UI can install extensions into
  # it), so this is not mounted as ScriptDir directly: pod-media.nix mounts
  # it read-only under /defaults and copies it into ScriptDir at container
  # start, same as nzbget.conf.
  extensionsPackage =
    pkgs.runCommand "nzbget-extensions" { nativeBuildInputs = [ pkgs.shellcheck ]; }
      ''
        mkdir -p $out
        ${lib.optionalString cfg.nestedUnpack.enable ''
          shellcheck --shell=bash ${nestedUnpackScript}
          install -Dm644 ${nestedUnpackManifest} $out/NestedUnpack/manifest.json
          install -Dm755 ${nestedUnpackScript} $out/NestedUnpack/main.sh
        ''}
      '';
in
{
  options.services.pods.media.nzbget = {
    # Uses a string (not pkgs.writeText package) because secrets must be
    # interpolated at NixOS activation time via sops.templates, not at Nix
    # build time when the store is world-readable.
    configContent = lib.mkOption {
      type = lib.types.str;
      default = ''
        # Configuration file for NZBGet (generated by Nix)

        ##############################################################################
        ### PATHS
        MainDir=/config
        DestDir=/media/downloads/completed
        InterDir=/media/downloads/intermediate
        NzbDir=''${MainDir}/nzb
        QueueDir=''${MainDir}/queue
        TempDir=''${MainDir}/tmp
        WebDir=''${AppDir}/webui
        ScriptDir=''${MainDir}/scripts
        LockFile=''${MainDir}/nzbget.lock
        LogFile=''${MainDir}/nzbget.log
        ConfigTemplate=''${AppDir}/webui/nzbget.conf.template
        CertStore=''${AppDir}/cacert.pem

        ##############################################################################
        ### NEWS-SERVERS
        Server1.Active=${if cfg.server.enable then "yes" else "no"}
        Server1.Name=${cfg.server.name}
        Server1.Level=0
        Server1.Optional=no
        Server1.Group=0
        Server1.Host=${config.sops.placeholder."nzbget/server_host"}
        Server1.Encryption=${if cfg.server.encryption then "yes" else "no"}
        Server1.Port=${toString cfg.server.port}
        Server1.Username=${config.sops.placeholder."nzbget/server_username"}
        Server1.Password=${config.sops.placeholder."nzbget/server_password"}
        Server1.JoinGroup=no
        Server1.Connections=${toString cfg.server.connections}
        Server1.Retention=0
        Server1.CertVerification=Strict
        Server1.IpVersion=auto

        ##############################################################################
        ### SECURITY
        ControlIP=${cfg.controlIp}
        ControlPort=${toString cfg.controlPort}
        ControlUsername=${config.sops.placeholder."nzbget/username"}
        ControlPassword=${config.sops.placeholder."nzbget/password"}
        RestrictedUsername=
        RestrictedPassword=
        AddUsername=
        AddPassword=
        FormAuth=yes
        SecureControl=no
        SecurePort=6791
        SecureCert=
        SecureKey=
        AuthorizedIP=127.0.0.1
        CertCheck=yes
        UpdateCheck=stable
        DaemonUsername=root
        UMask=1000

        ##############################################################################
        ### CATEGORIES
        Category1.Name=Movies
        Category1.DestDir=
        Category1.Unpack=yes
        Category1.Extensions=
        Category1.Aliases=

        Category2.Name=Shows
        Category2.DestDir=
        Category2.Unpack=yes
        Category2.Extensions=
        Category2.Aliases=

        Category3.Name=Music
        Category3.DestDir=
        Category3.Unpack=yes
        Category3.Extensions=
        Category3.Aliases=

        Category4.Name=Software
        Category4.DestDir=
        Category4.Unpack=yes
        Category4.Extensions=
        Category4.Aliases=

        ##############################################################################
        ### INCOMING NZBS
        AppendCategoryDir=yes
        NzbDirInterval=5
        NzbDirFileAge=60
        DupeCheck=yes

        ##############################################################################
        ### DOWNLOAD QUEUE
        FlushQueue=yes
        ContinuePartial=yes
        PropagationDelay=0
        ArticleCache=500
        DirectWrite=yes
        WriteBuffer=1024
        FileNaming=auto
        RenameAfterUnpack=yes
        RenameIgnoreExt=.zip, .7z, .rar, .par2
        ReorderFiles=yes
        PostStrategy=balanced
        DiskSpace=250
        NzbCleanupDisk=yes
        KeepHistory=30
        FeedHistory=7
        SkipWrite=no
        RawArticle=no

        ##############################################################################
        ### CONNECTION
        ArticleRetries=3
        ArticleInterval=10
        ArticleTimeout=60
        ArticleReadChunkSize=4
        UrlRetries=3
        UrlInterval=10
        UrlTimeout=60
        RemoteTimeout=90
        DownloadRate=0
        UrlConnections=4
        UrlForce=yes
        MonthlyQuota=0
        QuotaStartDay=1
        DailyQuota=0

        ##############################################################################
        ### LOGGING
        WriteLog=rotate
        RotateLog=100
        ErrorTarget=both
        WarningTarget=both
        InfoTarget=both
        DetailTarget=log
        DebugTarget=log
        LogBuffer=1000
        NzbLog=yes
        CrashTrace=yes
        CrashDump=no
        TimeCorrection=0

        ##############################################################################
        ### DISPLAY (TERMINAL)
        OutputMode=loggable
        CursesNzbName=yes
        CursesGroup=no
        CursesTime=no
        UpdateInterval=200

        ##############################################################################
        ### CHECK AND REPAIR
        CrcCheck=yes
        ParCheck=auto
        ParRepair=yes
        ParScan=extended
        ParQuick=yes
        ParBuffer=16
        ParThreads=0
        ParIgnoreExt=.sfv, .nzb, .nfo
        ParRename=yes
        RarRename=yes
        DirectRename=no
        HealthCheck=park
        ParTimeLimit=0
        ParPauseQueue=no

        ##############################################################################
        ### UNPACK
        Unpack=yes
        DirectUnpack=no
        UnpackPauseQueue=no
        UnpackCleanupDisk=yes
        UnrarCmd=unrar
        SevenZipCmd=7z
        ExtCleanupDisk=.par2, .sfv
        UnpackIgnoreExt=.cbr
        UnpackPassFile=

        ##############################################################################
        ### EXTENSION SCRIPTS
        Extensions=${lib.optionalString cfg.nestedUnpack.enable "NestedUnpack"}
        ScriptOrder=
        ScriptPauseQueue=no
        # Extension scripts come from the nix store with patched shebangs; run
        # them with the container's own bash instead.
        ShellOverride=.sh=/bin/bash
        EventInterval=0
        ${lib.optionalString cfg.nestedUnpack.enable ''

          ##############################################################################
          ### NESTEDUNPACK
          NestedUnpack.Cleanup=${yesNo cfg.nestedUnpack.cleanup}
          NestedUnpack.MaxPasses=${toString cfg.nestedUnpack.maxPasses}
        ''}'';
      description = "NZBGet config content with sops placeholders for secrets";
    };

    # Extensions
    extensionsPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = extensionsPackage;
      description = "Generated directory with the NZBGet extensions; deployed into ScriptDir at container start";
    };

    nestedUnpack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Unpack archives left in sub-folders after the main unpack (double-packed releases)";
      };

      cleanup = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Delete archive volumes after they were extracted successfully";
      };

      maxPasses = lib.mkOption {
        type = lib.types.ints.between 1 10;
        default = 3;
        description = "Maximum number of extraction passes (each pass handles one level of nesting)";
      };
    };

    # Control settings
    controlIp = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "IP address to listen on (0.0.0.0 for all interfaces)";
    };

    controlPort = lib.mkOption {
      type = lib.types.port;
      default = 6789;
      description = "Port for NZBGet web interface";
    };

    # Server settings (secrets like host/username/password come from sops)
    server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable news server configuration";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "Primary Server";
        description = "News server name";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 563;
        description = "News server port (563 for SSL, 119 for plain)";
      };

      encryption = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use SSL/TLS encryption";
      };

      connections = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Maximum simultaneous connections";
      };
    };
  };
}
