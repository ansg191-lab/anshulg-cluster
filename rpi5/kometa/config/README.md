# Kometa Config Directory

To create the Kubernetes secret for Kometa configuration, run the following command:

```bash
kubectl create secret generic -n kometa kometa-config --from-file=rpi5/kometa/config --dry-run=client -o yaml > rpi5/kometa/secret.unencrypted.yaml
```
