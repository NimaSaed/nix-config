{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pods.media.nzbget;
in
{
  options.services.pods.media.nzbget = {
    configFile = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeText "nzbget.conf" ''
        # Configuration file for NZBGet

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
        Server1.Host=${cfg.server.host}
        Server1.Encryption=${if cfg.server.encryption then "yes" else "no"}
        Server1.Port=${toString cfg.server.port}
        Server1.Username=${cfg.server.username}
        Server1.Password=${cfg.server.password}
        Server1.JoinGroup=no
        Server1.Connections=${toString cfg.server.connections}
        Server1.Retention=0
        Server1.CertVerification=Strict
        Server1.IpVersion=auto

        ##############################################################################
        ### SECURITY
        ControlIP=${cfg.controlIp}
        ControlPort=${toString cfg.controlPort}
        ControlUsername=${cfg.controlUsername}
        ControlPassword=${cfg.controlPassword}
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
        Extensions=
        ScriptOrder=
        ScriptPauseQueue=no
        ShellOverride=
        EventInterval=0
      '';
      description = "Generated nzbget.conf configuration file";
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

    controlUsername = lib.mkOption {
      type = lib.types.str;
      default = "nzbget";
      description = "Username for web interface (set to empty to disable authentication)";
    };

    controlPassword = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Password for web interface (set to empty to disable authentication)";
    };

    # Server settings
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

      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "News server hostname";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 563;
        description = "News server port (563 for SSL, 119 for plain)";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "News server username";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "News server password (prefer using secrets)";
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
