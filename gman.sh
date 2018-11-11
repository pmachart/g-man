#!/bin/bash

set_user_config() {

  ############## USER CONFIG ##############

  REVERSED=0 # optionally reversing arguments
  TESTCMD='./node_modules/.bin/jest'
  #if [[ -f package.json ]] ; then TESTCMD=$(node -pe "require('./package.json').scripts.test") ; fi
  TESTCACHEFOLDER='/tmp/jest_rs' # /!\ gets rm-rf'ed when test actions are called with nocache arg
  EXTMAIN='js' # file extension of the tested language
  EXTTEST='test' # file extension of the test files
  LINTCMD='./node_modules/.bin/tslint'
  CLIPBOARDCMD='xclip'

  ############ END USER CONFIG ############
}

DEBUG_LOGGER() {
  ((DEBUG)) && (
    local OPT
    [[ ${1} == "-n" ]] && shift && OPT='-n'
    [[ ${1} == "HR" ]] && shift && type -t horiz && horiz # using type to check if alias exists
    # horiz = horizontal ruler alias. check my dotfiles for it, or replace with echo ------------
    echo ${OPT} "${FUNCNAME[1]^^} ${1}"
  )
}

require_git_repo() { DEBUG_LOGGER HR
  local ISGIT=false
  local DIR=${PWD}
  until [[ ${DIR} == / ]]; do
    [[ -d "${DIR}/.git" ]] && ISGIT=true
    DIR=$(dirname "${DIR}")
  done
  if [[ ${ISGIT} == false ]] ; then
    echo -e '\n   Not in a git repository.'; return 1
  fi
}

build_gitstatus() { DEBUG_LOGGER HR
  rm -f "${GITSTATUSFILE}"
  git status -u --porcelain | cut -c 4- > "${GITSTATUSFILE}"
  ((DEBUG)) && cat "${GITSTATUSFILE}"
  rm -f "${GITSTATUSPRETTY}"
  git -c color.status=always status -su | nl -ba -s' ' > "${GITSTATUSPRETTY}"
  GITSTATUS_LENGTH="$(wc -l < "${GITSTATUSFILE}")"
}

show_gitstatus() { DEBUG_LOGGER HR
  if [[ ${GITSTATUS_LENGTH} -gt 0 ]] ; then
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

  DEBUG_LOGGER "${FILE}"
  FILELIST="${FILELIST# }" # strip first space
}

build_filelist() { DEBUG_LOGGER HR "${ARG}"
  local FIRST=0
  local LAST=0

  if [[ ${ARG} =~ ^[0-9]+-[0-9]+$ ]] ; then # parameter is range of numbers
    FIRST=$(echo "${ARG}" | cut -f1 -d-)
    LAST=$(echo "${ARG}" | cut -f2 -d-)

    if [[ ${FIRST} -gt ${LAST} ]] ; then # swap range
      local TEMP=${LAST}
      LAST=${FIRST}
      FIRST=${TEMP}
    fi
    for i in $(seq "${FIRST}" "${LAST}"); do
      add_to_filelist "${i}"
    done
  else # single parameter
    if grep -q '^[0-9]*$' <<< "${ARG}" ; then # numeric check
      add_to_filelist "${ARG}"
    else
      echo "Error : invalid parameter ${ARG}"; return 1
    fi
  fi
  ((DEBUG)) && echo -e "\nEnd build_filelist : [${FILELIST}]"  || return 0
}

send_to_clipboard() {
  # TODO this does not work for filenames with spaces : does not send quotes to xclip
  # TODO try with xargs ?
  eval echo -n ${FILELIST} | ${CLIPBOARDCMD}
}

display_files() { DEBUG_LOGGER "${ACTION}"
  local OUTPUT=''

  for FILE in "${FILEARRAY[@]}" ; do
    OUTPUT+="  ${FILE}\n"   # newline separated list for OUTPUT
  done

  if [[ ${ACTION} != 'view' ]] ; then
    # called with PRINT action ? simple output for piping and xargsing
    echo -e " ${FILELIST}"
    return 1
  fi

  echo -e "\nSelected files :\n${OUTPUT}"
  send_to_clipboard
}


