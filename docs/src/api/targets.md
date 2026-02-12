# Target Options

### `native.targets.<name>.compileFlags`

Raw compile flags.

**Type:** `list of string`

**Default:** `[]`


### `native.targets.<name>.compiler`

Compiler selection for this target.

**Type:** `null or string or (attribute set)`

**Default:** _none_


### `native.targets.<name>.defines`

Preprocessor defines.

**Type:** `list of (string or (attribute set))`

**Default:** `[]`


### `native.targets.<name>.includeDirs`

Include directories.

**Type:** `list of (absolute path or string or (attribute set))`

**Default:** `[]`


### `native.targets.<name>.languageFlags`

Per-language compile flags.

**Type:** `attribute set of list of string`

**Default:** `{}`


### `native.targets.<name>.libraries`

Library dependencies.

**Type:** `list of (string or absolute path or (submodule) or (attribute set) or (attribute set))`

**Default:** `[]`


### `native.targets.<name>.linkFlags`

Raw link flags.

**Type:** `list of string`

**Default:** `[]`


### `native.targets.<name>.linker`

Linker selection for this target.

**Type:** `null or string or (attribute set)`

**Default:** _none_


### `native.targets.<name>.name`

Output name for the target.

**Type:** `string`

**Default:** `"<name>"`


### `native.targets.<name>.publicCompileFlags`

Public compile flags (libraries).

**Type:** `list of string`

**Default:** `[]`


### `native.targets.<name>.publicDefines`

Public defines (libraries).

**Type:** `list of (string or (attribute set))`

**Default:** `[]`


### `native.targets.<name>.publicIncludeDirs`

Public include dirs (libraries).

**Type:** `list of (absolute path or string or (attribute set))`

**Default:** `[]`


### `native.targets.<name>.publicLinkFlags`

Public link flags (libraries).

**Type:** `list of (string or absolute path)`

**Default:** `[]`


### `native.targets.<name>.root`

Project root for the target.

**Type:** `null or absolute path or string or (attribute set)`

**Default:** _none_


### `native.targets.<name>.sources`

Source files for the target.

**Type:** `list of (absolute path or string or (attribute set))`

**Default:** `[]`


### `native.targets.<name>.toolchain`

Explicit toolchain for this target.

**Type:** `null or (attribute set)`

**Default:** _none_


### `native.targets.<name>.tools`

Tool plugins (code generators, etc.).

**Type:** `list of (attribute set)`

**Default:** `[]`


### `native.targets.<name>.type`

Target type.

**Type:** `null or one of "executable", "staticLib", "sharedLib", "headerOnly"`

**Default:** _none_



