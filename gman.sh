#!/bin/bash

function gman() {

  local DIR=$PWD
  local ISGIT=false
  until [[ $DIR == / ]]; do
    [[ -d "$DIR/.git" ]] && ISGIT=true
    DIR=$(dirname "$DIR")
  done
  if [[ $ISGIT == false ]] ; then
    echo -e '\n   Not in a git repository.'; return 1
  fi

  local GITROOT=$(git rev-parse --show-toplevel)
  local WORKDIR=$PWD
  local RELDIR=${WORKDIR#$GITROOT}

  if [[ $# == 0 ]] ; then # no param : build list

    unset gitstatus # global var
    gitstatus=$(git status --porcelain -u | cut -c 4-) # porcelain always does absolute paths

    if [ ! -z "$gitstatus" ] ; then
      echo
      cd $GITROOT # status -s always does relative paths, this is a small hack to avoid displaying a bunch of ../
      git -c color.status=always status -s -u | nl -ba -s' '
      cd $OLDPWD
      echo
    else
      echo -e '\n   "Looks clear."\n'
    fi

    return 0 # end build list : exit script
  fi

  local files=()
  local file=''
  local args=( "$@" )
  local hasaction=false
  local first=''
  local last=''
  local narg=0

  for arg in ${args[@]} ; do # loop through all args, both files and actions
  ((narg++))

    if grep -v -q '^[a-zA-Z]*$' <<< "${arg}" ; then # not an action

      if [[ $arg =~ ^[0-9]+-[0-9]+$ ]] ; then # parameter is range of numbers
        first=$(echo $arg | cut -f1 -d-)
        last=$(echo $arg | cut -f2 -d-)

        if [[ -z $first || -z $last ]] ; then
          echo 'error : invalid range '$arg; return 1 # user error : exit
        fi

        if [[ $first > $last ]] ; then # swap range
          local temp=$last
          last=$first
          first=$temp
        fi

      else # single parameter

        if grep -q '^[0-9]*$' <<< "${arg}" ; then # numeric check
          first=$arg # @TODO single file hack
          last=$arg
        else
          echo 'error : invalid parameter '$arg; return 1 # user error : exit
        fi

      fi # end single parameter

      for (( i=$first; i<${last}+1; i++ )) ; do # file lists are built
        file=$(sed -n ${i}p <<< "$gitstatus")
        files=($(echo ${files[@]}) "$GITROOT/$file") # array.push in bash
      done

    else # actions go here
      hasaction=true

     # actions with file params
      for file in ${files[@]} ; do
        case $arg in

          # basic actions
          'cd')
            if [ -d "$file" ] ; then
              cd $file
            else
              cd $(dirname "${file}")
            fi
            echo; ls; echo; break
            ;;
          'bak' | 'cp')
            cp $file $file.bak
            ;;
          'vim' | 'vi')
            vim $file
            ;;
          'vscode' | 'vs')
            code $file
            ;;
          'nano' | 'n')
            nano ${files[@]} ; break
            ;;
          'atom' | 'o')
            atom ${files[@]} ; break
            ;;

          # adding, resetting and undoing
          'add' | 'a')
            git add ${files[@]} ; break
            ;;
          'oops') # add to the latest unpushed commit
            git add ${files[@]}
            git commit --amend --no-edit --no-verify
            break
            ;;
          'reset' | 'r')
            git reset ${files[@]} ; break
            ;;
          'rm')
            git rm $file || rm $file
            ;;
          'stash')
            git stash push ${files[@]}
            ;;
          'checkout' | 'co' | 'u')
            if [[ $(git diff-index --cached HEAD --) == *"${file#$GITROOT}" ]]; then # file is staged ?
              git reset HEAD ${files[@]} # avoids unnecessary output on git checkout
            fi
            git checkout ${files[@]}
            break
            ;;

          # diffs
          d*)
            hr
            echo "  "${CYAN}${BOLD}${file#$GITROOT}${RESET}
            hr
            ;;& # fallthrough
          'diff' | 'df' | 'd')
            git diff $file # full diff
            ;;
          'dc')
            git diff --cached $file
            ;;
          'ds') # short diff
            git diff --unified=0 --ignore-space-at-eol --color-words='[[:alnum:]]+|[^[:space:]]' $file
            ;;
          'dcs' | 'dsc' ) # short diff cached
            git diff --unified=0 --ignore-space-at-eol --color-words='[[:alnum:]]+|[^[:space:]]' --cached $file
            ;;
          'icdiff' | 'dd') # icdiff is a nice side-by-side cli diff tool. look it up.
            git-icdiff $file
            ;;
          'hist' | 'h')
            hr
            echo "  "${CYAN}${BOLD}${file#$GITROOT}${RESET}
            hr
            git log -u $file
            ;;

          # linting
          'lint' | 'l')
            node node_modules/eslint/bin/eslint $file
            ;;
          'lintfix' | 'lf')
            node_modules/.bin/eslint --fix --stdin --stdin-filename $file
            ;;

          # tests
          t*) # wildcard : arg begins with t
            rm -rf /tmp/jest_rs
            cd $GITROOT # jest sometimes behaves erratically when not running from project root
            local TESTCMD=$(node -pe "require('./package.json').scripts.test")
            local TESTPARAMS=''

            local BASEDIR=$(dirname $file)
            local RELDIR=${BASEDIR#$GITROOT}
            local BASENAME=$(basename $file)
            local BASENOEXT=${BASENAME%.js}
            local BASENOEXT=${BASENOEXT%.test}

            if [[ $arg =~ c ]]; then TESTPARAMS="$TESTPARAMS --coverage"; fi
            if [[ $arg =~ u ]]; then TESTPARAMS="$TESTPARAMS --updateSnapshot"; fi
            if [[ $arg =~ w ]]; then TESTPARAMS="$TESTPARAMS --watch"; fi
            if [[ $arg =~ n ]]; then TESTPARAMS="$TESTPARAMS --no-cache"; fi

            hr
            echo "  "${CYAN}${BOLD}Testing ${RED}$BASENOEXT.js${CYAN} with params:${RED}$TESTPARAMS${RESET}
            hr
            $TESTCMD $TESTPARAMS $RELDIR/$BASENOEXT.test.js

            if [[ $arg =~ o && $arg =~ c ]]; then xdg-open ./coverage/lcov-report/$BASENOEXT.js.html > /dev/null 2>/dev/null; fi

            cd $OLDPWD
            ;;

          *)
            echo unrecognized action : \"$arg\" on file \"${file#$GITROOT}\"
            ;;

        esac #end action arg case
      done # end loop through files

      files=() # reset file lists for optional next action

    fi # end actions

  done # end loop through args

  if [[ $hasaction == false ]] ; then # no action arg > output abs paths
    local output=""
    local clipboard=""

    for file in ${files[@]} ; do
      output+="$file\n" # newline separated list for output
      clipboard+="$file " # space separated list for clipboard
    done

    echo -e "\n"$output

    if [[ ! -z $(which xclip) ]] ; then
      echo -n " $clipboard" | xclip
    else
      echo 'apt install xclip to send this output to clipboard next time'
    fi
  fi
}

hr() {
  local start=$'\e(0' end=$'\e(B' line='qqqqqqqqqqqqqqqq'
  local cols=${COLUMNS:-$(tput cols)}
  while ((${#line} < cols)); do line+="$line"; done
  printf '%s%s%s\n' "$start" "${line:0:cols}" "$end"
}

gman $@ # call function wrapper with all arguments. allows for local variables.
