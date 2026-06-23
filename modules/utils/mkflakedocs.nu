def main [--include-root] {
    # Extract documentation strings from /** ... */ comment blocks
    def extract-docs [file: path] {
        let content = (open $file)
        # (?s) enables dot to match newlines, .*? is non-greedy
        let raw_docs = ($content | parse --regex '(?s)/\*\*(.*?)\*/' | get capture0)

        # Trim each line
        $raw_docs | each {|doc|
            $doc | split row "\n" | each {|line| $line | str trim} | str join "\n" | str trim
        }
    }

    # Find all directories that contain .nix files (recursive search)
    mut dirs = (glob **/*.nix | path dirname | uniq)

    # Omit PWD unless `--include-root` was passed
    if not $include_root {
        $dirs = ($dirs | where {|d| ($d | path expand) != ($env.PWD | path expand) })
    }

    # Process each directory - only document .nix files at that depth
    # Returns list of relative paths to created README files
    $dirs | each {|dir|
        # List only .nix files directly in this directory
        let nix_files = (
            ls $dir
            | where type == "file"
            | where name =~ '\.nix$'
            | get name
        )

        if ($nix_files | is-empty) { return null }

        # Extract docs for each file and add filename header
        let sections = (
            $nix_files
            | each {|f|
                let docs = (extract-docs $f)
                if ($docs | is-empty) {
                    null
                } else {
                    let header = $"## ($f | path parse | get stem)"
                    let content = $docs | str join "\n\n"
                    $"($header)\n\n($content)"
                }
            }
            | compact
        )

        # Join all sections
        let full_doc = $sections | str join "\n\n"

        # Write README.md only if there's content
        if ($full_doc | is-not-empty) {
            let readme_path = [$dir "README.md"] | path join
            $full_doc + "\n" | save -f $readme_path
            # Return relative path
            $readme_path | path relative-to $env.PWD
        } else {
            null
        }
    } | compact
}
