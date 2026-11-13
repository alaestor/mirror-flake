# Host hardening

`server-hardening` supplies shared kernel restrictions, a host firewall,
sudo-rs policy, and AppArmor infrastructure. It does not define a host's network
topology or promise that every service is confined.

## Ownership

Hosts own address-family support, routing, and exceptions to reverse-path
validation. Use `networking.firewall.checkReversePath` for firewall validation;
the kernel's per-interface `rp_filter` is an independent mechanism. Combining
them needs an explicit reason and runtime verification. In particular, a zero
interface value cannot opt out of a global value of one. Network managers can
also change interface values after boot.

Services own their users, filesystem permissions, systemd sandboxes, and any
AppArmor profiles. Enabling AppArmor makes the mechanism available; it does not
load the profiles shipped on its include path or confine unprofiled programs.
Adding a profile requires tests of normal operations and an operation that must
be denied, plus a controlled rollout to already running processes.

CPU-specific mitigations belong with the relevant hardware policy. The generic
baseline retains forced page-table isolation, but does not force Intel KVM
cache-flushing parameters on unrelated processors.

## Service accounts and shared storage

Jellyfin defaults to its dedicated account and hides home directories. Grant
that account read and directory-traversal access to the media it needs at the
storage owner. Do not reuse an administrator's UID or grant broad group access
to make a NAS mount readable. NFS access also depends on server-side identity
mapping and ACLs, so client-side mode bits alone cannot establish access.

Changing an existing service account requires a migration, not just a new unit.
Stop the service and back up its state first. Check the actual state, cache,
configuration, and log paths and their mounts. Transfer only the local service
state to the new account without following media symlinks or traversing NAS
mounts. Upstream Jellyfin tmpfiles rules set ownership on the configured
directories, not all existing contents. Verify media access as the service
account and test playback, scanning, and transcoding before removing a temporary
host-specific account override.

## Service filesystem and device boundaries

Media services treat their libraries as read-only input. Filebrowser writes its
database and cache; Jellyfin writes its configured data, configuration, cache,
and log directories. qBittorrent writes its profile and download directory.
Their systemd units make the remaining filesystem read-only and provide private
temporary storage. They also explicitly protect `/run`: runtime probes on
systemd 262 found that combining `ProtectControlGroups=yes` with
`ProtectSystem=strict` left that mount writable unless it was named in
`ReadOnlyPaths`. Additional writable paths, such as a custom transcode
directory selected in an application's UI, require an explicit unit refinement.
Keep write exceptions narrow; making a parent writable can expose unrelated
state beneath it.

An application's configured default download directory does not describe every
existing torrent's storage. Before restricting qBittorrent, inspect its saved
per-torrent paths as well as its default and temporary directories. Hosts own
any additional write exceptions, bind mounts, and mount dependencies needed to
preserve those locations. When a whole share is intentionally a torrent
workspace, expose that share rather than enumerating changing inbox directories.

Read-only access is not confidentiality. Hosts with several NAS shares should
also hide unrelated shares from each workload. Jellyfin and qBittorrent can
overlay the mount tree with an empty read-only filesystem and bind back only the
required media subtree or torrent workspace. Bind media at its original absolute path so local
alias symlinks still resolve to their NAS targets. New libraries or symlinks
outside the exposed subtree require an explicit host policy change. These
restrictions apply to service processes, not interactive maintenance commands
such as the alias-library builder.

Dufs uses a private filesystem root instead. Only the selected media shares and
the read-only Nix store are bound into it. It has no writable application state
and cannot reach other host directories through its served tree. Its required
runtime authentication file and startup guard prevent an absent or empty secret
from silently enabling anonymous downloads. Test unauthenticated listings,
search, direct files, and archives as well as authenticated reads.

Jellyfin uses a closed device policy. Declare accelerator access through
`services.jellyfin.hardwareAcceleration` or explicit `DeviceAllow` refinements;
changing only the web UI does not grant device access. Retain executable-memory
support for .NET and test FFmpeg subprocesses rather than applying a generic
native-daemon sandbox unchanged.

Validate sandbox changes with both successful state/cache writes and denied
writes outside those directories. Check reads through real media symlinks,
denied access to hidden shares and devices, and application startup. Playback,
scanning, transcoding, authentication, and VPN-failure behavior still need
workload-specific checks before treating the rollout as complete.

## Kernel choices

Keep the kernel's default heap zero-on-allocation. Do not enable page poisoning
as an extra production protection: it takes precedence over automatic heap
initialization rather than supplementing it. Poisoning remains a debugging
choice with different coverage and cost.

Do not use `kernel.ftrace_enabled=0` as a portable tracing restriction. Newer
kernels reject that write, leave tracing enabled, and fail the sysctl service.
An actual tracing prohibition needs a separately tested supported mechanism.

The filesystem/protocol module blacklist suppresses autoload aliases; it is not
a kernel-enforced prohibition on loading those modules. Observation and any
future allowlist must distinguish modules loaded during normal operation from
modules needed for boot, recovery, optional hardware, and exceptional workloads.

## Validation

Run `nix build .#checks.x86_64-linux.server-hardening --no-link` and evaluate the
affected host's toplevel before committing policy changes. Evaluation cannot
prove that a running kernel accepts a sysctl or that a workload can access its
data.

After activating through the normal deployment workflow, require a successful
`systemd-sysctl.service` and inspect its journal. Boot-parameter changes need a
reboot. Check the boot log's `mem auto-init` report, not just kernel configuration
flags. Removing a sysctl declaration does not itself guarantee that its old
runtime value has been reset; verify effective values after reboot and after
network managers configure their interfaces.
