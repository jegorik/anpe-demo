"""
Infrastructure tests — validate Terraform and shell scripts without AWS credentials.

These tests are fast, purely local, and run in CI on every PR.
They verify:
  - Terraform HCL is correctly formatted
  - Terraform configuration is syntactically valid
  - All variable references resolve (no typos)
  - Shell scripts pass ShellCheck static analysis

Run locally:
    make test-infra
    scripts/run-tests.sh --infra

Requirements: terraform >= 1.9, shellcheck
"""
import subprocess
import os
import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TF_DIR = os.path.join(REPO_ROOT, "terraform")
SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")


def run(cmd: list[str], cwd: str = REPO_ROOT) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)


# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------

class TestTerraformFormat:
    def test_all_tf_files_are_formatted(self):
        """terraform fmt -check fails if any file needs reformatting."""
        result = run(["terraform", "fmt", "-check", "-recursive", "terraform/"])
        assert result.returncode == 0, (
            f"Terraform formatting issues found:\n{result.stdout}\n{result.stderr}"
        )


class TestTerraformValidate:
    def test_configuration_is_valid(self):
        """terraform validate catches undefined variables and invalid references."""
        # init must succeed first (uses cached providers if already initialised)
        init = run(["terraform", "-chdir=terraform", "init", "-backend=false"])
        assert init.returncode == 0, f"terraform init failed:\n{init.stderr}"

        result = run(["terraform", "-chdir=terraform", "validate"])
        assert result.returncode == 0, (
            f"Terraform validation failed:\n{result.stdout}\n{result.stderr}"
        )

    def test_all_variable_references_resolve(self):
        """No var.X reference should be missing a declaration in variables.tf."""
        import re
        import glob

        tf_files = glob.glob(os.path.join(TF_DIR, "*.tf"))
        all_refs: set[str] = set()
        for path in tf_files:
            with open(path, encoding="utf-8") as f:
                all_refs.update(re.findall(r"var\.([a-z_]+)", f.read()))

        with open(os.path.join(TF_DIR, "variables.tf"), encoding="utf-8") as f:
            declared = set(re.findall(r'variable "([a-z_]+)"', f.read()))

        undeclared = all_refs - declared
        assert not undeclared, f"Undeclared Terraform variables: {undeclared}"

    def test_terraform_files_exist(self):
        """Required Terraform files must all be present."""
        required = [
            "terraform.tf", "provider.tf", "variables.tf",
            "vpc.tf", "security_groups.tf", "main.tf",
            "iam.tf", "alb.tf", "ecs.tf", "outputs.tf",
        ]
        for filename in required:
            path = os.path.join(TF_DIR, filename)
            assert os.path.isfile(path), f"Missing Terraform file: {filename}"

    def test_tfvars_example_exists(self):
        path = os.path.join(TF_DIR, "terraform.tfvars.example")
        assert os.path.isfile(path), "terraform.tfvars.example is missing"

    def test_tfvars_not_committed(self):
        """terraform.tfvars must be covered by .gitignore — never committed."""
        import fnmatch
        gitignore = os.path.join(REPO_ROOT, ".gitignore")
        with open(gitignore, encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip() and not l.startswith("#")]
        assert any(fnmatch.fnmatch("terraform.tfvars", pattern) for pattern in lines), (
            "terraform.tfvars must be covered by .gitignore (literal or glob pattern)"
        )


# ---------------------------------------------------------------------------
# Shell scripts
# ---------------------------------------------------------------------------

class TestShellCheck:
    @pytest.mark.parametrize("script", ["check-prereqs.sh", "build-push.sh", "run-tests.sh"])
    def test_script_passes_shellcheck(self, script):
        """ShellCheck static analysis — catches quoting bugs, undefined vars, etc."""
        result = run(["shellcheck", "--severity=warning", os.path.join(SCRIPTS_DIR, script)])
        assert result.returncode == 0, (
            f"ShellCheck errors in {script}:\n{result.stdout}\n{result.stderr}"
        )

    @pytest.mark.parametrize("script", ["check-prereqs.sh", "build-push.sh", "run-tests.sh"])
    def test_script_is_executable(self, script):
        path = os.path.join(SCRIPTS_DIR, script)
        assert os.access(path, os.X_OK), f"{script} is not executable (chmod +x)"

    @pytest.mark.parametrize("script", ["check-prereqs.sh", "build-push.sh", "run-tests.sh"])
    def test_script_has_shebang(self, script):
        path = os.path.join(SCRIPTS_DIR, script)
        with open(path, encoding="utf-8") as f:
            first_line = f.readline().strip()
        assert first_line.startswith("#!/"), (
            f"{script} missing shebang line (found: {first_line!r})"
        )


