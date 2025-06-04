# graylog-helm
A helm chart for Graylog

## TLDR
Install
```bash
helm upgrade --install graylog graylog -f graylog/values-glc.yaml
```
Uninstall
```bash
helm uninstall graylog
```


## Mongo

```bash
mongosh -u admin -p password admin --eval "db.getSiblingDB('graylog_1').addUser('graylog_1', 'password');"
```



,graylog-datanode-1.{{ .Release.Namespace }}.svc.cluster.local,graylog-datanode-2.{{ .Release.Namespace }}.svc.cluster.local"



```
kc delete statefulset datanode
kc delete pvc datanode-datanode-0
kc delete pvc datanode-datanode-1
kc delete pvc datanode-datanode-2
kc delete statefulset graylog
