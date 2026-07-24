_webos_registered_users()
{
	local path
	for path in /etc/hoster/webos/users/*.env; do
		[[ -e "${path}" ]] && basename "${path}" .env
	done
}

_webos()
{
	local current previous command command_index=1
	current="${COMP_WORDS[COMP_CWORD]}"
	previous="${COMP_WORDS[COMP_CWORD-1]}"

	if [[ "${COMP_WORDS[1]:-}" == -u || "${COMP_WORDS[1]:-}" == --user ]]; then
		if (( COMP_CWORD == 2 )); then
			COMPREPLY=($(compgen -W "$(_webos_registered_users)" -- "${current}"))
			return
		fi
		command_index=3
	fi
	command="${COMP_WORDS[command_index]:-}"

	if (( COMP_CWORD == command_index )); then
		COMPREPLY=($(compgen -W "status start stop restart logs url diagnostics version config user help" -- "${current}"))
		return
	fi
	if (( COMP_CWORD == 1 )); then
		COMPREPLY=($(compgen -W "--user status start stop restart logs url diagnostics version config user help" -- "${current}"))
		return
	fi
	if [[ "${previous}" == -u || "${previous}" == --user ]]; then
		COMPREPLY=($(compgen -W "$(_webos_registered_users)" -- "${current}"))
	elif [[ "${command}" == logs ]]; then
		COMPREPLY=($(compgen -W "--follow --lines" -- "${current}"))
	elif [[ "${command}" == config ]]; then
		local relative=$((COMP_CWORD - command_index))
		if (( relative == 1 )); then
			COMPREPLY=($(compgen -W "show edit set reset rotate-password" -- "${current}"))
		elif [[ "${COMP_WORDS[command_index+1]:-}" == show ]]; then
			COMPREPLY=($(compgen -W "--show-secrets" -- "${current}"))
		elif [[ "${COMP_WORDS[command_index+1]:-}" == set && ${relative} -eq 2 ]]; then
			COMPREPLY=($(compgen -W "title browser-user browser-password listen port encoder cpu debug resolution" -- "${current}"))
		elif [[ "${previous}" == encoder ]]; then
			COMPREPLY=($(compgen -W "h264enc h264enc-striped openh264enc jpeg" -- "${current}"))
		elif [[ "${previous}" == cpu || "${previous}" == debug ]]; then
			COMPREPLY=($(compgen -W "true false" -- "${current}"))
		elif [[ "${COMP_WORDS[command_index+1]:-}" == reset ]]; then
			COMPREPLY=($(compgen -W "title" -- "${current}"))
		fi
	elif [[ "${command}" == user ]]; then
		local action="${COMP_WORDS[command_index+1]:-}"
		if (( COMP_CWORD == command_index + 1 )); then
			COMPREPLY=($(compgen -W "list add remove show credentials set-default renew-certificate start stop restart" -- "${current}"))
		elif (( COMP_CWORD == command_index + 2 )); then
			if [[ "${action}" == add ]]; then
				COMPREPLY=($(compgen -u -- "${current}"))
			elif [[ "${action}" != list ]]; then
				COMPREPLY=($(compgen -W "$(_webos_registered_users)" -- "${current}"))
			fi
		elif [[ "${action}" == add ]]; then
			COMPREPLY=($(compgen -W "--listen --port --title --browser-user --prompt-password" -- "${current}"))
		fi
	fi
}
complete -F _webos webos