require_files_exist() { DEBUG_LOGGER
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
  ((NOFILES)) && echo "${BOLD}${RED}Error: None of the selected files exist. Aborting.${RESET}" && return 1 || return 0
}

get_folder_name() { DEBUG_LOGGER -n HR "${FILE}"
  # TODO : handle symlinks
  declare -n RETURN=$1
  RETURN="${2}"
  if [ -f "${2}" ] ; then
    RETURN=$(dirname "${2}")
    ((DEBUG)) && echo ": ${RETURN}"
  fi
}

require_confirmation() { DEBUG_LOGGER
  local YN
  while true; do
    read -p "${1} (y/n) > " YN
    case ${YN} in
      [Yy]* ) return 0 ;;
      [Nn]* ) echo "${2}"; return 1 ;;
      * ) echo "Please answer with yes or no". ;;
    esac
  done
}

run_action() { DEBUG_LOGGER HR "${ARG}"

  local OPTIONS=''

  if [[ ${NBFILES} -eq 0 ]]; then
    # no file in the list ? get all the files !
    ((DEBUG)) && echo 'No file in list. Building gitstatus.'
    build_gitstatus
    ARG="1-${GITSTATUS_LENGTH}"
    build_filelist || return 1 # passing down returns because we run in source mode
  fi

  ((DEBUG)) && echo -e "${BOLD}--> ${RED}Running action : ${ACTION}${RESET}"
  case ${ACTION} in

    'show' | 's')
      show_gitstatus
      ;;
    'add' | 'a')   eval git add -- ${FILELIST} ;;
    'oops')
      eval git add -- ${FILELIST}
      git commit --amend --no-edit --no-verify
      ;;
    d*s*) OPTIONS+=" --unified=0 --ignore-space-at-eol --color-words='[[:alnum:]]+|[^[:space:]]'" ;;&
    d*c*) OPTIONS+=" --cached" ;;&
    d*h*) OPTIONS+=" HEAD" ;;&
    d*)
      eval git diff ${OPTIONS} -- ${FILELIST}
      ;;
    'checkout' | 'co' | 'u')
      for FILE in "${FILEARRAY[@]}" ; do
        if git diff --name-only --cached | grep "^${FILE#$GITROOT}$" >/dev/null ; then # file is staged ?
          eval git reset HEAD -- ${FILE} # avoids unnecessary output on git checkout
        fi
        eval git checkout -- ${FILE}
      done
      ;;
    'stash')       eval git stash push -- ${FILELIST} ;; # TODO read about git stash pushing
    'hist'  | 'h') eval git log -u -- ${FILELIST} ;;
    'reset' | 'r') eval git reset -- ${FILELIST} ;;



    'bak')
      for FILE in "${FILEARRAY[@]}" ; do
        require_files_exist && eval cp ${FILE} ${FILE}.bak
      done
      ;;

    'touch')       eval touch ${FILELIST} ;; # sometimes used as a git quickfix
    'vim'  | 'v')  eval vim  ${FILELIST} ;;
    'nano' | 'n')  eval nano ${FILELIST} ;;
    'code' | 'vs') eval code ${FILELIST} ;;
    'atom' | 'o')  eval atom ${FILELIST} ;;
    'cat'  | 'c')  require_files_exist && eval cat ${FILELIST} ;;
    'bat'  | 'b')  require_files_exist && eval bat ${FILELIST} ;;
    'most' | 'm')  eval most  ${FILELIST} ;;
    'print' | 'p' | 'view') display_files ;;
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
      ls -BhF${OPTIONS} --group-directories-first "${FILE_DIR}"
      ;;

    rm*f*) OPTIONS+=' -f' ;;&
    rm*)
      require_files_exist || return 1
      eval git rm ${OPTIONS} -- ${FILELIST} 2>/dev/null || rm ${OPTIONS} ${FILELIST}
      ;;

    'lintfix' | 'lf') OPTIONS+=' --fix --stdin --stdin-filename' ;;&
    'lint' | 'l')
      eval ${LINTCMD} ${OPTIONS} ${FILELIST}
      ;;

    t*)   if [[ -z ${TESTCMD} ]] ; then echo 'No test command configured' ; return 1 ; fi ;;
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
        type -t horiz && horiz # TODO colored line with variable variable
        echo "  ${CYAN}${BOLD}Testing ${RED}${BASENOEXT}.${EXTMAIN}${CYAN} with params:${RED}${TESTPARAMS}${RESET}"
        type -t horiz && horiz
        eval ${TESTCMD} ${TESTPARAMS} ${RELDIR}/${BASENOEXT}.${EXTTEST}.${EXTMAIN}
        if [[ ${ARG} =~ o && ${ARG} =~ c ]] ; then
          xdg-open ./coverage/lcov-report/${BASENOEXT}.${EXTMAIN}.html > /dev/null 2>/dev/null # TODO redirect too long
        fi
      done
      ;;

    *)
      echo "Warning : unrecognized action : ${ACTION}"
      # TODO : get rest of arguments. use shift to get rid of args progressively
      echo -e "The command '${ACTION}' is not registered in Gman and thus may have unforeseeable consequences."
      require_confirmation "Do you want to run '${ACTION} ${FILELIST}' ?" "Aborting." || return 1
      eval ${ACTION} ${FILELIST}
      ;;
  esac
}

