function __webos_users
    for path in /etc/hoster/webos/users/*.env
        test -e "$path"; and basename "$path" .env
    end
end

complete -c webos -f
complete -c webos -s u -l user -r -a '(__webos_users)' -d 'Select a registered WebOS user'
complete -c webos -n '__fish_use_subcommand' -a 'status start stop restart logs url diagnostics version config user help'
complete -c webos -n '__fish_seen_subcommand_from logs' -l follow -d 'Follow logs'
complete -c webos -n '__fish_seen_subcommand_from logs' -l lines -d 'Number of lines'
complete -c webos -n '__fish_seen_subcommand_from config' -a 'show edit set reset rotate-password'
complete -c webos -n '__fish_seen_subcommand_from set' -a 'title browser-user browser-password listen port encoder cpu debug resolution'
complete -c webos -n '__fish_seen_subcommand_from reset' -a title
complete -c webos -n '__fish_seen_subcommand_from user' -a 'list add remove show credentials set-default renew-certificate start stop restart'
complete -c webos -n '__fish_seen_subcommand_from add' -l listen -r
complete -c webos -n '__fish_seen_subcommand_from add' -l port -r
complete -c webos -n '__fish_seen_subcommand_from add' -l title -r
complete -c webos -n '__fish_seen_subcommand_from add' -l browser-user -r
complete -c webos -n '__fish_seen_subcommand_from add' -l prompt-password
