# Data Node handoff

What changed in the chart around Data Node over the last two weeks, what I validated, and what is still open.

## What changed

Rolling out a change to one workload used to roll everything. Now a Graylog change only rolls Graylog, and a Data Node change only rolls Data Node. Stakater Reloader is off by default for Data Node groups (`datanode.reloader.autoReload: false`). With multiple node groups it would restart them independently and could take down two groups at once. Roll groups yourself with `helm upgrade`, one at a time.

Node roles are configurable per group through `datanode.roles` and `datanode.extraNodeGroups`. Each group can have its own resources and config. See `docs/datanode-node-roles.md`.

S3 credentials can live in a user managed Secret instead of the values file. Graylog and Data Node can each get different credentials. Inline values still work. See `docs/graylog-secrets.md` and `examples/graylog/secrets/s3-secret.yaml`.

PodDisruptionBudgets accept `maxUnavailable` as an alternative to `minAvailable`. `datanode.podDisruptionBudget.consolidated: true` renders one PDB across every node group instead of one per group.

I also wrote Terraform for the OIDC provider, IAM role and buckets.

## Validated

- Node roles work and can be configured independently per group.
- Warm tier works with S3.
- Archive works with S3.

## Known issues

Two Data Node notifications will not stay dismissed: `Data Node Heap Size Warning` and `Data Node version mismatch`. Cloud mode suppresses them, but it also hides UI panels meant for Cloud tenants, so I would not use it here. No fix yet.

Switching from static S3 credentials to OIDC (IRSA) disconnected the pods from the backend. Cause not found. Pick one method before go-live and do not switch on a running cluster.

Every scaling operation on Data Node causes trouble. Scaling makes every pod roll, and the OpenSearch cluster goes unstable while it happens. Scale-in needs a drain first, and every index needs at least one replica before you start. Procedure so far is in `docs/graylog/datanode-scale-in.md`. The scale-out and full scaling section is still in progress.

OpenSearch telemetry is missing. TODO.

## How I manage OpenSearch

TODO: fill in. Suggested contents are the `osq.sh` tool, the checks I run before any change (`_cat/nodes`, `_cat/indices`, cluster health) and where the tool lives.

## Open items

- Finish the scaling section.
- Add OpenSearch metrics.
- Find the IRSA cause, and document the IRSA setup end to end.
- Decide what to do about the two notifications.
