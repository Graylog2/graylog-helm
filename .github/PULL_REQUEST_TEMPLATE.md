## Summary
Short description of the change.

## Details
- List of meaningful technical changes

## Linked issues
This fixes #??

## PR Checklist
Check the items that apply to your change.

- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] This PR includes a new feature
- [ ] This PR includes a bugfix
- [ ] This PR includes a refactor

## Testing Checklist

### Static Validation
- [ ] Linter check passes: `helm lint ./charts/graylog`
- [ ] Helm renders local template successfully: `helm template graylog ./charts/graylog --validate`

### Installation
- [ ] Fresh installation completes successfully: `helm install graylog ./charts/graylog`
- [ ] All pods reach Running state: `kubectl rollout status statefulset/graylog`
- [ ] Helm tests pass: `helm test graylog`

### Functional (if applicable)
- [ ] Web UI accessible and login works
- [ ] DataNodes visible in _System > Cluster Configuration_
- [ ] Inputs can be created and receive data

### Upgrade (if applicable)
- [ ] Upgrade from previous release succeeds
- [ ] Scaling up/down works correctly
- [ ] Configuration changes apply correctly

### Specific to this PR
- [ ] _describe what was specifically tested_

## Notes for reviewers
- [ ] Verify all applicable tests above pass
- [ ] Validate that the linked issues are no longer reproducible, if applicable
- [ ] Sync up with the author before merging
- [ ] Squash merge, and check the PR title is a valid Conventional Commit, because release-please builds the changelog from it
