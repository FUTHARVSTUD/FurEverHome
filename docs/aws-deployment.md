# FurEverHome AWS Deployment Guide

This guide provisions a single EC2 instance that runs the FurEverHome stack via `docker compose` and exposes the frontend on port 80 so it is reachable from the public internet.

## 1. Prerequisites

- AWS account with permissions to create EC2 instances, security groups, key pairs, and Route 53 records (optional).
- Jenkins controller with Docker installed (for building images) and SSH access to the EC2 instance.
- GitHub, Docker Hub, and AWS credentials already stored in Jenkins credentials store.
- Local clone of this repository (or configure Jenkins to check it out).

## 2. AWS Networking and Compute

1. **Security group**
   - In the target VPC create a security group, e.g. `fureverhome-sg`.
   - Inbound rules: allow TCP 22 (SSH) from your admin IP range, TCP 80 (HTTP) from `0.0.0.0/0`. Add TCP 443 later if you terminate TLS on the instance.
   - Outbound: allow all traffic (default).

2. **EC2 instance**
   - Launch an Ubuntu 22.04 LTS (or Amazon Linux 2023) instance, t3.medium is a good starting point.
   - Attach the `fureverhome-sg` security group.
   - Create or select an EC2 key pair for SSH (this needs to be uploaded to Jenkins as an SSH credential later).
   - Enable a public IPv4 address. Note the public DNS name; you will use it as the temporary access URL.

## 3. Bootstrapping the EC2 host

SSH into the instance and run the following to install Docker Engine and the Docker Compose plugin:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker ubuntu   # replace ubuntu with your user if different
newgrp docker
```

## 4. Deploying the application manually (first run)

```bash
# 1. Clone the repository
cd /opt
sudo git clone https://github.com/saumybhardwajclg/FurEverHome.git fureverhome
sudo chown -R ubuntu:ubuntu fureverhome
cd fureverhome

# 2. Create the production env file
cp .env.production.example .env.production
nano .env.production   # populate secrets, JWT secret, and REACT_APP_API_BASE

# 3. Build and start the stack
REACT_APP_API_BASE="http://$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)/api" \
  docker compose -f docker-compose.prod.yml up -d --build

# 4. Check status
docker compose -f docker-compose.prod.yml ps
```

The frontend will be reachable at `http://<public-dns-or-ip>/`. Backend health check: `http://<public-dns-or-ip>/api/health`.

## 5. Optional: assign a friendly domain and HTTPS

1. Create an A record in Route 53 pointing your domain (e.g. `app.example.com`) to the EC2 public IP or, preferably, to an Elastic IP associated with the instance so the address does not change.
2. Add port 443 to the security group.
3. Install and configure Traefik or Nginx reverse proxy with certbot on the instance to terminate TLS, or move to an Application Load Balancer if you need automatic certificate management.
4. Update `.env.production` so `REACT_APP_API_BASE` and `CORS_ORIGIN` (optional) use the new HTTPS endpoint.

## 6. Wiring Jenkins for one-click deploys

1. **Required Jenkins plugins**
   - SSH Agent Plugin (bundled with most Jenkins installs).
   - Credentials Binding Plugin (for secret files).

2. **Create credentials**
   - EC2 SSH key: add as `SSH Username with private key` and note the ID (the repository Jenkinsfile expects `ec2-deployer`).
   - Production env file: store the contents of `.env.production` as a secret file credential (ID `fureverhome-prod-env`).

3. **Pipeline configuration**
   - Create a multibranch or pipeline job that uses this repository's `Jenkinsfile` (already committed).
   - Adjust the `EC2_HOST`, `REMOTE_DIR`, `PUBLIC_URL`, or credential IDs in the Jenkinsfile if your environment differs.
   - Ensure the Jenkins agent that runs the job has Docker CLI available if you want the optional compose validation stage to run (otherwise the stage skips automatically).

4. **How the Jenkinsfile works**
   - Stage `Checkout` pulls the latest code.
   - Stage `Validate Compose Config` runs `docker compose config` when Docker is present to catch syntax errors early.
   - Stage `Deploy to EC2` wraps the new `scripts/deploy.sh` helper, authenticates with the EC2 SSH key, uploads the secret env file, pulls the latest code on the instance, and runs `docker compose -f docker-compose.prod.yml up -d --build`.
   - Stage `Smoke Test` hits `${PUBLIC_URL}/api/health` to confirm the deployment is live.

5. **Triggering deployments**
   - Enable webhook/SCM polling so pushes to `main` deploy automatically, or trigger manually from the Jenkins UI when you are ready to release.

## 7. Verifying new releases

After each deployment run:

```bash
# On the EC2 instance
docker compose -f docker-compose.prod.yml ps
curl -fsS http://localhost:5000/api/health
curl -I http://localhost/
```

If something fails, view logs with `docker compose -f docker-compose.prod.yml logs -f backend`, etc.

## 8. Hardening checklist

- Replace default Mongo credentials and restrict network access (Mongo runs in a private container network and is not exposed externally).
- Regularly rotate the EC2 SSH key and Jenkins credentials.
- Consider moving MongoDB to a managed service (Amazon DocumentDB or MongoDB Atlas) for production workloads.
- Add monitoring/alerting (CloudWatch agent or third-party) and enable automated backups of the EC2 volume.
- Migrate to an ECS Fargate or EKS deployment if you need horizontal scaling or zero-downtime deploys later.
