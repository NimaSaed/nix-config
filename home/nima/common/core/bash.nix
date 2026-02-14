{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs.bash = {
    enable = true;

    # =========================================================================
    # Shell Aliases - Organized by category
    # =========================================================================
    shellAliases = {
      # Vi mode
      sl = "ls";

      # vim -> nvim
      vim = "nvim";

      # List directory contents
      la = "ls -AF";
      ll = "ls -hl";
      l = "ls -a";
      l1 = "ls -1";

      # Navigation
      ".." = "cd ..";
      "cd.." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "~" = "cd ~";

      # Clear screen
      c = "clear";
      k = "clear";
      cls = "clear";
      q = "exit";

      # Sudo
      "_" = "sudo";
      svim = "sudo vim";

      # Grep with color
      grep = "grep --color=auto";
      fgrep = "fgrep --color=auto";
      egrep = "egrep --color=auto";

      # Clipboard (X11)
      xclip = "xclip -selection c";

      # Python/Ruby
      p = "python";
      python3 = "python3.13";
      pip3 = "pip";

      # Cat with bat
      cat = "bat";
      ccat = "cat -n";

      # Docker -> Podman
      docker = "podman";
      arch = "docker run --rm -it archlinux/base";
      barch = "docker run --rm -it blackarch bash";
      dockerbash = "docker run --rm -it --entrypoint=/bin/bash";
      dockershell = "docker run --rm -it --entrypoint=/bin/sh";
      nginxservehere = ''docker run --rm -it -p 80:80 -p 443:443 -v "$(pwd):/srv/data" nimasaed/nginxserve'';

      # Edit configs
      vbrc = "vim ~/.bashrc";
      vbpf = "vim ~/.bash_profile";
      vrc = "vim ~/.vimrc";
      vi3c = "vim ~/.config/i3/config";
      vi3b = "vim ~/.config/i3/i3blocks.conf";

      # Notes shortcuts
      en = "cd $n && vim note_index.md && cd";
      gn = "ranger ~/Dropbox/Notes";
      sn = "tree $n";
      n = "~/.scripts/createNote.sh";
      t = "~/.scripts/todo";
    };

    # =========================================================================
    # Bash RC Extra - Custom functions and advanced configuration
    # =========================================================================
    bashrcExtra = ''
            # =======================================================================
            # Special Aliases (require -- flag)
            # =======================================================================
            alias -- -='cd -'  # Go back to previous directory

            # =======================================================================
            # Vi Mode Configuration
            # =======================================================================
            set -o vi
            bind -m vi-command 'Control-l: clear-screen'
            bind -m vi-insert 'Control-l: clear-screen'

            # =======================================================================
            # History Configuration
            # =======================================================================
            export HISTSIZE=10000000
            export HISTCONTROL=ignoreboth
            export HISTTIMEFORMAT="%d/%m/%y %T "

            # Make C-s work with C-r (search command)
            stty stop undef

            # Append to history, don't overwrite
            shopt -s histappend

            # =======================================================================
            # Environment Variables
            # =======================================================================
            export LC_ALL='en_US.UTF-8'
            export BAT_THEME="Solarized (light)"
            export n=~/Dropbox/Notes/

            # LESS configuration with colors
            export LESS=-R
            export LESS_TERMCAP_mb=$'\E[4;49;31m'     # begin blink
            export LESS_TERMCAP_md=$'\E[1;49;36m'     # begin bold
            export LESS_TERMCAP_me=$'\E[0m'           # reset bold/blink
            export LESS_TERMCAP_so=$'\E[7;49;35m'     # begin reverse video
            export LESS_TERMCAP_se=$'\E[0m'           # reset reverse video
            export LESS_TERMCAP_us=$'\E[4;49;34m'     # begin underline
            export LESS_TERMCAP_ue=$'\E[0m'           # reset underline

            # =======================================================================
            # Platform-Specific Configuration
            # =======================================================================
            if [ "$(uname)" = "Darwin" ]; then
                # macOS
                eval $(gdircolors -b ~/.dircolors/dircolors 2>/dev/null || echo "")
                alias ls='gls --color=auto'
                export TERM="screen-256color"
            else
                # Linux
                eval $(dircolors -b ~/.dircolors/dircolors 2>/dev/null || echo "")
                alias ls='ls --color=auto'
                export TERM="screen-256color"
                export TERMINAL="st"
                export TERMCMD="st"
                export RUBYOPT="-W0"
                export BROWSER="firefox"
            fi

            # =======================================================================
            # 1Password Integration
            # =======================================================================
            if command -v op &>/dev/null; then
                export SOPS_AGE_KEY_CMD="op item get 'SOPS Age Private Key' --fields password --reveal"
            fi

            # =======================================================================
            # FZF Configuration
            # =======================================================================
            eval "$(fzf --bash)"

            _fzf_comprun() {
              local command=$1
              shift

              case "$command" in
                cd)           fzf --preview 'tree -L 2 -C {} | head -200'   "$@" ;;
                export|unset) fzf --preview "eval 'echo \$'{}

      "         "$@" ;;
                ssh)          fzf --preview 'dig +short {}'                   "$@" ;;
                *)            fzf --preview 'bat -n --color=always {}' "$@" ;;
              esac
            }

            # =======================================================================
            # Custom Functions
            # =======================================================================

            # Git branch display for prompt
            function git_branch() {
                if [ ! -z "$(git branch 2>/dev/null | grep ^*)" ]; then
                    echo -n "$(git branch 2>/dev/null | grep ^* | colrm 1 2)"
                fi
            }

            # AWS profile display for prompt
            function get_aws_profile {
                if [ ! -z "$AWS_PROFILE" ]; then
                    echo "(''${AWS_PROFILE}[''${AWS_REGION}])";
                fi
            }

            # AWS profile selector
            function aws_profile() {
                local aws_home="$HOME/.aws"
                local profiles=($(cat ''${aws_home}/config | grep "\[profile" | sed 's/\[//g;s/\]//g' | cut -d " " -f 2))

                PS3="Select a profile: [none = 0] "
                select profile in ''${profiles[@]}; do
                    selected=$profile
                    break
                done

                unset $PS3
                if [ ! -z ''${profile} ]; then
                    export AWS_PROFILE="''${profile}"
                    export AWS_REGION=$(cat ''${aws_home}/config | sed -n "/''${profile}/,/\[/p" | grep region | cut -d '=' -f 2 | sed 's/ //g')
                    export AWS_DEFAULT_REGION=$(cat ''${aws_home}/config | sed -n "/''${profile}/,/\[/p" | grep region | cut -d '=' -f 2 | sed 's/ //g')
                    export AWS_ACCESS_KEY_ID=$(cat ''${aws_home}/credentials | sed -n "/''${profile}/,/\[/p" | grep aws_access_key_id | cut -d '=' -f 2 | sed 's/ //g')
                    export AWS_SECRET_ACCESS_KEY=$(cat ''${aws_home}/credentials | sed -n "/''${profile}/,/\[/p" | grep aws_secret_access_key | cut -d '=' -f 2 | sed 's/ //g')
                else
                    export AWS_PROFILE=""
                    export AWS_REGION=""
                    export AWS_ACCESS_KEY_ID=""
                    export AWS_SECRET_ACCESS_KEY=""
                    export AWS_SESSION_TOKEN=""
                    export AWS_ROLE_ARN=""
                fi
            }

            # AWS MFA authentication
            function aws_mfa () {
                aws_profile
                read -s -p "AWS MFA: " MFA

                aws_user=$(aws iam get-user | jq .User.UserName -r)
                mfa_arn=$(aws iam list-mfa-devices --user-name $aws_user | jq .MFADevices[0].SerialNumber -r)
                json=$(aws sts get-session-token --serial-number $mfa_arn --token-code $MFA)

                export AWS_SECRET_ACCESS_KEY=$(echo $json | jq -r .Credentials.SecretAccessKey)
                export AWS_SESSION_TOKEN=$(echo $json | jq -r .Credentials.SessionToken)
                export AWS_ACCESS_KEY_ID=$(echo $json | jq -r .Credentials.AccessKeyId)

                aws_admin_role=$(aws iam list-roles | jq -r '.Roles[] | select(.RoleName=="admin") | .Arn')
                json=$(aws sts assume-role --role-arn $aws_admin_role --role-session-name admin)

                export AWS_SECRET_ACCESS_KEY=$(echo $json | jq -r .Credentials.SecretAccessKey)
                export AWS_SESSION_TOKEN=$(echo $json | jq -r .Credentials.SessionToken)
                export AWS_ACCESS_KEY_ID=$(echo $json | jq -r .Credentials.AccessKeyId)
                export AWS_ROLE_ARN=$aws_admin_role
            }

            # AWS region selector
            function aws_region(){
                aws_regions=($(aws ec2 describe-regions --all-regions --query "Regions[].{Name:RegionName}" --output text))

                PS3="Select a region: [none = 0] "
                select region in ''${aws_regions[@]}; do
                    selected=$region
                    break
                done

                unset $PS3
                if [ ! -z ''${region} ]; then
                    export AWS_REGION="$selected"
                else
                    aws_profile
                fi
            }

            # Proxy management
            function SetProxy(){
                location=''${2:-"localhost:8080"}
                if [ "''${1:-set}" = "set" ]; then
                    echo "Setting http and https proxy to $location"
                    export HTTP_PROXY=http://''${location}
                    export HTTPS_PROXY=http://''${location}
                    export all_proxy=http://''${location}
                elif [ "''${1:-set}" = "unset" ]; then
                    echo "Unsetting http and https proxy"
                    unset -v HTTP_PROXY
                    unset -v HTTPS_PROXY
                    unset -v all_proxy
                fi
            }

            # Public IP lookup
            function public_ip() {
                public_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
                echo -n $public_ip
            }

            # Utility functions
            function news() { curl -s getnews.tech/"$@"; }
            function cht() { curl -s cht.sh/"$@"; }
            function rate() { curl -s rate.sx/"$@"; }
            function dic() { curl -s dict://dict.org/d:"$@"; }

            function wttr() {
                local request="wttr.in/''${1-}?0"
                [ "$COLUMNS" -lt 125 ] && request+='?n'
                curl -SH "Accept-Language: ''${LANG%_*}" --compressed "$request"
            }

            # Docker helper functions
            function sslscan(){ docker run --rm -e URL=''${1:-localhost} -e PORT=''${2:-443} nimasaed/sslscan; }
            function dockerbashhere() {
                dirname=''${PWD##*/}
                docker run --rm -it --entrypoint=/bin/bash -v `pwd`:/''${dirname} -w /''${dirname} "$@"
            }
            function dockershellhere() {
                dirname=''${PWD##*/}
                docker run --rm -it --entrypoint=/bin/sh -v `pwd`:/''${dirname} -w /''${dirname} "$@"
            }
            function dockerpwshhere() {
                dirname=''${PWD##*/}
                docker run --rm -it -v `pwd`:/''${dirname} -w /''${dirname} mcr.microsoft.com/powershell
            }
            function webgoat(){ docker run --rm -p 8080:8080 -p 9090:9090 -e TZ=Europe/Amsterdam --name webgoat webgoat/goatandwolf; }

            # List users (educational)
            function list_users() {
                while IFS=: read login a b c name e; do
                    printf "%-30s %s\n" "$login" "$name"
                done < /etc/passwd
            }

            # Parallels VM SSH helper (macOS)
            function vmssh(){
                all_vm=($(prlctl list -a 2>/dev/null | sed -E 's|([a-zA-Z0-9]) ([a-zA-Z0-9])|\1_\2|g' | sed 1d | awk '{print $1,$2,$4}' | sed 's/ /,/g' | sed 's/[{}]//g'))

                PS3="Select a VM: [none = 0] "
                select vm in ''${all_vm[@]}; do
                    selected=$vm
                    break
                done
                unset $PS3

                if [ ! -z ''${vm} ]; then
                    vm_info=($(echo $vm | sed 's/,/ /g'))
                    vm_uuid=''${vm_info[0]}
                    vm_status=''${vm_info[1]}
                    vm_name=''${vm_info[2]}

                    if [ $vm_status = "paused" ] || [ $vm_status = "stopped" ] || [ $vm_status = "suspended" ]; then
                        prlctl start $vm_uuid
                    fi

                    while [ $vm_status != "running" ]; do
                        echo $vm_info $vm_uuid $vm_status $vm_name
                        vm_status="$(prlctl status $vm_uuid | cut -d " " -f 4)"
                    done

                    prlctl exec $vm_uuid systemctl start ssh
                    sshkey=$(op read "op://Private/bd2up2giqd3pkzrtt6csqy24qa/public key" 2>/dev/null || cat ~/.ssh/id_ed25519.pub)
                    prlctl exec $vm_uuid "if [ -d \"/home/parallels/.ssh\" ]; then echo \"$sshkey\" > /home/parallels/.ssh/authorized_keys; else mkdir /home/parallels/.ssh; echo \"$sshkey\" > /home/parallels/.ssh/authorized_keys; fi; chown parallels:parallels -R /home/parallels/.ssh"

                    vm_ip=$(prlctl list -f $vm_uuid | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')

                    if [ ! -z $vm_ip ]; then
                        ssh parallels@''${vm_ip}
                    else
                        echo "no IP is available"
                    fi
                fi
            }

            # YouTube transcript helper
            #yt() {
            #    if [ "$#" -eq 0 ] || [ "$#" -gt 2 ]; then
            #        echo "Usage: yt [-t | --timestamps] youtube-link"
            #        echo "Use the '-t' flag to get the transcript with timestamps."
            #        return 1
            #    fi

            #    transcript_flag="--transcript"
            #    if [ "$1" = "-t" ] || [ "$1" = "--timestamps" ]; then
            #        transcript_flag="--transcript-with-timestamps"
            #        shift
            #    fi
            #    local video_link="$1"
            #    fabric-ai -y "$video_link" $transcript_flag
            #}

            # =======================================================================
            # Fabric AI Pattern Aliases
            # =======================================================================
            #if [ -d "$HOME/.config/fabric/patterns" ]; then
            #    for pattern_file in $HOME/.config/fabric/patterns/*; do
            #        if [ -f "$pattern_file" ]; then
            #            pattern_name=$(basename "$pattern_file")
            #            alias $pattern_name="fabric-ai --pattern $pattern_name"
            #        fi
            #    done
            #fi

            # =======================================================================
            # Custom Prompt (PS1) - Replaces Starship
            # =======================================================================
            PS1="\n"
            PS1+="\[\e[0;49;36m\]\[\e[0;49;96m\]\w\[\e[0;49;36m\] "
            PS1+="\[\e[0;49;33m\]\$(git_branch) "
            PS1+="\[\e[7;49;93m\]\$(get_aws_profile)"
            PS1+="\[\e[0;49;39m\]"
            PS1+="\[\e[1;49;39m\]>_\[\e[0;49;39m\] "
            PS2=">> "

            # =======================================================================
            # PATH Additions
            # =======================================================================
            export PATH="/Users/nima/.lmstudio/bin:$PATH"
            export PATH="/Users/nima/.local/bin:$PATH"

            # =======================================================================
            # Tmux Auto-Start (Optional - comment out if not desired)
            # =======================================================================
            if [ -z "$TMUX" ]; then
                tmux new -t Main
            fi

            # =======================================================================
            # MSF (Metasploit) Docker Aliases
            # =======================================================================
            msf_path="''${HOME}/Dropbox/Projects/dockers/msf/docker-compose.yml"
            if [ -f "$msf_path" ]; then
                alias msf="docker-compose -f ''${msf_path} up --detach"
                alias msf2="docker-compose -f ''${msf_path} up --scale msf=2 --detach"
                alias msf3="docker-compose -f ''${msf_path} up --scale msf=3 --detach"
                alias msfcon="docker attach msf-msf-1"
                alias msfcon2="docker attach msf-msf-2"
                alias msfcon3="docker attach msf-msf-3"
                alias msfstop="docker-compose -f ''${msf_path} stop"
                alias msfdown="docker-compose -f ''${msf_path} down"
            fi
    '';
  };
}
