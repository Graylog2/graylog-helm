## Summary

Short description of the change.

## What changed
- List of meaningful changes

## Linked issues

This fixes #??

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] This PR includes a new feature
- [ ] This PR includes a bugfix
- [ ] This PR includes a refactor

## Testing Checklist

### Static Validation
- [ ] Linter check passes: `helm lint ./charts/graylog`
- [ ] Helm renders local template sucessfully: `helm template graylog ./charts/graylog --validate`

### Installation
- [ ] Fresh installation completes successfully: `helm install graylog ./charts/graylog`
- [ ] All pods reach Running state: `kubectl rollout status statefulset/graylog `
- [ ] Helm tests pass: `helm test graylog `

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
- [ ] Verify all tests above pass
- [ ] Verify all tests in [TESTING.md](https://github.com/Graylog2/graylog-helm/blob/main/docs/TESTING.md) pass
- [ ] Validate that the linked issues are no longer reproducible, if applicable
- [ ] Sync up with the author before merging
- [ ] The commit history should be preserved - use rebase-merge or standard merge options when applicable
