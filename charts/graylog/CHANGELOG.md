# Changelog

## [2.0.0](https://github.com/Graylog2/graylog-helm/compare/graylog-1.0.0...graylog-2.0.0) (2026-08-27)


### ⚠ BREAKING CHANGES

* **graylog:** `appVersion` moves from 7.0 to 7.1.8. `graylog.image.tag` and `datanode.image.tag` default to `appVersion`, so upgrading moves the running Graylog and Data Node images unless you pin both tags ([#181](https://github.com/Graylog2/graylog-helm/issues/181)) ([eee5bd8](https://github.com/Graylog2/graylog-helm/commit/eee5bd839e03fb005aa853e4ad38ee5a94eaa65a))
* **values:** `global.imagePullSecrets`, `graylog.image.imagePullSecrets` and `datanode.image.imagePullSecrets` now take `{name: <secret>}` objects instead of bare strings. Schema validation rejects the old string form ([#93](https://github.com/Graylog2/graylog-helm/issues/93)) ([cdb719c](https://github.com/Graylog2/graylog-helm/commit/cdb719c23f337f500752d941a09cb48383f2428e))
* **mongodb:** the default replica set is now 3 data-bearing members with no arbiter, replacing 2 members plus 1 arbiter. Upgrading on the defaults adds a member and drops the arbiter, so budget for a third data volume ([#127](https://github.com/Graylog2/graylog-helm/issues/127)) ([47edf85](https://github.com/Graylog2/graylog-helm/commit/47edf8579675a237c2b233c2f5778727e94b972b))
* **mongodb:** the chart now sets MongoDB container resources, which nothing could override before. A pod reserves 300m/1152Mi instead of the operator's 1000m/800M, and upgrading rolls the replica set ([#176](https://github.com/Graylog2/graylog-helm/issues/176)) ([e49b97f](https://github.com/Graylog2/graylog-helm/commit/e49b97fdd6a31316f654e6fc154eaf0ee3c3d7ba))
* pods and containers now run under a restricted security context: `runAsNonRoot: true`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, and all capabilities dropped except `NET_BIND_SERVICE` on graylog and the file-ownership set on datanode. A custom image that runs as root or needs other capabilities will not start ([#100](https://github.com/Graylog2/graylog-helm/issues/100)) ([cb9bd63](https://github.com/Graylog2/graylog-helm/commit/cb9bd63313f8664a7128767d22fbf24e40fdd723))
* **values:** removed `datanode.persistence.enabled`, `datanode.persistence.data.existingClaim`, `datanode.persistence.data.selector`, `datanode.persistence.data.dataSource`, `datanode.persistence.nativeLibs.existingClaim`, `datanode.persistence.nativeLibs.selector`, `graylog.persistence.mountPath` and `graylog.persistence.selector`. None of them were wired to anything ([6571951](https://github.com/Graylog2/graylog-helm/commit/657195144e47a7fb79e126a00dd78cd2dddf5293))
* **geo-ip:** the MaxMind database update runs as a sidecar on the Graylog pod instead of a CronJob. `graylog.config.geolocation.maxmindGeoIp.cronSchedule` moves to `graylog.config.geolocation.sidecar.schedule`, and `postInstallRun` is gone ([#129](https://github.com/Graylog2/graylog-helm/issues/129)) ([e9c0354](https://github.com/Graylog2/graylog-helm/commit/e9c03545fcc7a093c9de40fb800ca68fecffe8dc))
* **ingress:** `ingress.forwarder` splits into two channels, `ingress.forwarder.messageChannel` and `ingress.forwarder.configChannel`, each with its own `className`, `annotations`, `labels`, `hosts` and `tls`. Existing forwarder ingress values need rewriting, not renaming ([#160](https://github.com/Graylog2/graylog-helm/issues/160)) ([29c1430](https://github.com/Graylog2/graylog-helm/commit/29c14308ac430f5e3c5a2dec5b84c2205ecb5d96))
* **datanode:** the native-libs volume claim template changes name from `nativeLibs` to `native-libs`. `volumeClaimTemplates` is immutable, so Kubernetes rejects the upgrade for anyone running with `datanode.persistence.nativeLibs.enabled=true`. Delete the StatefulSet with `--cascade=orphan` first ([#75](https://github.com/Graylog2/graylog-helm/issues/75)) ([5fc7e22](https://github.com/Graylog2/graylog-helm/commit/5fc7e22e1a3fde8e25c6eacbf11051c1815e764a))
* **graylog:** `terminationGracePeriodSeconds` is now 300, and a preStop hook drains the journal before shutdown. Pod deletion, node drains and rolling upgrades take up to five minutes per pod ([#147](https://github.com/Graylog2/graylog-helm/issues/147)) ([c643cd0](https://github.com/Graylog2/graylog-helm/commit/c643cd00da039bdc6b0e65f59dc8d1d084cdc3d9))
* PodDisruptionBudgets are on by default for both graylog and datanode. A single-replica deployment blocks node drains until you relax the budget
* **helpers:** an explicit `graylog.config.network.externalUri` now wins over the LoadBalancer Service lookup, and a bare hostname gets the scheme and app port appended. Setting both a LoadBalancer service and `externalUri` changes the advertised `http_external_uri` ([e3c965d](https://github.com/Graylog2/graylog-helm/commit/e3c965df087ca13ccd4967dc087968a1971271c1))
* the chart renames the init script ConfigMap from the fixed `init-script-cm` to `<release>-graylog-init-cm`, so two releases can share a namespace. External references to the old name break ([#79](https://github.com/Graylog2/graylog-helm/issues/79)) ([25653e2](https://github.com/Graylog2/graylog-helm/commit/25653e2bf13ac1d2bb38aafb514034800a4380d8))
* the chart writes the generated root password to the backup Secret instead of printing it in `NOTES.txt`. Anything scraping the install output for the password must read the Secret ([33499f2](https://github.com/Graylog2/graylog-helm/commit/33499f2f41169e570ad886f9e251cf155f992304))
* **probes:** both StatefulSets now get a startupProbe, on by default. It allows 330s before the kubelet restarts the container, so an install that takes longer restarts in a loop until you raise `startupProbe.failureThreshold` ([#169](https://github.com/Graylog2/graylog-helm/issues/169)) ([b411145](https://github.com/Graylog2/graylog-helm/commit/b411145e50e78929ba69f97a4bd453187111e7b9))
* **probes:** removed `graylog.livenessProbe.successThreshold` and `datanode.livenessProbe.successThreshold`. The schema does not reject unknown keys, so either one still validates and does nothing ([#169](https://github.com/Graylog2/graylog-helm/issues/169)) ([b411145](https://github.com/Graylog2/graylog-helm/commit/b411145e50e78929ba69f97a4bd453187111e7b9))


### Features

* Bring Your Own Opensearch ([#135](https://github.com/Graylog2/graylog-helm/issues/135)) ([5d531c1](https://github.com/Graylog2/graylog-helm/commit/5d531c1e182e4ecc0b9f256386a9a6e7538d491d))
* Allowing for custom labels and annotations to rendered kubernetes manifests. ([#160](https://github.com/Graylog2/graylog-helm/issues/160)) ([29c1430](https://github.com/Graylog2/graylog-helm/commit/29c14308ac430f5e3c5a2dec5b84c2205ecb5d96))
* **data-node:** Adding sysctlInit datanode init container to set vm.max_map_count ([8270c06](https://github.com/Graylog2/graylog-helm/commit/8270c064a6706ff796c5d5d597440ae3989eb6d0))
* **geo-ip:** Setting up side car geoip update, working downloads ([#129](https://github.com/Graylog2/graylog-helm/issues/129)) ([e9c0354](https://github.com/Graylog2/graylog-helm/commit/e9c03545fcc7a093c9de40fb800ca68fecffe8dc))
* Safe Graylog Journal Draining ([#147](https://github.com/Graylog2/graylog-helm/issues/147)) ([c643cd0](https://github.com/Graylog2/graylog-helm/commit/c643cd00da039bdc6b0e65f59dc8d1d084cdc3d9))
* Updating datanode and graylog health check and startup probes ([#169](https://github.com/Graylog2/graylog-helm/issues/169)) ([b411145](https://github.com/Graylog2/graylog-helm/commit/b411145e50e78929ba69f97a4bd453187111e7b9))
* Updating to Graylog, and Datanode to 7.1.8 ([#181](https://github.com/Graylog2/graylog-helm/issues/181)) ([eee5bd8](https://github.com/Graylog2/graylog-helm/commit/eee5bd839e03fb005aa853e4ad38ee5a94eaa65a))


### Bug Fixes

* correct imagePullSecrets schema to use LocalObjectReference format ([#93](https://github.com/Graylog2/graylog-helm/issues/93)) ([cdb719c](https://github.com/Graylog2/graylog-helm/commit/cdb719c23f337f500752d941a09cb48383f2428e))
* **datanode:** use with for each secret field ([#77](https://github.com/Graylog2/graylog-helm/issues/77)) ([8bcd2d3](https://github.com/Graylog2/graylog-helm/commit/8bcd2d374fc26cfc9c73ea05efcc42adae6a1237))
* encode GRAYLOG_HTTP_TLS_KEY_PASSWORD ([#76](https://github.com/Graylog2/graylog-helm/issues/76)) ([992c615](https://github.com/Graylog2/graylog-helm/commit/992c61580cd99bb89da9c8b53c2531accf4140fd))
* **geo-ip:** Updating GeoIP default image and secret handling ([#168](https://github.com/Graylog2/graylog-helm/issues/168)) ([64aed49](https://github.com/Graylog2/graylog-helm/commit/64aed494cd45af060e4775bf1db1d9391f99ae5d))
* **helpers:** Prefer an explicit externalUri over the Service lookup ([e3c965d](https://github.com/Graylog2/graylog-helm/commit/e3c965df087ca13ccd4967dc087968a1971271c1))
* **ingress:** point defaultBackend at the fallback Service port ([91bee91](https://github.com/Graylog2/graylog-helm/commit/91bee91920a4aed7c921190f08df0740577260d1))
* **mongodb:** let MongoDB container resources be configured ([#176](https://github.com/Graylog2/graylog-helm/issues/176)) ([e49b97f](https://github.com/Graylog2/graylog-helm/commit/e49b97fdd6a31316f654e6fc154eaf0ee3c3d7ba))
* rename native-libs pvc template ([#75](https://github.com/Graylog2/graylog-helm/issues/75)) ([5fc7e22](https://github.com/Graylog2/graylog-helm/commit/5fc7e22e1a3fde8e25c6eacbf11051c1815e764a))
* **secrets:** Accept secret peppers of exactly 64 characters ([59f44af](https://github.com/Graylog2/graylog-helm/commit/59f44afa236aca7acd6e42a82c3886dfad873f85))
* **secrets:** Adding graylog-root-sha2 to automatic password generation ([21fcb15](https://github.com/Graylog2/graylog-helm/commit/21fcb15ef5dc158c8d5328fd0b79e97bb523ebcf))
* **secrets:** Adding graylog-root-sha2 to automatic password generation ([9390114](https://github.com/Graylog2/graylog-helm/commit/93901143e8a17f377043c44cecc4e89a979e0ec4))
* **service-accounts:** Fixing bug in service account automount ([#130](https://github.com/Graylog2/graylog-helm/issues/130)) ([fdff2a7](https://github.com/Graylog2/graylog-helm/commit/fdff2a7533b71e759df12b65b7cf5d08d15c486c))
* StatefulSet checksums ([#83](https://github.com/Graylog2/graylog-helm/issues/83)) ([bd8c9a3](https://github.com/Graylog2/graylog-helm/commit/bd8c9a368604f4a98fe1964662c46da718952336))
* use release-specific templated names ([#79](https://github.com/Graylog2/graylog-helm/issues/79)) ([25653e2](https://github.com/Graylog2/graylog-helm/commit/25653e2bf13ac1d2bb38aafb514034800a4380d8))
* use selectorLabels ([#80](https://github.com/Graylog2/graylog-helm/issues/80)) ([1b7f6ee](https://github.com/Graylog2/graylog-helm/commit/1b7f6ee481337f5b13c7bbd153d74a3bab2cd6b6))
* use toYaml with each nodeSelector ([#78](https://github.com/Graylog2/graylog-helm/issues/78)) ([2fab1bd](https://github.com/Graylog2/graylog-helm/commit/2fab1bd0113c8be104095128211d9646c8c82ac5))
* **values:** Remove unused persistence configuration values ([6571951](https://github.com/Graylog2/graylog-helm/commit/657195144e47a7fb79e126a00dd78cd2dddf5293))


### Documentation

* **chart:** add an upgrade guide and document the commit-driven release ([#182](https://github.com/Graylog2/graylog-helm/issues/182)) ([7400c0d](https://github.com/Graylog2/graylog-helm/commit/7400c0df7e079c9ff4e4723357a83af1246c0ce6))
