{ ... }:

{
  home.file.".aerospace.toml".text = ''
    # Managed by home-manager — do not edit directly
    # Source: home/nima/common/optional/aerospace.nix

    after-login-command = []
    after-startup-command = []

    start-at-login = true

    # Normalizations
    enable-normalization-flatten-containers = true
    enable-normalization-opposite-orientation-for-nested-containers = true

    accordion-padding = 30
    default-root-container-layout = 'tiles'
    default-root-container-orientation = 'auto'

    key-mapping.preset = 'qwerty'

    on-focused-monitor-changed = ['move-mouse monitor-lazy-center']

    [gaps]
    inner.horizontal = 10
    inner.vertical   = 10
    outer.left       = 10
    outer.bottom     = 10
    outer.top        = 10
    outer.right      = 10

    [mode.main.binding]
    # App launchers
    alt-ctrl-a = 'exec-and-forget open /Applications/Alacritty.app'
    alt-ctrl-s = 'exec-and-forget open /Applications/Safari.app'
    alt-ctrl-d = 'exec-and-forget open /Applications/Slack.app'
    alt-ctrl-f = 'exec-and-forget open /Applications/Microsoft\ Teams.app'
    alt-ctrl-g = 'exec-and-forget open /System/Applications/Mail.app'
    alt-ctrl-h = 'exec-and-forget open /System/Applications/Calendar.app'

    # Layout
    alt-t = 'layout tiles horizontal vertical'
    alt-a = 'layout v_accordion'

    # Focus
    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'
    alt-f = 'fullscreen --no-outer-gaps'

    # Move
    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'

    # Resize
    alt-s = 'resize smart -50'
    alt-w = 'resize smart +50'

    # Workspaces
    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'

    shift-ctrl-alt-cmd-a = 'workspace 1'
    shift-ctrl-alt-cmd-s = 'workspace 2'
    shift-ctrl-alt-cmd-d = 'workspace 3'
    shift-ctrl-alt-cmd-f = 'workspace 4'
    shift-ctrl-alt-cmd-g = 'workspace 5'
    shift-ctrl-alt-cmd-h = 'workspace 6'

    # Move node to workspace
    alt-shift-1 = ['move-node-to-workspace 1', 'workspace 1']
    alt-shift-2 = ['move-node-to-workspace 2', 'workspace 2']
    alt-shift-3 = ['move-node-to-workspace 3', 'workspace 3']
    alt-shift-4 = ['move-node-to-workspace 4', 'workspace 4']
    alt-shift-5 = ['move-node-to-workspace 5', 'workspace 5']
    alt-shift-6 = ['move-node-to-workspace 6', 'workspace 6']
    alt-shift-7 = ['move-node-to-monitor 1', 'workspace 7']

    # Service mode
    alt-shift-s = 'mode service'

    [mode.service.binding]
    esc       = ['reload-config', 'mode main']
    r         = ['flatten-workspace-tree', 'mode main']
    f         = ['layout floating tiling', 'mode main']
    backspace = ['close-all-windows-but-current', 'mode main']

    alt-shift-h = ['join-with left', 'mode main']
    alt-shift-j = ['join-with down', 'mode main']
    alt-shift-k = ['join-with up', 'mode main']
    alt-shift-l = ['join-with right', 'mode main']

    # Window assignment rules

    # Terminal → workspace 1
    [[on-window-detected]]
    if.app-id = 'org.alacritty'
    run = 'move-node-to-workspace 1'

    # Browser → workspace 2
    [[on-window-detected]]
    if.app-id = 'com.apple.Safari'
    run = 'move-node-to-workspace 2'

    [[on-window-detected]]
    if.app-id = 'com.brave.Browser'
    run = 'move-node-to-workspace 2'

    [[on-window-detected]]
    if.app-id = 'org.mozilla.firefox'
    run = 'move-node-to-workspace 2'

    # Bitwarden → floating (AeroSpace doesn't support resize in on-window-detected)
    [[on-window-detected]]
    if.app-id = 'com.bitwarden.desktop'
    run = 'layout floating'

    # Communication → workspace 3
    [[on-window-detected]]
    if.app-id = 'com.tinyspeck.slackmacgap'
    run = 'move-node-to-workspace 3'

    [[on-window-detected]]
    if.app-id = 'com.microsoft.teams2'
    run = 'move-node-to-workspace 3'

    # Mail & Calendar → workspace 4
    [[on-window-detected]]
    if.app-id = 'com.apple.mail'
    run = 'move-node-to-workspace 4'

    [[on-window-detected]]
    if.app-id = 'com.apple.iCal'
    run = 'move-node-to-workspace 4'

    # 3D / CAD → workspace 5
    [[on-window-detected]]
    if.app-id = 'com.bambulab.bambu-studio'
    run = 'move-node-to-workspace 5'

    [[on-window-detected]]
    if.app-id = 'org.freecadweb.FreeCAD'
    run = 'move-node-to-workspace 5'

    [[on-window-detected]]
    if.app-id = 'org.blenderfoundation.blender'
    run = 'move-node-to-workspace 5'
  '';
}
