#!/usr/bin/env bash
#
#  Gman : a CLI helper tool for daily Git usage.
#
#  Project home : https://github.com/pmachart/g-man
#  Released under MIT License
#

set_user_config() {

  ############## USER CONFIG ##############

  REVERSED=0 # optionally reversing argument order
  TESTCMD='./node_modules/.bin/jest'
  #if [[ -f package.json ]] ; then TESTCMD=$(node -pe "require('./package.json').scripts.test") ; fi
  TESTCACHEFOLDER='/tmp/jest_rs' # /!\ gets rm-rf'ed when test actions are called with nocache arg
  EXTMAIN='js' # file extension of the tested language
  EXTTEST='test' # file extension of the test files
  LINTCMD='./node_modules/.bin/tslint'
  CLIPBOARDCMD='xclip' # command to send `view` output to clipboard
  DEFAULTACTION='view' # default action if none is supplied

  ############ END USER CONFIG ############

  DEBUG=0 # verbose debug output

}

display_help() { # TODO
cat <<'EOF'
usage: g [-h | --help] [-r | --reversed] [-c | --clear] [-d | --debug] [s | show]
         [1-99] [cd] [v | view] [p | print] [clip] [bak] [rm] [rmf | rm -f]
         [touch] [vi | vim] [n | nano] [vs | code] [at | atom] [c | cat] [b | bat] [m | most]
         [l] [ll | l -l] [la | l -A] [lr | l -R] [lla | l -lA] [llr | l -lR] [lar | l -AR] [llar | l -lAR]
         [a | add] [oops] [d | diff] [dc | diff --cached] [dh | diff HEAD] [ds]
         [u | co | checkout] [h | hist] [r | reset]
         [t] [tc | t --coverage] [tu | t --updateSnapshot] [tw | t --watch] [tn | t --no-cache]
         [lt | lint] [ltf | lintfix]

Go to https://github.com/pmachart/g-man for the full documentation.
EOF
}

LOGGER() { # simple debug output wrapper with some formatting
  ((! DEBUG)) && return 0
  local OPT
  [[ ${1} == '-n' ]] && { shift ; OPT='-n' ; }
  [[ ${1} == '-h' ]] && { shift ; printf '━%.0s' $(seq $(tput cols)) ; }
  echo ${OPT} "${FUNCNAME[1]^^} ${1}"
}

build_gitstatus() { LOGGER -h # `git status` output is stored in two text files
  rm -f "${GITSTATUSFILE}"
  mkdir -p $(dirname "${GITSTATUSFILE}")
  git status -u --porcelain | cut -c 4- > "${GITSTATUSFILE}" # one for parsing
  ((DEBUG)) && cat "${GITSTATUSFILE}"
  rm -f "${GITSTATUSPRETTY}"
  git -c color.status=always status -su | nl -ba -s' ' > "${GITSTATUSPRETTY}" # one for display
  GITSTATUS_LENGTH="$(wc -l < "${GITSTATUSFILE}")"
}

show_gitstatus() { LOGGER -h
  if (( ${GITSTATUS_LENGTH} > 0 )) ; then
    echo
    cat "${GITSTATUSPRETTY}"
    echo
  else
    echo -e '\n   "Looks clear."\n'
  fi
}

add_to_filelist() {
  FILE=$(sed -n "${1}p" < "${GITSTATUSFILE}")
  ((NBFILES++))

  FILELIST+=" ${FILE}"
  FILEARRAY+=("${FILE}")

  LOGGER "${FILE}"
  FILELIST="${FILELIST# }" # strip first space
}

build_filelist() { LOGGER -h "${ARG}"
  local FIRST=0
  local LAST=0

  if [[ ${ARG} =~ ^[0-9]+-[0-9]+$ ]] ; then # parameter is range of numbers
    FIRST=$(echo "${ARG}" | cut --fields=1 --delimiter='-')
    LAST=$(echo "${ARG}" | cut --fields=2 --delimiter='-')

    if (( ${FIRST} > ${LAST} )) ; then # swap range
      local -r TEMP=${LAST}
      LAST=${FIRST}
      FIRST=${TEMP}
    fi
    local i
    for i in $(seq "${FIRST}" "${LAST}") ; do
      add_to_filelist "${i}"
    done
  else # single parameter
    if grep --quiet '^[0-9]*$' <<< "${ARG}" ; then # numeric check
      add_to_filelist "${ARG}"
    else
      echo "Error : invalid parameter ${ARG}" >&2 ; return 10
    fi
  fi
  ((DEBUG)) && echo -e "\nEnd build_filelist : [${FILELIST}]"  || return 0
}

