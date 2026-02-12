# Shell Options

### `native.shells.<name>.extraPackages`

Extra packages to include.

**Type:** `list of anything`

**Default:** `[]`


### `native.shells.<name>.includeTools`

Include common dev tools (clang-tools, gdb).

**Type:** `boolean`

**Default:** `true`


### `native.shells.<name>.linkCompileCommands`

Symlink compile_commands.json if available.

**Type:** `boolean`

**Default:** `true`


### `native.shells.<name>.name`

Dev shell name.

**Type:** `string`

**Default:** `"<name>"`


### `native.shells.<name>.symlinkName`

Symlink name for compile commands.

**Type:** `string`

**Default:** `"compile_commands.json"`


### `native.shells.<name>.target`

Target to derive toolchain from.

**Type:** `null or string or (attribute set)`

**Default:** _none_


### `native.shells.<name>.toolchain`

Explicit toolchain for the dev shell.

**Type:** `null or (attribute set)`

**Default:** _none_



