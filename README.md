# End-to-End CI/CD Lab: Jenkins + Docker + Kubernetes (K3s) on AWS EC2

A complete learning project. A Git push triggers Jenkins, which checks out the code, runs tests,
builds a Docker image, pushes it to Docker Hub, and deploys it to Kubernetes.

> Lab architecture: one Ubuntu EC2 instance runs Docker, Jenkins (containerized), and a single-node
> K3s cluster. This is for learning, not production. Do not expose Jenkins or Kubernetes API publicly.

## 1. AWS prerequisites

Create an Ubuntu 24.04 LTS EC2 instance:
- Recommended lab size: 4 vCPU / 16 GiB RAM (for example, `t3.xlarge`)
- 40 GiB gp3 EBS volume
- Security group inbound:
  - TCP 22 from **your public IP only**
  - TCP 8080 from **your public IP only** (Jenkins UI)
  - TCP 30080 from **your public IP only** (demo application)
- Do not open 6443 (Kubernetes API) or Docker's 2375 port to the internet.
- Assign an Elastic IP only if you need a stable public endpoint. This may incur charges.

A smaller instance may work for a very light test but can become memory constrained.

## 2. Install the lab

SSH to the EC2 instance, then:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone <YOUR_GITHUB_REPOSITORY_URL> jenkins-kubernetes-cicd-lab
cd jenkins-kubernetes-cicd-lab
chmod +x scripts/*.sh
sudo ./scripts/install-lab.sh
```

The script installs Docker and K3s, creates a Jenkins image with Docker CLI and kubectl,
and starts Jenkins with persistent storage. It uses host networking so Jenkins can reach
the single-node K3s API at `127.0.0.1:6443`.

Get Jenkins initial password:

```bash
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open `http://EC2_PUBLIC_IP:8080`, unlock Jenkins, install suggested plugins, and create an admin user.
Install/confirm these plugins in **Manage Jenkins → Plugins**:
- Pipeline
- Git
- Credentials Binding

## 3. Create Docker Hub credentials

1. Create a Docker Hub account and a personal access token.
2. In Jenkins: **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**.
3. Kind: **Username with password**.
4. Username: your Docker Hub username.
5. Password: Docker Hub access token (not your account password).
6. ID: `dockerhub-creds`.

Do not put registry passwords or tokens in source code.

## 4. Put the project in GitHub

Create an empty GitHub repository and push this project:

```bash
git init
git add .
git commit -m "Initial Jenkins Kubernetes CI/CD lab"
git branch -M main
git remote add origin https://github.com/<YOUR_USER>/<YOUR_REPO>.git
git push -u origin main
```

## 5. Create the Jenkins pipeline

1. Jenkins dashboard → **New Item**.
2. Name: `flask-kubernetes-cicd`.
3. Select **Pipeline**.
4. Under Pipeline, choose **Pipeline script from SCM**.
5. SCM: Git; Repository URL: your GitHub repository URL.
6. Branch: `*/main`; Script Path: `Jenkinsfile`.
7. Save → **Build Now**.

The Jenkinsfile uses the credential ID `dockerhub-creds`. It builds and pushes:
`docker.io/<DOCKERHUB_USERNAME>/devops-flask-lab:<BUILD_NUMBER>` and `:latest`.

### Set the Docker Hub username

Edit `Jenkinsfile` and replace `YOUR_DOCKERHUB_USERNAME` with your Docker Hub username.
Commit and push the change. This value is a public image namespace, not a secret.

## 6. Verify deployment

After a successful build:

```bash
sudo kubectl get nodes -o wide
sudo kubectl get all -n devops-lab
sudo kubectl rollout status deployment/flask-app -n devops-lab
```

Open:

`http://EC2_PUBLIC_IP:30080`

Health endpoint:

`http://EC2_PUBLIC_IP:30080/health`

You can also test from EC2:

```bash
curl http://127.0.0.1:30080/
curl http://127.0.0.1:30080/health
```

## 7. Test a new release

Change the message in `app.py`, then:

```bash
git add app.py
git commit -m "Update application message"
git push
```

Run the Jenkins job again (or configure a GitHub webhook). Watch the stages:
Checkout → Test → Build Image → Push Image → Deploy → Verify.
Then refresh the app. Kubernetes performs a rolling update.

### Optional GitHub webhook

For a webhook-triggered build:
1. Install/confirm the **GitHub** plugin in Jenkins.
2. In the Jenkins job, enable **GitHub hook trigger for GITScm polling**.
3. In GitHub repository → Settings → Webhooks → Add webhook:
   `http://EC2_PUBLIC_IP:8080/github-webhook/`
4. Content type: `application/json`; select push events.

For a real environment, put Jenkins behind HTTPS and do not expose it broadly.

## 8. Useful troubleshooting commands

```bash
# Jenkins
sudo docker ps
sudo docker logs -f jenkins
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# Kubernetes / K3s
sudo systemctl status k3s
sudo journalctl -u k3s -f
sudo kubectl get nodes
sudo kubectl get pods -n devops-lab -o wide
sudo kubectl describe pod -n devops-lab <POD_NAME>
sudo kubectl logs -n devops-lab deployment/flask-app
sudo kubectl get events -n devops-lab --sort-by=.metadata.creationTimestamp

# Deployment
sudo kubectl rollout history deployment/flask-app -n devops-lab
sudo kubectl rollout undo deployment/flask-app -n devops-lab
sudo kubectl rollout restart deployment/flask-app -n devops-lab
```

Common issues:
- `ImagePullBackOff`: check Docker Hub image name, visibility, and pull credentials if the repo is private.
  This lab expects a public Docker Hub repository by default.
- `docker: permission denied`: check that Jenkins has `/var/run/docker.sock` mounted and restart Jenkins.
- `kubectl connection refused`: check `systemctl status k3s`; Jenkins shares host networking.
- App unreachable: confirm NodePort 30080 is allowed from your IP and the pod is Ready.
- Jenkins build cannot find Docker: check `sudo docker exec jenkins docker version`.

## 9. Cleanup

Delete the Kubernetes workload:

```bash
sudo kubectl delete namespace devops-lab
```

Stop Jenkins:

```bash
sudo docker rm -f jenkins
```

Uninstall K3s (this deletes the local Kubernetes cluster):

```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

To remove the lab's Jenkins data too, delete the Docker volume only after you are sure you no longer need it:

```bash
sudo docker volume rm jenkins_home
```

## 10. Learning exercises

1. Change the app response and deploy a new build.
2. Add a `/ready` endpoint and configure Kubernetes readiness/liveness probes.
3. Add a second replica and observe pod distribution.
4. Break the Docker build intentionally and inspect the Jenkins failure.
5. Deploy a bad image and practise `kubectl rollout undo`.
6. Add a Kubernetes ConfigMap and consume it from the app.
7. Add a Secret for a sample app setting (never commit real secrets).
8. Add a staging namespace and a manual approval stage.
9. Configure GitHub webhook and automatic builds.
10. Move Jenkins to a separate EC2 instance and Kubernetes to a separate cluster.

## Security notes

This is deliberately a compact single-node lab. Jenkins has access to the host Docker socket
and Kubernetes admin kubeconfig; anyone who gains Jenkins administrator access can effectively
control the EC2 host and cluster. Restrict port 8080 to your IP, use strong credentials, keep
the host patched, and destroy the lab when finished. Do not reuse this design for production.
