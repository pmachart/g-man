#! /bin/bash
# @TODO : mute les output intermediaires de git reset en groupe

function gman() {

  local dir=$PWD
  local isgit=false
  until [[ $dir == / ]]; do 
    [[ -d "$dir/.git" ]] && isgit=true
    dir=$(dirname "$dir")
  done
  if [[ $isgit == false ]] ; then
    echo -e '\n   Not in a git repository.' ; return
  fi

  local GITROOT=$(git rev-parse --show-toplevel)
  local WORKDIR=$PWD
  local RELDIR=${WORKDIR#$GITROOT}

  if [[ $# == 0 ]] ; then # no param : build list

    unset gitstatus # global var
    gitstatus=$(git status --porcelain | cut -c 4-) #porcelain always does absolute paths

    if [ ! -z "$gitstatus" ] ; then
      echo ''
      cd $GITROOT # status -s always does relative paths, this is a small hack to avoid displaying a bunch of ../
      git -c color.status=always status -s | nl -ba -s' '
      cd $OLDPWD
      echo ''
    else
      echo -e '\n   "Looks clear."\n'
    fi

    return # end build list : exit script
  fi



  local files=()
  local file=''
  local args=( "$@" )
  local hasaction=false
  local first=''
  local last=''

  for arg in ${args[@]} ; do # loop through all args, both files and actions

    if grep -v -q '^[a-zA-Z]*$' <<< "${arg}" ; then # not an action

      if [[ $arg =~ ^[0-9]+-[0-9]+$ ]] ; then # parameter is range of numbers
        first=$(echo $arg | cut -f1 -d-)
        last=$(echo $arg | cut -f2 -d-)

        if [[ -z $first || -z $last ]] ; then
          echo 'error : invalid range '$arg; return # user error : exit
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
          echo 'error : invalid parameter '$arg; return # user error : exit
        fi

      fi # end single parameter

      for (( i=$first; i<${last}+1; i++ )) ; do # file lists are built
        file=$(sed -n ${i}p <<< "$gitstatus")
        files=($(echo ${files[@]}) "$file") # array.push in bash :)
      done

    else # actions go here
      hasaction=true

      for file in ${files[@]} ; do
        case $arg in

          # basic actions
          'cd')
            cd $GITROOT/$(dirname "${file}")
            echo '' ; ls ; echo ''
            ;;
          'vim' | 'v')
            vim $GITROOT/$file
            ;;
          'nano' | 'n')
            nano $GITROOT/$file
            ;;
          'atom' | 'o')
            atom $GITROOT/$file
            ;;

          # adding resetting and undoing
          'add' | 'a')
            git add $GITROOT/$file
            ;;
          'oops') # add to the latest unpushed commit
            git add $GITROOT/$file
            git commit --amend --no-edit --no-verify
            ;;
          'reset' | 'r')
            git reset $GITROOT/$file
            ;;
          'rm')
            git rm $GITROOT/$file
            ;;
          'checkout' | 'co' | 'u')
            if [[ $(git diff-index --cached HEAD --) == *"$file" ]]; then # file is staged ?
              git reset HEAD $GITROOT/$file # avoids unnecessary output on git checkout
            fi
            git checkout $GITROOT/$file
            ;;

          # diffs
          'diff' | 'df')
            git diff $GITROOT/$file # full diff
            ;;& # fallthrough
          'd') # short diff
            git diff --unified=0 --ignore-space-at-eol --color-words='[[:alnum:]]+|[^[:space:]]' $GITROOT/$file
            ;;&
          'diff' | 'df' | 'dc' | 'd')
            git diff --cached $GITROOT/$file # cached diff
            ;;

          *)
            echo unrecognized action : \"$arg\" on file \"$file\"
            ;;

        esac
      done

      files=() # reset file lists for optional next action

    fi # end actions

  done # end loop through args

  if [[ $hasaction == false ]] ; then # no action arg > output abs paths
    local output=""
    local clipboard=""

    for file in ${files[@]} ; do
      output+="$GITROOT/$file\n" # newline separated list for output
      clipboard+="$GITROOT/$file " # space separated list for clipboard
    done

    echo -e "\n"$output

    if [[ ! -z $(which xclip) ]] ; then
      echo -n " $clipboard" | xclip
    else
      echo 'apt install xclip to send this output to clipboard next time'
    fi
  fi
}

gman $@ # call function wrapper with all arguments. allows for local variables.
