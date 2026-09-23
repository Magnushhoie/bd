Before running code:
- Check for any pre-existing environments (e.g. conda) to activate. Always ask before creating new environments.

For agents:
DO screen the codebase for related functionality and similar patterns which can/should be re-used, instead of writing new helpers and duplicating existing logic
DO run quick tests to inform your plan before implementing new code
DO validate that changes are working after implementation. Consider writing black-box end-to-end tests BEFORE writing code which can validate the pipeline after the PR is done (if this can be tested rapidly)
DO NOT re-write older tests which SHOULD pass unless explicitly expecting that they need to be changed before implementation
Consider a short design note covering intent, constraints, and alternatives considered
DO Focus on minimal and highly maintainable code with minimal technical debt and ease of review.
DO evaluate whether you can remove defensive programming, silent fall-backs, re-validating at every layer or unreasoned error checks. Critically evaluate whether this even SHOULD be possible and whether this check should occur here, or at all
DO remove backwards compatibility unless explicitly requested

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

Questions to ask:

Does the codebase already do this?
Does this diverge from how siblings are handled?
Code should be self-documenting. Use clear names and logic to replace comments.
Is each decision made once, explicitly, and as high in the call chain as possible?
Could variables be named better to understand intention? Will it be unambiguous after the next feature lands?