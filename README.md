# 🧰 Micro Omni

Just a swiss army knife plugin that adds the functionalities I have from VSCodium.

List of features not in any particular order:
- ⚙️ Fuzzy Search For Files Recursively
    - This extends from fzfinder, but can work independently
- 🔲 Centering Cursor To Viewport
- 🦘 Jump Selection
- 📔 Global Cursor History
- 📁 Copy Current File Path
- 🔦 Highlight Only (Before finding next)
- (WIP) Bracket jumping without on top of it
- (WIP) Contect selection within brackets
- (WIP) Diff view
- (WIP) Resize split with keyboard <!-- Using https://github.com/zyedidia/micro/issues/1807#issuecomment-1907899274 -->
- (WIP) Minimap

## 📦️ Installation
This is still a WIP plugin so don't have any releases yet. To use this, you will need to clone it.

`git clone https://github.com/Neko-Box-Coder/MicroOmni` to your micro `plug` directory


## 📐 Requirements
- micro (from [my branch](https://github.com/Neko-Box-Coder/micro-dev) for now due to a [bug](https://github.com/zyedidia/micro/pull/3318))
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

## 🔍️ Fuzzy Search For Files Recursively

Recommended binding:
```json
{
    "Alt-F": "command:OmniSearch",
    //Windows
    "Alt-Shift-F": "command:OmniSearch"
}
```

To find a with keyword(s), launch command `OmniSearch` which is bindable to a key.
1. First it will ask you which directory to search from, if a relative path is give, 
this will be relative to current working directory (not to be confused with current file directory).
Leaving empty will default to current working directory.
    - `{fileDir}` can be used to substitute the directory path of the current file. 
2. If any text was selected prior to launching the `OmniSearch` command, that text will be used
for **fuzzy** searching. If not, a prompt will ask you what to search.
3. If successful, a fzf window will be launched. Here are the keybindings by default:
    - up/down: Navigate results
    - alt-up / alt-down: Navigate half page of results
    - page-up / page-down: Scroll up and down for the preview window
    - alt-f: Search again with text in the input field (**Non fuzzy** but case insensitive)

### ⚙️ Fuzzy Search Settings
- `fzfCmd`: (Extending from fzfinder) The `fzf` location.
    - Defaults to `"fzf"`
- `fzfOpen`: (Extending from fzfinder) How to open the new file. Available options are:
    - `thispane`: (Default) Opens in current pane
    - `newtab`: Opens in new tab
    - `vsplit`: Opens in new pane as vertical split
    - `hsplit`: Opens in new pane as horizontal split
- `OmniContentArgs`: Argument to be passed to fzf. It defaults to the following:
```lua
OmniContentArgs =   "--bind 'alt-f:reload:rg -i -uu -n {q}' "..
                    "--delimiter : -i "..
                    "--bind page-up:preview-half-page-up,page-down:preview-half-page-down,"..
                    "alt-up:half-page-up,alt-down:half-page-down "..
                    "--preview-window '+{2}-/2' "..
                    "--preview 'bat -f -n --highlight-line {2} {1}'"
```

## 🔲 Centering Cursor To Viewport

Recommended binding:
```json
{
    "Alt-m": "command:OmniCenter"
}
```

It centers your cursor to the middle of your viewport.

## 🦘 Jump Selection

Recommended binding:
```json
{
    "Alt-J": "command-edit:OmniJumpSelect ",
    //Windows
    "Alt-Shift-J": "command-edit:OmniJumpSelect "
}
```

To select a section based on line number, launch the `OmniJumpSelect` command with 
the line number specified. 

By default it uses relative line numbers, so 5 is 5 lines down and -5 is 5 lines up.
This can be configured to use absolute line number. See settings.

### ⚙️ Jump Selection Type Settings
- `OmniSelectType`: Sets the jump selection type. Can either be `relative` (default) or `absolute`


## 📔 Global Cursor History

Recommended binding:
```json
{
    "Alt-{": "command:OmniPreviousHistory",
    "Alt-}": "command:OmniNextHistory"
}
```

When you are editing multiple files or jumping between different functions, 
a history of the cursor location is stored. You can go to previous or next cursor position
by launching the `OmniPreviousHistory` and `OmniNextHistory` commands.

This is similar to the navigate back and forward commands in VSCode

### ⚙️ Global Cursor History Settings
- `OmniHistoryLineDiff`: Sets how many line difference count as new cursor history. Defaults to 5

<!-- - `fzfpath`: The root path to search from, can be absolute path or relative to open file by setting to `relative`. -->
<!--     -If empty or not specified, defaults to directory where micro was launched -->

## 📁 Copy Current File Path

Recommended binding:

None (Invoke it in command pane)

You can copy the current file absolute or relative path with `OmniCopyRelativePath` and 
`OmniCopyAbsolutePath` command.


## 🔦 Highlight Only (Before finding next)

- `OmniHighlightOnly`: TODO