# ---------------------------------------------------------------------------
# Docker Compose
# ---------------------------------------------------------------------------

class TestDockerCompose:
    def test_compose_file_exists(self):
        path = os.path.join(REPO_ROOT, "docker-compose.yml")
        assert os.path.isfile(path), "docker-compose.yml not found"

    def test_compose_config_is_valid(self):
        """docker compose config validates syntax without starting containers."""
        result = run(["docker", "compose", "config", "--quiet"])
        assert result.returncode == 0, (
            f"docker-compose.yml has syntax errors:\n{result.stderr}"
        )

    def test_compose_has_prometheus_service(self):
        """Prometheus service must be declared in docker-compose.yml."""
        path = os.path.join(REPO_ROOT, "docker-compose.yml")
        with open(path, encoding="utf-8") as f:
            content = f.read()
        assert "prometheus:" in content, "Missing 'prometheus' service in docker-compose.yml"

    def test_compose_has_grafana_service(self):
        """Grafana service must be declared in docker-compose.yml."""
        path = os.path.join(REPO_ROOT, "docker-compose.yml")
        with open(path, encoding="utf-8") as f:
            content = f.read()
        assert "grafana:" in content, "Missing 'grafana' service in docker-compose.yml"


# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

class TestMonitoring:
    MONITORING_DIR = os.path.join(REPO_ROOT, "monitoring")

    def test_prometheus_config_exists(self):
        path = os.path.join(self.MONITORING_DIR, "prometheus.yml")
        assert os.path.isfile(path), "monitoring/prometheus.yml not found"

    def test_prometheus_config_scrapes_api_gateway(self):
        import yaml
        path = os.path.join(self.MONITORING_DIR, "prometheus.yml")
        with open(path, encoding="utf-8") as f:
            config = yaml.safe_load(f)
        jobs = [sc["job_name"] for sc in config.get("scrape_configs", [])]
        assert "api-gateway" in jobs, "Prometheus must scrape 'api-gateway'"

    def test_prometheus_config_scrapes_worker(self):
        import yaml
        path = os.path.join(self.MONITORING_DIR, "prometheus.yml")
        with open(path, encoding="utf-8") as f:
            config = yaml.safe_load(f)
        jobs = [sc["job_name"] for sc in config.get("scrape_configs", [])]
        assert "worker" in jobs, "Prometheus must scrape 'worker'"

    def test_grafana_datasource_provisioning_exists(self):
        path = os.path.join(
            self.MONITORING_DIR, "grafana", "provisioning", "datasources", "prometheus.yml"
        )
        assert os.path.isfile(path), "Grafana datasource provisioning file not found"

    def test_grafana_datasource_points_to_prometheus(self):
        import yaml
        path = os.path.join(
            self.MONITORING_DIR, "grafana", "provisioning", "datasources", "prometheus.yml"
        )
        with open(path, encoding="utf-8") as f:
            config = yaml.safe_load(f)
        sources = config.get("datasources", [])
        assert any(ds.get("type") == "prometheus" for ds in sources), (
            "Grafana datasource must include a Prometheus datasource"
        )

    def test_grafana_dashboard_exists(self):
        path = os.path.join(self.MONITORING_DIR, "grafana", "dashboards", "anpe.json")
        assert os.path.isfile(path), "Grafana dashboard file monitoring/grafana/dashboards/anpe.json not found"

    def test_grafana_dashboard_is_valid_json(self):
        import json
        path = os.path.join(self.MONITORING_DIR, "grafana", "dashboards", "anpe.json")
        with open(path, encoding="utf-8") as f:
            dashboard = json.load(f)
        assert "panels" in dashboard, "Grafana dashboard JSON must contain 'panels'"
        assert len(dashboard["panels"]) > 0, "Grafana dashboard must have at least one panel"