send_to_clipboard() {
  # TODO : this does not work for filenames with spaces : does not send quotes to xclip. try with xargs ?
  [[ ! $(command -v "${CLIPBOARDCMD}") ]] && {
    printf '  The specified clipboard command "%s" is not installed.\n' ${CLIPBOARDCMD}
    printf '  Please install it or configure another one in the user config.\n'
    eval echo -n ${FILELIST}
    return 0
  }
  eval echo -n ${FILELIST} | ${CLIPBOARDCMD}
}

display_files() { ((DEBUG))
  echo -e "\nSelected files :\n$(IFS=$'\n'; echo "${FILEARRAY[*]}" | sed "s/^/  /";)\n"
  send_to_clipboard
}


require_files_exist() { LOGGER
  FILELIST=''
  local NOFILES=1
  local NEWFILEARRAY=()
  local TESTFILE=''

  for FILE in "${FILEARRAY[@]}" ; do
    TESTFILE=${FILE}
    TESTFILE=${TESTFILE##\"}
    TESTFILE=${TESTFILE%%\"}
    if [[ -f "${TESTFILE}" ]] ; then
      FILELIST+="${FILE} "
      NEWFILEARRAY+=("${FILE}")
      NOFILES=0
    else
      echo "${BOLD}${RED}Warning:${RESET} File ${YELLOW}${FILE}${RESET} does not exist."
    fi
  done

  FILEARRAY=(${NEWFILEARRAY[@]})

  ((NOFILES)) && echo "${BOLD}${RED}Error: None of the selected files exist. Aborting.${RESET}" >&2
  return ${NOFILES}
}

get_folder_name() { LOGGER -n -h "${FILE}"
  # TODO : handle symlinks
  declare -n RETURN=$1
  RETURN="${2}"
  if [[ -f "${2}" ]] ; then
    RETURN=$(dirname "${2}")
    ((DEBUG)) && echo ": ${RETURN}"
  fi
}

require_confirmation() { LOGGER
  local YN
  local MSGYES
  local MSGNO
  [[ -z ${2} ]] && MSGYES='Proceeding.' || MSGYES=${2}
  [[ -z ${3} ]] && MSGNO='Aborting.'    || MSGNO=${3}
  while true; do
    read -p "${1} (y/n) > " YN
    YN=$(echo "${YN}" | awk '{print tolower($0)}')
    case ${YN} in
      y|yes ) echo "${MSGYES}"; return 0 ;;
      n|no )  echo "${MSGNO}";  return 20 ;;
      * ) echo "Please answer with yes or no". ;;
    esac
  done
}

