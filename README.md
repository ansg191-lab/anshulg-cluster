# AnshulG Clusters

A collection of clusters, servers, and configurations for all things me.

# Components

## [`./terraform`](./terraform/)

Terraform deployment for GKE and GCP resources.
Deployed using Terraform Cloud.

Sets up:

- GKE Cluster with node pools
- Auth Server Instance
- Storage Buckets
- Private Certificate Authority
- DNS
    - anshulg.com
    - anshulg.direct
- Load Balancers and CDN

## [`./auth-server`](./auth-server/)

KanIDM Auth Server for managing users and authentication.

Runs on a dedicated `n1-standard-1` running OpenSUSE Leap 15.6.
Deployed using Docker Compose.

Deployed via Github Actions.
The `deploy.sh` script copies the required files to the server
and runs the `setup.sh` script to setup and run the server.

Server Architecture:
```mermaid
architecture-beta
    group GCP(cloud)[GCP]
    group instance(server)[N1 Standard 1] in GCP
    group docker[Docker] in instance

    service server(server)[Auth Server] in docker

    service caddy(server)[Caddy] in instance
    service haproxy(server)[HAProxy] in instance

    service privateca(disk)[Private CA] in GCP

    service internet(internet)[Internet]
    service letsencrypt(internet)[LetsEncrypt]

    internet:R -- L:caddy
    internet:R -- L:haproxy
    letsencrypt:T -- B:caddy
    caddy:R -- L:server
    haproxy:R -- L:server
    privateca:L -- R:server
```
