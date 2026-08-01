---
name: git-howto-change-commit-message-history
description: How agents can retroactively change a commit message
disable-model-invocation: false
---

Since I cannot use an interactive editor, I automated the rebase using environment variables:

1. **`GIT_SEQUENCE_EDITOR`**: Used `sed` to programmatically change `pick` to `reword` for the specific commit hash in the rebase todo list.
2. **`GIT_EDITOR`**: Used `sed` to programmatically replace the text in the commit message file when the rebase paused for rewording.

**Command used:**
```
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <hash>/reword <hash>/'" GIT_EDITOR="sed -i 's/old-text/new-text/'" git rebase -i <hash>^
```