run_action() { LOGGER -h "${ACTION}"

  local OPTIONS=''

  if [[ ${NBFILES} -eq 0 ]]; then
    # no file in the list ? get all the files !
    ((DEBUG)) && echo 'No file in list. Building gitstatus.'
    build_gitstatus
    ARG="1-${GITSTATUS_LENGTH}"
    build_filelist || return ${?} # passing returns up
  fi

  ((DEBUG)) && echo -e "${BOLD}--> ${RED}Running action : ${ACTION} ${FILELIST}${RESET}"
  case ${ACTION} in

    'show' | 's')
      show_gitstatus
      return 0
      ;;
    'add' | 'a')   eval git add "${ARGOPTION}" -- ${FILELIST} ;;
    'oops')
      eval git add -- ${FILELIST}
      git commit --amend --no-edit --no-verify
      ;;
    d*s*) OPTIONS+=" --unified=0 --ignore-space-at-eol --color-words='[[:alnum:]]+|[^[:space:]]'" ;;&
    d*c*) OPTIONS+=" --cached" ;;&
    d*h*) OPTIONS+=" HEAD" ;;&
    d*)
      eval git diff "${OPTIONS}" "${ARGOPTION}" -- ${FILELIST}
      ;;
    'checkout' | 'co' | 'u')
      for FILE in "${FILEARRAY[@]}" ; do
        if git diff --name-only --cached | grep "^${FILE#$GITROOT}$" >/dev/null ; then # file is staged ?
          eval git reset HEAD -- ${FILE} # avoids unnecessary output on git checkout
        fi
        eval git checkout -- ${FILE}
      done
      ;;
    # 'stash')       eval git stash push -- ${FILELIST} ;; # TODO make sure this works as excpected
    'hist'  | 'h') eval git log -u "${ARGOPTION}" -- ${FILELIST} ;;
    'reset' | 'r') eval git reset -- ${FILELIST} ;;

    'lintfix' | 'ltf') OPTIONS+=' --fix --stdin --stdin-filename' ;;&
    'lint' | 'lt')
      eval ${LINTCMD} "${OPTIONS}" ${FILELIST}
      ;;

    'bak')
      for FILE in "${FILEARRAY[@]}" ; do
        require_files_exist && eval cp ${FILE} ${FILE}.bak
      done
      ;;

    'touch')       eval touch ${FILELIST} ;; # sometimes used as a git quickfix
    'vim'  | 'vi') eval vim  ${FILELIST} ;;
    'nano' | 'n')  eval nano ${FILELIST} ;;
    'code' | 'vs') eval code ${FILELIST} ;;
    'atom' | 'at') eval atom ${FILELIST} ;;
    'cat'  | 'c')  require_files_exist && eval cat ${FILELIST} ;;
    'bat'  | 'b')  require_files_exist && eval bat "${ARGOPTION}" ${FILELIST} ;;
    'most' | 'm')  eval most  ${FILELIST} ;;
    'print'| 'p')  echo -e " ${FILELIST}" ;;
    'view' | 'v')  display_files ;;
    'clip') send_to_clipboard ;;

    'cd')
      local FILE_DIR
      get_folder_name FILE_DIR "${FILE}"
      WORKDIR="${FILE_DIR}"
      ;;
    l*l*) OPTIONS+='l' ;;&
    l*a*) OPTIONS+='A' ;;&
    l*r*) OPTIONS+='R' ;;&
    l*)
      # TODO : customizable LS command (eg: replace with exa)
      local FILE_DIR
      get_folder_name FILE_DIR "${FILE}"
      echo "> ls ${FILE_DIR}"
      ls -BhF${OPTIONS} "${ARGOPTION}" --group-directories-first "${FILE_DIR}"
      ;;

    rmf) OPTIONS+=' -f' ;;&
    rm*)
      require_files_exist || return ${?}
#      eval git rm "${OPTIONS}" "${ARGOPTION}" -- ${FILELIST} 2>/dev/null || rm -i "${OPTIONS}" ${FILELIST}
      eval git rm "${OPTIONS}" "${ARGOPTION}" ${FILELIST} 2>/dev/null || rm -i "${OPTIONS}" ${FILELIST}
      ;;

    t*)   if [[ -z ${TESTCMD} ]] ; then echo 'No test command configured' ; return 30 ; fi ;;&
    t*c*) OPTIONS+=' --coverage' ;;&
    t*u*) OPTIONS+=' --updateSnapshot' ;;&
    t*w*) OPTIONS+=' --watch' ;;&
    t*n*) OPTIONS+=' --no-cache' ; rm -rf "${TESTCACHEFOLDER}" ;;&
    t*)
      for FILE in "${FILEARRAY[@]}" ; do
        local BASEDIR=$(dirname ${FILE})
        local RELDIR=${BASEDIR#$GITROOT}
        local BASENAME=$(basename ${FILE})
        local BASENOEXT=${BASENAME%.${EXTMAIN}}
        local BASENOEXT=${BASENOEXT%.${EXTTEST}}
        type -t horiz && horiz || echo '----------------------------'
        echo "  ${CYAN}${BOLD}Testing ${RED}${BASENOEXT}.${EXTMAIN}${CYAN} with params:${RED}${TESTPARAMS}${RESET}"
        type -t horiz && horiz || echo '----------------------------'
        eval ${TESTCMD} ${TESTPARAMS} ${RELDIR}/${BASENOEXT}.${EXTTEST}.${EXTMAIN}
        if [[ ${ARG} =~ o && ${ARG} =~ c ]] ; then
          xdg-open ./coverage/lcov-report/${BASENOEXT}.${EXTMAIN}.html > /dev/null 2>/dev/null # TODO redirect too long
        fi
      done
      ;;

    *)
      echo "Warning : unrecognized action : ${ACTION}"
      # TODO : ability to pass -x/--x options to action with -- separation ?
      echo -e "The command '${ACTION}' is not registered in Gman and thus may have unforeseeable consequences."
      require_confirmation "Do you want to run '${ACTION} ${FILELIST}' ?" || return 31
      eval ${ACTION} "${ARGOPTION}" ${FILELIST}
      ;;
  esac
}

