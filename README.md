# G-Man
<img src="images/suitcase.jpg" height="130" align="right">
A simple bash script to accelerate your daily git usage.

----
## Description
The script is built on top of `git status -s` to generate a numbered file list.

That list can then be used to run various actions on files or group of files by typing only these numbers and shorthand commands such as `g 2 a` to to a `git add` on the second file in the list. No more path copy-pasting.

----
## Installation
Using "g" as a shorthand for `git` is the obvious thing to do.
Just copy the file and use a bash alias to run it, like so :
```shell
alias g='~/gman.sh'
```

----
## Usage

| CLI | Details |
| --- | --- |
| <img src="images/usage01.png"> | Basic usage : specify a file's number, followed by the desired action. |
| <img src="images/usage02.png" width="232"> | Number range : in case you are too lazy. One could also have typed `g 3 4 5 6 a` for the same outcome. |
| <img src="images/usage03.png"> | You can chain instructions, following the "file numbers - action" pattern.<br><br>In this example, files 1 2 and 3 are staged, file 6 is checked out, and we `cd` to the folder containing file 5. |


(Prompt on these screenshots is with <a href="https://github.com/magicmonty/bash-git-prompt" target="_blank">MagicMonty's bash-git-prompt</a>)

----
## Available commands
This is just a short list of the available actions. For more details, and to customize them or add your own, take a look at the script. Contributions are very welcome.

#### Git related
| Command and shorthand | Description |
| --- | --- |
| add, a | `git add` |
| oops | adds file to the last non-pushed commit |
| reset | `git reset` |
| rm | `git rm` |
| checkout, co, u | reverts changes to staged or unstaged file |

#### Filesystem related
| Command and shorthand | Description |
| --- | --- |
| cd | `cd` to the folder containing the file |
| vim, v | open the file with vim |
| nano, n | open the file with nano |
| atom, o | open the file with atom |

----
## Contribution

I have built this for my personal use. I am a front-end web developer and bash scripting is not my usual language.

Many former colleagues have seen me use this small tool and asked me to share it with them, and i did. With this repository, I am taking things a step further.

I have improved it and refactored it a few times and am always looking for advice and constructive criticism, so please feel free to contribute or comment about anything.
