## default

# Administrative identities

These keys are created and managed via the CryptID protocol; refer to it for maintenance details.

default.nix is an attrset that exposes the following filedata string values:

- pgp={certificate,fingerprint}
- age={primary}
- ssh={primary,recovery}

as well as the primary consumer interfaces:

- `age-keys`: all configured primary and recovery Age recipients
- `ssh-keys`: all configured primary and recovery SSH public keys

Consumers should normally use these complete lists. Select an individual
identity only when an operation is explicitly specific to its primary or
recovery role.
