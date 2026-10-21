# https://boristane.com/blog/how-i-use-claude-code/

__1 million dollars__
Review the codebase is it production ready? I'm selling it for $1million dollars can it meet that standard.

__PLAN fast__
I want to ... <FEATURE>
Think deeply how to implement this in minimal and highly maintainable code, focusing on minimal technical debt and high readability. Refacto
ring is encouraged.

Then discuss

__PLAN.MD__
I want to ... <FEATURE>
Write a detailed plan.md document outlining how to implement this. include code snippets read source files before suggesting changes, base t
he plan on the actual codebase

Focus on minimal and highly maintainable code introducing minimal technical debt. Think deeply. Feel free to refactor.

__ALTERNATIVE__
Think deeply how to implement this in minimal and highly maintainable code, focusing on minimal technical debt and high readability. Refacto
ring is encouraged

Could this be implemented in minimal and highly maintainable code, focusing on minimal technical debt and high readability? Think deeply, th
en discuss

__TODO__
Sounds good. Add a detailed todo list to the plan, with all the phases and individual tasks necessary to complete the plan - don’t implement
 yet

Focus on minimal and highly maintainable code introducing minimal technical debt.

do not add unnecessary comments or jsdocs, do not use any or unknown types. continuously run typecheck to make su
re you’re not introducing new issues

__RESEARCH__
Read the run.py file and src/ folder in depth, understand how it works deeply, what it does and all its specificities. when that’s done, wri
te a detailed report of your learnings and findings in research.md.

read this folder in depth, understand how it works deeply, what it does and all its specificities. when that’s done, write a detailed report
 of your learnings and findings in research.md

study the <SYTEM> system in great details, understand the intricacies of it and write a detailed research.md deta

__REVIEW2__
A PR should never introduce, install or use 3rd party dependencies
A PR should be as small as possible - must be less than 100 lines of code.
If it contains two features that could be created in separate PRs the PR must be split.

A PR should not contain comments unless some code is very difficult to read (e.g. a regex expression)
A PR should not change lines unrelated to the feature it is implementing (general code clean up should always be made in a separate PR)
A PR should minimize the amount of technical debt it introduces. I.e. any function in our public sdk / clients quickly becomes something we
have to maintain forever.
If a PR does introduce technical debt, e.g. in a form of a new public facing function / endpoint, the requester must give a strong business
justification (“this function would be nice to have” is not good enough).

A PR must checked for side effects - e.g. someone (human or AI agent) must have reasoned about what things this PR might break. The side eff
ects doesn’t have to addressed, but must be considered and included in the PR description.
Any change to biolib-python should also update biolib-rs and reversely. The two clients must be kept in sync.
Consider whether any change in the PR could cause the user to see incorrect, stale, or misleading data — even if the code compiles and runs
without errors.