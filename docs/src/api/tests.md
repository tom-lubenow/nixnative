# Test Options

### `native.tests.<name>.args`

Arguments passed to the executable.

**Type:** `list of string`

**Default:** `[]`


### `native.tests.<name>.executable`

Executable target (name or derivation).

**Type:** `null or string or (attribute set)`

**Default:** _none_


### `native.tests.<name>.expectedOutput`

Optional expected output substring.

**Type:** `null or string`

**Default:** _none_


### `native.tests.<name>.name`

Test derivation name.

**Type:** `string`

**Default:** `"<name>"`


### `native.tests.<name>.stdin`

Optional stdin for the test.

**Type:** `null or string`

**Default:** _none_



