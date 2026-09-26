# wm-infra-netlab-db

The shared Postgres database for [wm-infra-netlab](https://github.com/WilliamFly/wm-infra-netlab).
One owning repo for a resource every app needs — the Rust app first,
the Node app later — so there's exactly one place that provisions and
can destroy it. See
[ADR 0004](https://github.com/WilliamFly/wm-infra-netlab/blob/main/docs/decisions/0004-shared-db-own-repo.md)
for why this isn't part of `app-rust` even though only one app uses it
so far.

| | |
|---|---|
| Hostname | `netlab-db` |
| Admin user | `netlab-admin` (SSH key only) |
| data-net IP | `10.0.3.20` |
| Postgres | Listens on all interfaces, `pg_hba.conf` allows `10.0.2.0/24` (private-net) only |
| DB / role | Created on boot from `db_name`/`db_app_user`/`db_app_password` vars |

This repo does **not** reference `wm-infra-netlab-network-foundation`'s
Terraform state — it imports its own copy of the base image and attaches
to `data-net` by name (`network_name`, not `network_id`), same decoupling
pattern used throughout this project.

Hardening (`harden-baseline`) is deliberately not applied yet — proving
connectivity with a real service came first; hardening can be layered on
via Ansible the same way the router got it.

## ⚠️ Provisioning currently requires a manual step

`data-net` has no route to the internet (by design — see
[ADR 0001](https://github.com/WilliamFly/wm-infra-netlab/blob/main/docs/decisions/0001-network-segmentation.md)),
which means cloud-init's live `apt install postgresql` step **fails
silently** on first boot. `terraform apply` alone does NOT give you a
working Postgres — see
[ADR 0005](https://github.com/WilliamFly/wm-infra-netlab/blob/main/docs/decisions/0005-isolated-tier-provisioning.md)
for the full story and the planned real fix (Packer-baked images).

**Until that's built, after `terraform apply`, do this:**

0. Wait for cloud-init to actually finish before touching the VM further:
   ```bash
   ssh -J netlab-admin@10.0.1.10 netlab-admin@10.0.3.20
   cloud-init status --wait
   ```
1. In `wm-infra-netlab-network-foundation/ansible`, temporarily open
   `data-net`'s egress:
   ```bash
   ansible-playbook playbook-router.yml -e router_temp_allow_data_egress=true
   ```
2. SSH into this VM and finish setup by hand:
   ```bash
   ssh -J netlab-admin@10.0.1.10 netlab-admin@10.0.3.20

   sudo apt update
   sudo apt install -y postgresql
   echo "listen_addresses = '*'" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
   echo "host all all 10.0.2.0/24 scram-sha-256" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
   sudo systemctl restart postgresql
   sudo -u postgres psql -c "CREATE USER app_user WITH PASSWORD 'your-real-password';"
   sudo -u postgres psql -c "CREATE DATABASE netlab_app OWNER app_user;"
   ```
   (Use the actual `db_app_user`/`db_name`/`db_app_password` from your
   `terraform.tfvars`, not necessarily these literal defaults.)
3. Close the egress hole again:
   ```bash
   # back in network-foundation/ansible
   ansible-playbook playbook-router.yml -e router_temp_allow_data_egress=false
   ```

## Consuming this from an app repo

Apps connect by IP — they never provision this VM themselves:
```
Host:     10.0.3.20
Database: (value of db_name, default netlab_app)
User:     (value of db_app_user, default app_user)
Password: (value of db_app_password — get this out-of-band, never committed)
```

## Prerequisites

- `network-foundation`'s networks + router already applied and working
- Terraform >= 1.9, `dmacvicar/libvirt` provider `>= 0.8.1, < 0.9`

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set base_image_path, ssh_public_key, db_app_password

terraform init
terraform plan
terraform apply
```

## Verifying

```bash
ssh -J netlab-admin@10.0.1.10 netlab-admin@10.0.3.20
```

Inside the DB VM:
```bash
sudo -u postgres psql -c "\l"   # should list the app database
```

From a VM on `private-net` (once one exists), confirm Postgres is
reachable through the router:
```bash
nc -zv 10.0.3.20 5432
```

## Security / Hardening

This VM has `harden-baseline` applied via `ansible/playbook-db.yml`:

- SSH hardened (no root login, no password auth)
- `ufw` enabled, default-deny incoming
- Port 5432 (Postgres) is scoped to `10.0.2.0/24` (private-net) only —
  not reachable from data-net's other hosts or the internet
- `fail2ban` active on sshd
- `unattended-upgrades` enabled

Re-run after any change to `ansible/group_vars/db.yml`:

```bash
cd ansible
ansible-playbook playbook-db.yml
```

**Note:** because `data-net` has no internet route by design (see ADR 0005 in
`wm-infra-netlab`), any playbook run that needs to *install* a new package
(not just configure one already present) requires the same temporary egress
toggle documented above — flip `router_temp_allow_data_egress=true` on the
router, run the playbook, flip it back off.
