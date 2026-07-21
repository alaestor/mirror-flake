
uBlock Origin exposed policy-based management in the form of [managed_storage.json](https://github.com/gorhill/uBlock/blob/master/platform/common/managed_storage.json).

When used with Firefox's policy (via mkFirefoxModule.nix) ...
```
"3rdparty".Extensions = {
  "uBlock0@raymondhill.net".adminSettings = {
  ...
```

Per the link above, `adminSettings` requires "a valid JSON string compliant with uBO's backup format" and states that "all entries present will overwrite local settings." Ideal for declarative management.

While it would be easier just to slap the backup file here, I've decided to keep these text files separate for ease of maintainability.

They're gathered by using the backup file in addition to exporting from uBO's various configuration tabs. Some reformatting is required: separate the `hostnameSwitches` from the dynamic filtering rules export, and format `trusted` and `filterLists` to multiline without quotes or punctuation.
