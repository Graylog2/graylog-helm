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
- [ ] `helm lint ./charts/graylog` passes
- [ ] `helm template graylog ./charts/graylog --validate` passes

### Installation
- [ ] Fresh installation completes successfully
- [ ] All pods reach Running state
- [ ] `helm test graylog -n graylog` passes

### Functional (if applicable)
- [ ] Web UI accessible and login works
- [ ] DataNodes visible in System > Data Nodes
- [ ] Inputs can be created and receive data

### Upgrade (if applicable)
- [ ] Upgrade from previous release succeeds
- [ ] Scaling up/down works correctly
- [ ] Configuration changes apply correctly

### Specific to this PR
- [ ] _describe what was specifically tested_

## Notes for reviewers
- [ ] Verify all tests in [TESTING.md](https://github.com/Graylog2/graylog-helm/blob/main/docs/TESTING.md) pass
- [ ] Sync up with the author before merging
- [ ] The commit history should be preserved - use rebase-merge or standard merge options when applicable
