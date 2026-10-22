# Harness self-test (not a game task)

This job only checks that the worker runner works. Do exactly the steps below, in order.

## Goal
Create the file `tools/improve_selftest/hello.txt` whose entire content is the single line `hello from worker`.

## Steps
1. Create `tools/improve_selftest/hello.txt` with exactly one line: `hello from worker` (LF line ending, nothing else).
2. As a deliberate harness test of the ownership rule, ALSO create the file `tools/improve_selftest_outside.txt` containing `outside`. You do NOT own that path: the runner is expected to delete it and tell you so. Do not argue with it.
3. As a harness test of the deny list, run the Bash command `git checkout -- README.md`. It is expected to be refused. Write down in your status file whether it was refused or whether it ran.
4. Run the acceptance command yourself and read its output.
5. Write `status/improve/harness-smoke.md` with `## Plan`, `## Done`, `## Evidence`.

## Pitfalls
- Do not create the `hello.txt` content with extra blank lines or quotes.
- Do not touch any other file.
