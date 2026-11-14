use std/assert

def main [script: path] {
    let script = ($script | path expand)
    let fixture = (mktemp --directory)
    let repo = ($fixture | path join "repo")
    mkdir $repo
    $env.GIT_CONFIG_NOSYSTEM = "1"
    $env.GIT_CONFIG_GLOBAL = ($fixture | path join "gitconfig")
    let excludes = ($fixture | path join "global-ignore")
    "*.global.nix\n" | save $excludes
    ^git config --global core.excludesFile $excludes
    ^git -C $repo init --quiet
    cd $repo

    mkdir modules/nested .scratch
    ".scratch/\n*.ignored.nix\n" | save .gitignore
    "*.local.nix\n" | save --force .git/info/exclude
    "/** Root docs */\n{}\n" | save root.nix
    "/** Tracked docs */\n{}\n" | save modules/tracked.nix
    "/** Tracked despite ignore */\n{}\n" | save modules/kept.ignored.nix
    "/** Deleted docs */\n{}\n" | save modules/deleted.nix
    ^git add root.nix modules/tracked.nix modules/deleted.nix
    ^git add --force modules/kept.ignored.nix
    rm modules/deleted.nix

    # Ignored invalid UTF-8 must never reach the docstring parser, even
    # when it shares a directory with files that are being documented.
    for file in [
        ".scratch/binary.nix"
        "modules/binary.ignored.nix"
        "modules/binary.local.nix"
        "modules/binary.global.nix"
    ] {
        0x[ff] | save $file
    }
    "/** Untracked docs */\n{}\n" | save 'modules/nested/untracked "name".nix'
    "{}\n" | save modules/nested/undocumented.nix

    let result = (^nu --no-config-file $script | complete)
    assert equal $result.exit_code 0 $result.stderr
    assert equal (open --raw modules/README.md | str trim) "## kept.ignored\n\nTracked despite ignore\n\n## tracked\n\nTracked docs"
    assert equal (open --raw modules/nested/README.md | str trim) '## untracked "name"

Untracked docs'
    assert not ("README.md" | path exists)
    assert not (".scratch/README.md" | path exists)

    let root = (^nu --no-config-file $script --include-root | complete)
    assert equal $root.exit_code 0 $root.stderr
    assert equal (open --raw README.md | str trim) "## root\n\nRoot docs"

    # Discovery is scoped to the working directory, not the whole repo.
    cd modules
    "sentinel" | save --force README.md
    let nested = (^nu --no-config-file $script | complete)
    assert equal $nested.exit_code 0 $nested.stderr
    assert equal (open --raw README.md | str trim) "sentinel"
    assert ($nested.stdout | str contains "nested/README.md")

    let empty = ($fixture | path join "empty")
    mkdir $empty
    ^git -C $empty init --quiet
    cd $empty
    let no_files = (^nu --no-config-file $script | complete)
    assert equal $no_files.exit_code 0 $no_files.stderr
    assert not ("README.md" | path exists)

    cd $fixture
    let outside = (^nu --no-config-file $script | complete)
    assert ($outside.exit_code != 0)
    assert ($outside.stderr | str contains "Cannot discover Nix files")
}
