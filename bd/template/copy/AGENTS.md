Before running code:
- Check for any pre-existing environments (e.g. conda) to activate. Always ask before creating new environments.

Review guide:

First steps:

Determine what the developer wants to achieve and why they want that
Determine if the approach is the right one
Be more critical the larger the diff scope and lines of code changed is. Be very critical of «why» this PR and every line of code change deserves to exist. Removing no longer needed functionality is encouraged

Prefer current codebase conventions, styles and variable naming
Prefer PRs focused on one thing to make reviewing easier. Prefer new PRs for new scope
Actively hunt for code to delete, including legacy
Fail early, loudly, and with clear error messages
Fix issues at the right layer - should this live further up/down the chain, or in the backend?

Patterns to remove:
Ask why any try-except, silent defaults or other defensive programming patterns need to be there
Backwards compatibility should not be considered unless explicitly asked

Questions to ask:

Does the codebase already do this?
Does this diverge from how siblings are handled?
Code should be self-documenting. Use clear names and logic to replace comments.
Is each decision made once, explicitly, and as high in the call chain as possible?
Could variables be named better to understand intention? Will it be unambiguous after the next feature lands?
Does this work as intended?