gman() {

  [[ ! $(command -v git) ]] && {
    echo "\n  Gman requires git to be installed. Exiting."
    return 40
  }
  [[ ! $(git rev-parse --show-toplevel 2>/dev/null) ]] && {
    echo -e "\n  Gman cannot be used outside git repositories. Exiting."
    return 41
  }

  local GITROOT
  GITROOT=$(git rev-parse --show-toplevel)

  cd "${GITROOT}"

  # declaring user config variables
  local REVERSED
  local DEBUG
  local TESTCMD
  local TESTCACHEFOLDER
  local EXTMAIN
  local EXTTEST
  local LINTCMD
  local CLIPBOARDCMD
  local DEFAULTACTION

  # calling the userconfig setting function to initialize the variables declared above
  set_user_config

  # command options. processed after user config for priority.
  while [[ ${1} =~ ^- ]] ; do # TODO : try using getopts ?
    local opt=${1}
    shift
    case ${opt} in
      -r|--reversed) REVERSED=1 ;;
      -d|--debug)    DEBUG=1 ;;
      -c|--clear)    [[ -f ${GITSTATUSFILE} ]] && { rm -f "${GITSTATUSFILE}" "${GITSTATUSPRETTY}" ; return 50 ; } ;;
      -h|--help)     display_help ; return 51 ;;
      --)            break ;;
      *) require_confirmation "Invalid Gman option '${1}'. Ignore & continue ?" && shift || return 52 ;;
    esac
  done

  ((DEBUG)) && { clear ; printf 'gman %s\n' "${@}" ; } # term readability when debugging
  ((DEBUG)) && ((REVERSED)) && echo 'Reversed arguments'


  local WORKDIR=${PWD}
  local -r GITROOTDIR=$(basename ${GITROOT})
  local -r GITSTATUSFILE=/tmp/gman/${GITROOTDIR}/.gman_gitstatus
  local -r GITSTATUSPRETTY=/tmp/gman/${GITROOTDIR}/.gman_gitstatus_pretty
  local GITSTATUS_LENGTH=0

  local FILE=''
  local FILEARRAY=()
  local FILELIST=''
  local NBFILES=0

  local ACTION=''
  local NEXTACTION=''
  local LASTACTION=''

  local -r ARGS=( "${@}" )
  local ARG=''
  local ARGOPTION=''
  local NEXTOPTION=''

  cd "${GITROOT}"


  # called with no args or missing or empty gitstatusfile ?
  if [[ ${#} == 0 || ! -f ${GITSTATUSFILE} ]] \
     || [[ -f ${GITSTATUSFILE} && "$(wc -l < "${GITSTATUSFILE}" | awk '{print $1}')" -eq 0 ]] ; then
    build_gitstatus && show_gitstatus || return ${?}
    cd "${WORKDIR}"
    return 0
  fi


  local i
  for (( i=0 ; i<"${#ARGS[@]}" ; i++ )) ; do
    ARG=${ARGS[i]}
    ((DEBUG)) && horiz


    if grep -q '^[1-9].*[1-9]*$' <<< "${ARG}" ; then # arg is number or range

      build_filelist || return ${?}

      if [[ $((i+1)) -eq ${#} ]] ; then # last arg
        ACTION=${DEFAULTACTION}
        ((REVERSED)) && { ACTION=${NEXTACTION} ; ARGOPTION=${NEXTOPTION} ; }
      fi

    else # arg is action

      ARG=$(echo "${ARG}" | awk '{print tolower($0)}')

      if ((REVERSED)) ; then
        [[ -n "${NEXTACTION}" ]] && { ACTION=${NEXTACTION} ; ARGOPTION=${NEXTOPTION} ; }
        NEXTACTION=${ARG}
      else
        ACTION=${ARG}
      fi

      # EXPERIMENTAL : passing options to actions.
      while [[ "${ARGS[$((i+1))]}" =~ ^- ]] ; do # look ahead for -options
        ((REVERSED)) && NEXTOPTION+=" ${ARGS[$((i+1))]}" || ARGOPTION+=" ${ARGS[$((i+1))]}"
        ((i++))
      done

      ((REVERSED)) && [[ $((i+1)) -eq ${#} ]] && LASTACTION=${ARG}

    fi


    if [[ -n "${ACTION}" ]] ; then

      run_action || return ${?}

      # reset variables for next action
      FILEARRAY=()
      FILELIST=''
      NBFILES=0
      ACTION=''
      ARGOPTION=''
    fi

  done

  [[ -n "${LASTACTION}" ]] && { ACTION=${LASTACTION} ; run_action ; } || return ${?}

  cd "${WORKDIR}"
}

gman "${@}"
