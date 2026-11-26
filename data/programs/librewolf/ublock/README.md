# uBlock Origin policy

The [LibreWolf module](../../../../modules/programs/librewolf.nix) passes
`adminSettings` as a Firefox managed-storage object. uBlock Origin
[accepts an object or a JSON string](https://github.com/gorhill/uBlock/blob/master/src/js/storage.js)
and reapplies the managed settings at startup. Add permanent changes to the
managed lists, custom filters, or dynamic rules in this directory. Dashboard
edits to those settings do not replace the managed copy.

Advanced mode is intentional. Third-party requests are blocked by default.
For a broken site, add a `noop` from the affected site to the specific resource
host, rather than to that host globally. Use a site-wide third-party `noop`
if the site needs too many exceptions. Both forms let static filter lists
continue to apply. The browser's cookie settings are separate.

`trusted.txt` and `hostnameSwitches.txt` are retained exports, not policy.