gman() {

  # user config variables are declared below so they can be set in a function at the top of the script
  local REVERSED
  local TESTCMD
  local TESTCACHEFOLDER
  local EXTMAIN
  local EXTTEST
  local LINTCMD
  local CLIPBOARDCMD

  set_user_config # calling the user config setting function

  require_git_repo || return 1

  local WORKDIR=${PWD}
  local GITROOT
    GITROOT=$(git rev-parse --show-toplevel)
  local GITSTATUSFILE=${GITROOT}/.git/.gman_gitstatus
  local GITSTATUSPRETTY=${GITROOT}/.git/.gman_gitstatus_pretty
  local GITSTATUS_LENGTH=0

  local FILE=''
  local FILEARRAY=()
  local FILELIST=''
  local NBFILES=0
  local ACTION=''
  local NEXTACTION='view' # default action if none is supplied

  if [[ ${1} == '-r' ]] ; then shift ; REVERSED=1 ; fi
  ((DEBUG)) && ((REVERSED)) && echo 'Reversed arguments'

  local ARGS=( "${@}" )
  local ARG=''
  local NBARG=0

  cd "${GITROOT}"


  if [[ ${#} == 0 || ! -f ${GITSTATUSFILE} ]] || [[ -f ${GITSTATUSFILE} && "$(wc -l < "${GITSTATUSFILE}")" -eq 0 ]] ; then
    # no args and no gitstatusfile, or an empty gitstatusfile
    build_gitstatus
    show_gitstatus
    return 0
  fi


  for ARG in "${ARGS[@]}" ; do # loop through all args, both file numbers and actions
  ((NBARG++))

    if ! grep -q '^[a-zA-Z]*$' <<< "${ARG}" ; then # arg is file number

      build_filelist || return 1

    else # is action

      ARG=${ARG,,} # tolowercase in bash 4
      if [[ ! ${NBARG} == 1 ]] ; then
        ACTION=${NEXTACTION}
      fi
      NEXTACTION=${ARG}

      # if running with reversed args, the action to be run with the files is ARG
      ((REVERSED)) && ACTION=${ARG} && NEXTACTION='view'

    fi

    if [[ ${NBARG} -eq ${#} ]] ; then
      ACTION=${NEXTACTION}
    fi

    if [[ ${ACTION} ]] ; then
      run_action "${ACTION}" || return 1

      # reset file list for next action
      FILEARRAY=()
      FILELIST=''
      NBFILES=0
      ACTION=''
    fi

  done

  cd "${WORKDIR}"
}

((DEBUG)) && clear
gman "${@}"
