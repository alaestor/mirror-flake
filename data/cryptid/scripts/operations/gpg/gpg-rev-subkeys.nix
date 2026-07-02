{ context }:
with context;
{
  name = "gpg-rev-subkeys";
  description = "revoke the newest two subkeys";
  category = "lesser";
  wrapped = true;
  hidden = false;
  content = ''
    ${bash-get-keyid}
    echo "Revoking the newest two GPG subkeys ..."

    expect -d << EXPECT_SCRIPT &> ${path-log-expectScript}

    ${expect-header}
    ${expect-gpgeditkey}

    proc revoke_key { keyindex {spawn ""} } {
      ${expect-default-spawn}
      oi "gpg>" "key \$keyindex" \$spawn
      oi "gpg>" "revkey" \$spawn
      oi "Do you really want to revoke" "y" \$spawn
      safe_expect "0 = No reason specified"  \$spawn
      oi "Your decision?" "0"  \$spawn
      oi "optional description" ""  \$spawn
      oi "Is this okay" "y"  \$spawn
      oi "gpg>" "key \$keyindex" \$spawn
    }

    spawn gpg --expert --pinentry-mode loopback --edit-key ${"$" + env.keyid}

    set index2 [count_subkeys]
    set index1 [expr {\$index2 - 1}]
    revoke_key \$index1
    revoke_key \$index2

    oi "gpg>" "save"
    safe_expect_end
    EXPECT_SCRIPT
    echo "Done."
  '';
}
