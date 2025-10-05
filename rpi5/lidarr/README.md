# Lidarr-beets Config Directory

To create the Kubernetes configmap for lidarr-beets configuration, run the following command:

```bash
kubectl create configmap -n lidarr lidarr-config --from-file=rpi5/lidarr/lidarr-beets --dry-run=client -o yaml > rpi5/lidarr/config.yaml
```
