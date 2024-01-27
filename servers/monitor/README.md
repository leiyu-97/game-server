需要在 /etc/docker/daemon.json 文件下加入，然后重启 docker daemon
```json
{
  "metrics-addr" : "0.0.0.0:9323",
  "experimental" : true
}
```
```shell
systemctl restart docker
```

Grafana Data Source 填 http://monitor_prometheus:9090

Grafana 推荐 dashboard:
13331