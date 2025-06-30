## Git Workflow Guidelines

- Do **not** commit directly to `main`. Always use a feature branch:
```sh
git checkout -b feat/my-feature
```
- Before opening a PR, **rebase or squash** your commits to keep history clean:
```sh
git rebase origin/main
```
- Use clear and concise commit messages. We recommend following [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
```sh
git commit -m "docs: add CONTRIBUTING.md"
```
- Ensure your branch is up to date with `main` before creating a PR:
```sh
git fetch origin
git rebase origin/main
```
- All PRs must be reviewed by at least one maintainer before merging.
