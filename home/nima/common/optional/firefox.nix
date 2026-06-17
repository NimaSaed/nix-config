{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # rycee's NUR addon set, scoped to this system's architecture.
  addons = inputs.firefox-addons.packages.${pkgs.system};

  # Bundled (app-provided) search engines to hide. eBay ships region-specific
  # ids (ebay-de, ebay-nl, …) and only the active one matters, so hide them
  # all — hiding an inactive id is a harmless no-op.
  hiddenSearchEngineIds =
    [
      "google"
      "bing"
      "amazondotcom-us"
      "ddg"
      "wikipedia"
      "perplexity"
    ]
    ++ map (r: "ebay${r}") [
      ""
      "-at"
      "-au"
      "-be"
      "-ca"
      "-ch"
      "-de"
      "-es"
      "-fr"
      "-ie"
      "-it"
      "-nl"
      "-pl"
      "-uk"
    ];
in
{
  # ===========================================================================
  # Firefox (shared) — minimal UI, native vertical tabs
  # ===========================================================================
  # Installs Firefox and manages its profile (and extensions) declaratively.
  # The toolbar layout in `browser.uiCustomization.state` keys off each
  # extension's intrinsic addon ID (e.g. Bitwarden's
  # `{446900e4-71c2-419f-a6a7-df9c091e268b}`), which is identical whether the
  # extension is installed by hand or via Nix — so Nix-managing addons does
  # NOT change the widget IDs and the placement stays valid.

  programs.firefox = {
    enable = true;

    # Let the Bitwarden browser extension talk to the bitwarden-desktop app
    # (browser unlock / autofill via the native messaging bridge).
    nativeMessagingHosts = [ pkgs.bitwarden-desktop ];

    profiles.default = {
      isDefault = true;

      # --- Extensions (declarative) --------------------------------------
      # `force` is required once `extensions.settings` is used, and makes
      # Home Manager the sole owner of this profile's extension set (add-ons
      # installed by hand will be removed on the next switch).
      extensions = {
        force = true;
        packages = [
          addons.bitwarden
          addons.vimium
          addons.ublock-origin
          addons.privacy-badger
        ];

        # Pin each add-on's state so there's no "enable this add-on?" prompt.
        settings."{446900e4-71c2-419f-a6a7-df9c091e268b}".force = true; # Bitwarden
        settings."{d7742d87-e61d-4b78-b8a1-b469842139fa}".force = true; # Vimium
        settings."uBlock0@raymondhill.net".force = true; # uBlock Origin
        settings."jid1-MnnxcxisBPnSXQ@jetpack".force = true; # Privacy Badger
      };

      settings = {
        # --- Native vertical tabs (Firefox 136+) -------------------------
        "sidebar.revamp" = true;
        "sidebar.verticalTabs" = true;
        # Hide the sidebar launcher strip; expand-on-hover is the alternative.
        "sidebar.visibility" = "hide-sidebar";
        # Remove the sidebar tool icons (history, bookmarks, synced tabs,
        # AI chat) that the revamped vertical-tabs sidebar shows. NOTE: on a
        # fresh profile this pref is not enough — Firefox's one-time sidebar
        # migration writes the default tools *after* user.js is applied, so
        # the icons show until the sidebar settings panel is opened once.
        # The userChrome.css rule below hides them deterministically instead.
        "sidebar.main.tools" = "";

        # --- Allow userChrome.css to take effect -------------------------
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # --- Auto-enable Nix-installed extensions ------------------------
        # Firefox defaults this to 15 (all scopes), which silently DISABLES
        # every profile-/side-loaded add-on until approved by hand. 0 turns
        # that off so the extensions managed above come up enabled.
        "extensions.autoDisableScopes" = 0;

        # --- Disable the built-in password manager (Bitwarden is used) ---
        "signon.rememberSignons" = false; # no save-password prompts / store
        "signon.autofillForms" = false; # don't autofill saved logins
        "signon.generation.enabled" = false; # no "suggest strong password"
        "signon.management.page.breach-alerts.enabled" = false;

        # --- Quality-of-life ---------------------------------------------
        # Never show the bookmarks toolbar (also accepts "always"/"newtab").
        "browser.toolbars.bookmarks.visibility" = "never";
        "browser.aboutConfig.showWarning" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        # New tab / home stay on about:newtab / about:home (NOT about:blank,
        # which userContent.css can't recolor — it always shows Firefox's
        # default near-black canvas). The userContent rule below paints these
        # Deep Blue and hides all their content, so they look blank but themed.
        "browser.startup.homepage" = "about:home";

        # --- Telemetry / data collection ---------------------------------
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "app.shield.optoutstudies.enabled" = false; # no Shield studies
        "datareporting.policy.dataSubmissionEnabled" = false;
        "browser.discovery.enabled" = false; # no "recommended extensions"

        # --- New-tab clutter (Pocket itself is gone as of FF 151) --------
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.feeds.section.highlights" = false;

        # --- Form autofill (Bitwarden handles logins; kill the rest) -----
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.creditCards.enabled" = false;

        # --- Security ----------------------------------------------------
        "dom.security.https_only_mode" = true; # HTTPS-only mode
        "network.trr.mode" = 2; # DNS-over-HTTPS (opportunistic)
        "browser.contentblocking.category" = "strict"; # strict tracking protection

        # --- UX ----------------------------------------------------------
        "browser.uidensity" = 1; # compact toolbar (pairs well with vertical tabs)
        "browser.download.useDownloadDir" = false; # always ask where to save
        "browser.tabs.closeWindowWithLastTab" = false;
        "browser.aboutwelcome.enabled" = false; # no onboarding tour
        "browser.urlbar.suggest.searches" = false; # no search-engine suggestions

        # --- Dark base theme ---------------------------------------------
        # Makes the surfaces userChrome.css doesn't reach (context menus, the
        # urlbar dropdown, popups) render dark so they don't clash with the
        # Deep Blue chrome.
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";

        # --- Misc cleanup ------------------------------------------------
        "browser.shell.checkDefaultBrowser" = false; # no "make default" nag
        # Firefox Suggest / sponsored urlbar results off.
        "browser.urlbar.quicksuggest.enabled" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
        # Remaining telemetry / recommendation channels.
        "app.normandy.enabled" = false;
        "extensions.htmlaboutaddons.recommendations.enabled" = false;
        "extensions.getAddons.showPane" = false;

        # --- Toolbar / UI layout -----------------------------------------
        # Deterministic layout: all four extension buttons live in `nav-bar`
        # so they're pinned to the toolbar (Bitwarden included), and
        # `unified-extensions-area` (the puzzle-menu overflow) is left empty.
        # Widget IDs derive from each add-on's intrinsic ID, so they're stable
        # across machines. Double quotes are literal in this Nix indented
        # string and the JSON contains no `${`.
        "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":[],"nav-bar":["back-button","forward-button","urlbar-container","unified-extensions-button","downloads-button","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action","_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action","jid1-mnnxcxisbpnsxq_jetpack-browser-action","ublock0_raymondhill_net-browser-action","vertical-spacer"],"toolbar-menubar":["menubar-items"],"TabsToolbar":[],"vertical-tabs":["tabbrowser-tabs"],"PersonalToolbar":["personal-bookmarks"]},"seen":["developer-button","screenshot-button","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action","reset-pbm-toolbar-button","ipprotection-button","_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action","jid1-mnnxcxisbpnsxq_jetpack-browser-action","ublock0_raymondhill_net-browser-action"],"dirtyAreaCache":["nav-bar","vertical-tabs","TabsToolbar","PersonalToolbar","unified-extensions-area"],"currentVersion":24,"newElementCount":9}'';
      };

      # --- Declarative search engines ------------------------------------
      # European, privacy-leaning engines (from european-alternatives.eu).
      # `force` is required to overwrite Firefox's existing search.json store.
      # GOOD (good.de) is omitted: its query-URL format isn't reliably
      # documented and a wrong template would just break that engine.
      search = {
        force = true;
        default = "ecosia";
        privateDefault = "ecosia";
        order = [
          "ecosia"
          "qwant"
          "mojeek"
          "swisscows"
          "metager"
        ];
        engines = {
          # Keyed by engine id (HM 25.11 requires ids, not display names).
          "ecosia" = {
            urls = [ { template = "https://www.ecosia.org/search?q={searchTerms}"; } ];
            definedAliases = [ "@ec" ];
          };
          "qwant" = {
            urls = [ { template = "https://www.qwant.com/?q={searchTerms}"; } ];
            definedAliases = [ "@qw" ];
          };
          "mojeek" = {
            name = "Mojeek";
            urls = [ { template = "https://www.mojeek.com/search?q={searchTerms}"; } ];
            definedAliases = [ "@mj" ];
          };
          "swisscows" = {
            name = "swisscows";
            urls = [ { template = "https://swisscows.com/en/web?query={searchTerms}"; } ];
            definedAliases = [ "@sc" ];
          };
          "metager" = {
            name = "metaGer";
            urls = [ { template = "https://metager.org/meta/meta.ger3?eingabe={searchTerms}"; } ];
            definedAliases = [ "@mg" ];
          };
        }
        # Hide the bundled engines (keyed by their search-config-v2 ids).
        // lib.genAttrs hiddenSearchEngineIds (_: { metaData.hidden = true; });
      };

      # userChrome.css — hide the nav-bar widgets Firefox force-re-adds even
      # when removed from uiCustomization.state. Keyboard-only workflow, so
      # back/forward and the extensions (puzzle) button are all dead weight;
      # only the address bar stays visible.
      userChrome = ''
        #back-button,
        #forward-button,
        #unified-extensions-button {
          display: none !important;
        }

        /* Hide the built-in sidebar tool icons (history, bookmarks, synced
           tabs, AI chat). Deterministic backstop for `sidebar.main.tools`,
           which Firefox's first-run migration overrides on a fresh profile.
           Extension sidebar buttons and the customize gear are left intact. */
        #sidebar-main moz-button[view="viewHistorySidebar"],
        #sidebar-main moz-button[view="viewBookmarksSidebar"],
        #sidebar-main moz-button[view="viewSyncedTabsSidebar"],
        #sidebar-main moz-button[view="viewGenaiChatSidebar"] {
          display: none !important;
        }

        /* ===== Nebius color theme (browser chrome) ================== */
        :root {
          --nb-deep-blue: #052B42;   /* primary chrome background      */
          --nb-surface:   #0A3B58;   /* lifted surface (fields / tabs) */
          --nb-lime:      #DAFF33;   /* primary accent (active state)  */
          --nb-violet:    #5D52F6;   /* secondary accent               */
          --nb-lavender:  #C1C1FF;   /* soft accent (hover)            */
          --nb-light-blue: #F0F8FF;  /* foreground text / icons        */

          /* Theme variables consumed by toolbars, fields and sidebar. */
          --lwt-accent-color: var(--nb-deep-blue) !important;
          --toolbar-bgcolor: var(--nb-deep-blue) !important;
          --toolbar-color: var(--nb-light-blue) !important;
          --lwt-text-color: var(--nb-light-blue) !important;
          --toolbarbutton-icon-fill: var(--nb-light-blue) !important;
          --toolbarbutton-icon-fill-attention: var(--nb-lime) !important;

          --toolbar-field-background-color: var(--nb-surface) !important;
          --toolbar-field-color: var(--nb-light-blue) !important;
          --toolbar-field-focus-background-color: var(--nb-surface) !important;
          --toolbar-field-focus-color: var(--nb-light-blue) !important;
          --toolbar-field-focus-border-color: var(--nb-lime) !important;

          /* Text-selection highlight inside the address/search bar. */
          --lwt-toolbar-field-highlight: var(--nb-lime) !important;
          --lwt-toolbar-field-highlight-text: var(--nb-deep-blue) !important;

          --sidebar-background-color: var(--nb-deep-blue) !important;
          --sidebar-text-color: var(--nb-light-blue) !important;

          --tab-selected-bgcolor: var(--nb-surface) !important;
          --tab-selected-textcolor: var(--nb-light-blue) !important;
        }

        /* Paint the main chrome surfaces directly (robust regardless of
           the active built-in theme). */
        #navigator-toolbox,
        #nav-bar,
        #TabsToolbar,
        #PersonalToolbar,
        #sidebar-main,
        #tabbrowser-tabbox {
          background-color: var(--nb-deep-blue) !important;
          color: var(--nb-light-blue) !important;
        }

        /* Color the content viewport itself so there's no black flash before
           a page (or the new-tab page) paints. */
        #tabbrowser-tabpanels,
        .browserStack,
        browser[type="content"] {
          background-color: var(--nb-deep-blue) !important;
        }

        /* Active tab: lifted surface with a lime accent bar. */
        .tabbrowser-tab[visuallyselected="true"] .tab-background {
          background-color: var(--nb-surface) !important;
          box-shadow: inset 3px 0 0 0 var(--nb-lime) !important;
        }

        /* Tab hover: soft lavender wash. */
        .tabbrowser-tab:hover:not([visuallyselected="true"]) .tab-background {
          background-color: color-mix(in srgb, var(--nb-lavender) 12%, transparent) !important;
        }

        /* Lime text-selection in the address/search bar (fallback for the
           --lwt-toolbar-field-highlight* variables above). */
        #urlbar-input::selection,
        #urlbar .urlbar-input::selection,
        #searchbar .searchbar-textbox::selection {
          background-color: var(--nb-lime) !important;
          color: var(--nb-deep-blue) !important;
        }
      '';

      # userContent.css — styles web *content* pages (the chrome is handled
      # by userChrome.css above). Recolors the New Tab / Home page, which is
      # Firefox content (not chrome) and so unreachable from userChrome.
      userContent = ''
        /* New Tab / Home page: paint it Deep Blue and hide every content
           element (search box, shortcuts, sections, personalize button) so
           it looks blank but matches the theme. Coloring <html> guarantees
           the whole viewport is filled even after the content is hidden. */
        @-moz-document url("about:home"), url("about:newtab") {
          html,
          body {
            background-color: #052B42 !important;
            color: #F0F8FF !important;
          }
          main,
          .personalize-button,
          .customize-menu {
            display: none !important;
          }
        }
      '';
    };
  };
}
