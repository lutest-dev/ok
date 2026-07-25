# Changesets

Every user-facing change needs a changeset. Run `npx changeset`, select the
appropriate SemVer bump, and describe the change in English.

When changesets reach `main`, the release workflow opens or updates a version
pull request. Merging that pull request publishes the Wally package and creates
a GitHub Release with `ok.rbxm` attached.
