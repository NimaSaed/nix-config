{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ===========================================================================
  # Firefox (shared) — minimal UI, native vertical tabs
  # ===========================================================================
  # Installs Firefox and manages its profile declaratively. Extensions are
  # intentionally NOT managed here: the toolbar layout captured in
  # `browser.uiCustomization.state` references the currently-installed
  # extension by its per-install UUID. Switching that extension to
  # Nix-managed would change its ID and break the placement, so addons are
  # left to be installed manually for now.

  programs.firefox = {
    enable = true;

    profiles.default = {
      isDefault = true;

      settings = {
        # --- Native vertical tabs (Firefox 136+) -------------------------
        "sidebar.revamp" = true;
        "sidebar.verticalTabs" = true;
        # Hide the sidebar launcher strip; expand-on-hover is the alternative.
        "sidebar.visibility" = "hide-sidebar";
        # Remove the sidebar tool icons (history, bookmarks, synced tabs,
        # AI chat) that the revamped vertical-tabs sidebar shows.
        "sidebar.main.tools" = "";

        # --- Allow userChrome.css to take effect -------------------------
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # --- Quality-of-life ---------------------------------------------
        "browser.aboutConfig.showWarning" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;

        # --- Toolbar / UI layout -----------------------------------------
        # Captured verbatim from about:config after arranging the toolbar by
        # hand. Pasted as-is inside a Nix indented string (double quotes are
        # literal there, and the JSON contains no `${`).
        "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"],"nav-bar":["back-button","forward-button","urlbar-container","unified-extensions-button"],"TabsToolbar":["tabbrowser-tabs","downloads-button"],"vertical-tabs":[],"PersonalToolbar":["personal-bookmarks"]},"seen":["developer-button","screenshot-button","_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action","reset-pbm-toolbar-button","ipprotection-button"],"dirtyAreaCache":["nav-bar","vertical-tabs","TabsToolbar","PersonalToolbar","unified-extensions-area"],"currentVersion":24,"newElementCount":9}'';
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
      '';
    };
  };
}
