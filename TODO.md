# Remaining Work

The public API listed in `PLAN.md` exists. This checklist tracks the work
needed to make its behavior, safety, and documentation match the plan.

## Controlled interception

- [ ] Support calls originating from concurrent coroutines and verify that a
  response or release resumes only its own coroutine.
- [ ] Define and test behavior when the original method yields or performs
  asynchronous work after `mock.release`.
