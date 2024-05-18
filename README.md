# Micro Omni

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
- (WIP) Resize split with keyboard
<!-- Using https://github.com/zyedidia/micro/issues/1807#issuecomment-1907899274 -->

### Installation
This is still a WIP plugin so don't have any releases yet. To use this, you will need to clone it.
`git clone https://github.com/Neko-Box-Coder/MicroOmni` to your micro `plug` directory


### Requirements
- micro (master or nightly)
- fzf
- grep
- (optional) bat

All of these are available for Unix and Windows
> (WIP) Windows link to requirements

### Keybindings/Commands
- `OmniCenter`: Centers your cursor to the middle of the viewport
- `OmniContent`: Searches all the file contents recursively with whatever is selected or entered
- `OmniSelect`: Selects from current cursor position to either relative line or absolute line
    - This is meant to be used as a command, so bind it like this `"command-edit:OmniSelect "`


### Settings
- `OmniContentArgs`: Argument to be passed to fzf, `-i` is recommended
- `OmniSelectType`: Either `"relative"` or `"absolute"` to for target line number
    - Defaults to `"relative"`

- `fzfCmd`: (Extending from fzfinder) The `fzf` location.
    - Defaults to `"fzf"`
- `fzfOpen`: (Extending from fzfinder) How to open the new file. Available options are:
    - `newtab`: Opens in new tab
    - `vsplit`: Opens in new pane as vertical split
    - `hsplit`: Opens in new pane as horizontal split
    - `thispane`: (Default) Opens in current pane
- `fzfpath`: The root path to search from, can be absolute path or relative to open file by
setting to `relative`.
    -If empty or not specified, defaults to directory where micro was launched
