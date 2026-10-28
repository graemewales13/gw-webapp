# gw-webapp

A test three-tier web application running in the **gw-apps-prod** landing zone of the [gw Azure landing zone](https://github.com/graemewales13/gw-azure-landing-zone).

```
Internet ──HTTPS──► Frontend ───────────► API ───────────────► Database
                    Azure Container Apps   Linux VM (Ubuntu)    PostgreSQL Flexible Server
                    nginx in Docker        FastAPI, configured   private endpoint only,
                    snet-webapp-frontend   by Ansible            Entra ID auth only
                                           snet-webapp-api       snet-webapp-pe
                    └──────────────── vnet-gw-prod-eas (spoke, peered to the hub) ─────┘
```

| Tier | Built with | Deployed by |
|---|---|---|
| Frontend | Docker image ([frontend/](frontend/)): static page, nginx proxies `/api/` to the VM | GitHub Actions → ACR → Container Apps ([frontend.yml](.github/workflows/frontend.yml)) |
| API | Python FastAPI ([api/](api/)) under systemd | GitHub Actions publishes a bundle; the VM applies it with Ansible ([ansible/](ansible/), [api.yml](.github/workflows/api.yml)) |
| Database | PostgreSQL 16, Burstable B1ms | Terraform ([infra/](infra/)) |
| Infrastructure | Terraform | HCP Terraform workspace `apps/gw-webapp-prod` (VCS-driven, `infra/`) |

## Security design
- **No secrets anywhere.**
  - HCP Terraform and GitHub Actions sign in to Azure with OIDC.
  - The API signs in to PostgreSQL with the VM's managed identity, using an Entra ID token instead of a password.
  - The container app pulls from ACR with its managed identity.
- **Least privilege.** The landing zone vends this workspace's identities, scoped to the gw-apps-prod subscription only, with no right to grant Owner or access-admin roles. The GitHub identity can only push to ACR, update the one container app, upload to the deploy container and run commands on the one VM, and only from `main`.
- **Network.**
  - Only the frontend is public.
  - The VM has no public IP and no SSH path in. Its NSG allows only the frontend subnet on the API port.
  - PostgreSQL has public access disabled. Its private endpoint subnet allows only the API subnet on 5432.
- **DNS.** The private endpoint's record is added to the platform's central `privatelink.postgres.database.azure.com` zone by a landing zone policy. This repo never touches the Connectivity subscription.
- **Patching.** Ansible enables `unattended-upgrades`. Azure Update Manager reports patch status.

## How the VM is configured
There's no Bastion and no inbound SSH, so nothing can push configuration to the VM over SSH. The repo is private, and the VM holds no GitHub credentials. Instead, CI publishes a build artifact and the VM pulls it:
1. Terraform renders [cloud-init](infra/templates/cloud-init.yaml.tftpl). On first boot it:
   - installs Ansible
   - writes `/etc/gw-webapp/vars.yml` (DB host, identity, and so on)
   - installs `gw-apply-config` and a systemd timer that runs it every 15 minutes
2. [api.yml](.github/workflows/api.yml) runs on every merge that changes `api/` or `ansible/`. It tars those two folders and uploads them to the private storage account ([deploy-store.tf](infra/deploy-store.tf)). Then it uses Run Command to start `gw-config.service` straight away.
3. `gw-apply-config` downloads the bundle with the VM's **managed identity** and runs [ansible/site.yml](ansible/site.yml) locally. The timer means manual changes get put back.

Blob versioning keeps every bundle. To roll back, either restore an earlier version of `api-bundle.tar.gz`, or revert the commit and let CI redeploy.

## First deployment
Prerequisites in the landing zone repo: the prod landing zone is onboarded, and the PR adding workload vending and the PostgreSQL DNS zone is merged and applied.

1. **Create the GitHub repo** `graemewales13/gw-webapp` (private) and push this code. In GitHub → Settings → Applications → *Terraform Cloud* → Configure, make sure the HCP Terraform app has access to it.
2. **Landing zone bootstrap** (`terraform apply` in `landing-zone/bootstrap`). This creates the HCP Terraform project `apps`, the workspace `gw-webapp-prod` linked to `infra/`, and its plan and apply identities.
3. **HCP Terraform:** `apps/gw-webapp-prod` → *New run* → *Plan and apply*. This takes about 15 minutes; PostgreSQL is the slow part.
4. **GitHub repository variables:** copy `github_actions_variables` from the run's outputs into Settings → Secrets and variables → Actions → **Variables**.
5. **Deploy both tiers:** Actions → *api* → *Run workflow*, then *frontend* → *Run workflow*. Until then the app shows the nginx welcome page and the VM has nothing to apply.
6. **Open `frontend_url`** (from the outputs). Allow a few minutes after the apply for the landing zone policy to register the database's DNS record.

## Checking on it
| What | Where |
|---|---|
| Frontend logs | Container app → *Log stream* |
| VM bootstrap | VM → *Run command* → `RunShellScript`: `cloud-init status --long; tail -50 /var/log/cloud-init-output.log` |
| Config runs | Run command: `journalctl -u gw-config --since -1h` |
| API | Run command: `systemctl status webapp-api; curl -s localhost:8000/api/health/db` |
| DNS registration | Private endpoint → *DNS configuration* should list `privatelink.postgres.database.azure.com` |

## Cost (East Asia, approx.)
| Resource | Monthly |
|---|---|
| Container Apps (consumption, scales to zero) | about £0 within the free grant |
| ACR Basic | about £4 |
| VM B2pts v2 (Arm64) + 30 GB disk | about £6 + £2 |
| PostgreSQL B1ms + 32 GB | about £13 (free for 12 months on new accounts) |
| Private endpoint | about £6 |
| Storage (config bundles) | pennies |

Stop the VM and PostgreSQL server when you're not using them, or `terraform destroy`.

## Local development
```powershell
# Frontend (API_UPSTREAM is required by the nginx template)
docker build -t frontend frontend
docker run --rm -p 8080:8080 -e API_UPSTREAM=http://host.docker.internal:8000 frontend
```

## Contributing
Same conventions as the landing zone: `feat/…`, `fix/…` branches, Conventional Commit PR titles (checked by CI), and squash merge.
