# Reusable Jenkins bootstrap scripts

These scripts are designed to be usable from Packer, cloud-init/user-data, or manually.

## Files

- `jenkins_setup.sh` — installs Jenkins and orchestrates initial setup.
- `jenkins_unlock.sh` — creates the first Jenkins administrator through the setup wizard.
- `jenkins_plugins.sh` — installs plugins listed in `plugins.txt`.
- `jenkins_confirm_url.sh` — sets the Jenkins root URL.
- `jenkins_common.sh` — shared helper functions.
- `plugins.txt` — declarative plugin list.

## Required variables

For initial Jenkins setup:

```bash
export JENKINS_ADMIN_PASSWORD='replace-me'
```

Recommended variables:

```bash
export JENKINS_URL='http://127.0.0.1:8080'
export JENKINS_ROOT_URL='https://jenkins.example.com'
export JENKINS_ADMIN_USER='admin'
export JENKINS_ADMIN_FULLNAME='Jenkins Administrator'
export JENKINS_ADMIN_EMAIL='jenkins@example.com'
```

For a Packer AMI where the final URL is not known yet, disable root URL configuration:

```bash
export CONFIGURE_ROOT_URL=false
```

Then configure `JENKINS_ROOT_URL` during instance startup or via JCasC.

## Feature switches

```bash
INSTALL_GIT=true
RUN_INITIAL_SETUP=true
INSTALL_PLUGINS=true
CONFIGURE_ROOT_URL=true
```

## Example

```bash
sudo env \
  JENKINS_ADMIN_PASSWORD='temporary-build-password' \
  CONFIGURE_ROOT_URL=false \
  ./jenkins_setup.sh
```

Do not bake production credentials, AWS keys, application credentials, EKS kubeconfig, or environment-specific secrets into an AMI.

## Packer recommendation

For an AMI, keep environment-specific configuration out of the image. In particular, do not create EKS kubeconfig during the image build. Install `aws`, `kubectl`, and `helm` in a separate provisioning script and generate kubeconfig in the Jenkins pipeline.

The scripts deliberately do not create project credentials or jobs. Seed jobs, application credentials, AWS/EKS access, and deployment configuration should be separate from the reusable Jenkins base image.
