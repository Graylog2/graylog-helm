---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

> [!CAUTION]
> Do not paste credentials into this issue. This includes Kubernetes `Secret` manifests,
> base64 or decoded secret values, private values files, tokens, private keys, and MongoDB
> URIs. The output of `helm get all`, `helm template`, and `kubectl get secret` can contain
> credentials. Redact them before you paste. This issue is public.
>
> To report a security vulnerability, contact the maintainers privately. Do not open a
> public issue.

## Summary
_Give a brief description of the problem._

### Details
_Explain with further technical details, if applicable._

### Impact
_What is affected by this issue, and why does it matter?_

## How to Reproduce?

## Environment

- Helm chart version:
- Graylog version:
- Kubernetes version:
- Cloud provider / platform:

### Pre-flight checks
- [ ] `helm lint ./charts/graylog` passes
- [ ] Checked existing issues for duplicates
- [ ] I removed every credential, token, and secret value from the text, logs, and screenshots in this issue

### Steps to reproduce the issue:
1. ...
2. ...

**Expected behavior**
_A clear and concise description of what you expected to happen._

## Notes for maintainers
_Any additional context, logs, or screenshots_
