# 🧰 Micro Omni

Just a swiss army knife plugin that adds the functionalities I have from VSCodium.

List of features not in any particular order:
- fuzzy search for files recursively
    - This extends from fzfinder, but can work independently
- Centering cursor to viewport
- Jump Selection
- (WIP) Global Cursor History
- (WIP) Bracket jumping without on top of it
- (WIP) Contect selection within brackets
- (WIP) Diff view
- (WIP) Copy current file path
- (WIP) Resize split with keyboard <!-- Using https://github.com/zyedidia/micro/issues/1807#issuecomment-1907899274 -->
- (WIP) Minimap

## 📦️ Installation
This is still a WIP plugin so don't have any releases yet. To use this, you will need to clone it.

`git clone https://github.com/Neko-Box-Coder/MicroOmni` to your micro `plug` directory


## 📐 Requirements
- micro (from [my branch](https://github.com/Neko-Box-Coder/micro-dev) for now due to bug)
- fzf
- ripgrep
- bat

All of these are available for Unix and Windows
> Windows link to requirements
>
> [https://github.com/junegunn/fzf/releases](https://github.com/junegunn/fzf/releases)
>
> [https://github.com/BurntSushi/ripgrep/releases](https://github.com/BurntSushi/ripgrep/releases)
>
> [https://github.com/sharkdp/bat/releases](https://github.com/sharkdp/bat/releases)

## 🔍️ Finding files recursively with fzf

To find a with keyword(s), launch command `OmniFind` which is bindable to a key.
1. First it will ask you which directory to search from, if a relative path is give, 
this will be relative to current working directory (not to be confused with current file directory).
Leaving empty will default to current working directory.
    - `{fileDir}` can be used to substitute the directory path of the current file. 
2. If any text was selected prior to launching the `OmniFind` command, that text will be used
for searching. If not, a prompt will ask you what to search.
3. If successful, a fzf window will be launched. Here are the keybindings by default:
    - up/down: Navigate results
    - alt-up / alt-down: Navigate half page of results
    - page-up / page-down: Scroll up and down for the preview window


> [!CAUTION] 
> The rest of this README is still work in progress and incomplete



### Keybindings/Commands
- `OmniCenter`: Centers your cursor to the middle of the viewport
- `OmniContent`: Searches all the file contents recursively with whatever is selected or entered
- `OmniSelect`: Selects from current cursor position to either relative line or absolute line
    - This is meant to be used as a command, so bind it like this `"command-edit:OmniSelect "`





### Settings
- `OmniContentArgs`: Argument to be passed to fzf. Recommend the set to either the following:
    - `"--delimiter : -i --preview-window +{2}-/2 --preview \"bat -f -n --highlight-line {2} {1}\"`
    - `"-i"`
- `OmniSelectType`: Either `"relative"` or `"absolute"` to for target line number
    - Defaults to `"relative"`

- `fzfCmd`: (Extending from fzfinder) The `fzf` location.
    - Defaults to `"fzf"`
- `fzfOpen`: (Extending from fzfinder) How to open the new file. Available options are:
    - `thispane`: (Default) Opens in current pane
    - `newtab`: Opens in new tab
    - `vsplit`: Opens in new pane as vertical split
    - `hsplit`: Opens in new pane as horizontal split

<!-- - `fzfpath`: The root path to search from, can be absolute path or relative to open file by setting to `relative`. -->
<!--     -If empty or not specified, defaults to directory where micro was launched -->
