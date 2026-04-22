#!/bin/bash
set -euo pipefail

# =============================================================================
# Usage: ./setup.sh [OPTIONS]
#
# Options:
#   -e, --env <env>           Environment to deploy: dev|uat|prod (overrides .env)
#   -a, --all                 Process all environments (overrides .env)
#   -n, --dry-run             Print what would be done without making changes
#   -y, --yes                 Auto-confirm all prompts (required for prod in CI)
#   -s, --skip-playbook       Build inventories only, do not run Ansible
#   -d, --skip-deps           Skip venv/pip/galaxy installation steps
#   -t, --tags <tags>         Ansible tags to pass to ansible-playbook
#   -f, --env-file <file>     Path to env file (default: .env)
#   -h, --help                Show this help message
#
# Examples:
#   ./setup.sh                              # Use .env settings
#   ./setup.sh --env prod --yes             # Deploy prod non-interactively
#   ./setup.sh --all --skip-playbook        # Regenerate all inventories only
#   ./setup.sh --dry-run                    # See what would happen
#   ./setup.sh --env dev --tags k3s         # Run only k3s-tagged tasks
# =============================================================================

# --------------------------------------------------------------------------
# Defaults (all overridable by .env, then by CLI args)
# --------------------------------------------------------------------------
ARG_ENV=""
ARG_ALL=false
ARG_DRY_RUN=false
ARG_YES=false
ARG_SKIP_PLAYBOOK=false
ARG_SKIP_DEPS=false
ARG_TAGS=""
ARG_ENV_FILE=".env"

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
usage() {
    sed -n '/^# ====/,/^# ====/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--env)           ARG_ENV="$2";      shift 2 ;;
        -a|--all)           ARG_ALL=true;       shift   ;;
        -n|--dry-run)       ARG_DRY_RUN=true;  shift   ;;
        -y|--yes)           ARG_YES=true;       shift   ;;
        -s|--skip-playbook) ARG_SKIP_PLAYBOOK=true; shift ;;
        -d|--skip-deps)     ARG_SKIP_DEPS=true; shift  ;;
        -t|--tags)          ARG_TAGS="$2";     shift 2 ;;
        -f|--env-file)      ARG_ENV_FILE="$2"; shift 2 ;;
        -h|--help)          usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# --------------------------------------------------------------------------
# Dry-run wrapper: prints commands instead of executing them
# --------------------------------------------------------------------------
run() {
    if [ "${ARG_DRY_RUN}" == "true" ]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# --------------------------------------------------------------------------
# Load env file
# --------------------------------------------------------------------------
if [ ! -f "${ARG_ENV_FILE}" ]; then
    echo "Error: env file '${ARG_ENV_FILE}' not found."
    echo "  Copy example.env and configure: cp example.env .env"
    exit 1
fi
set -a
# shellcheck source=.env
source "${ARG_ENV_FILE}"
set +a

# CLI args override .env values
[ -n "${ARG_ENV}" ]               && ENVIRONMENT="${ARG_ENV}"
[ "${ARG_ALL}" == "true" ]        && SETUP_ALL_ENVIRONMENTS=true

# Apply defaults for any variables not set in .env
ENVIRONMENT="${ENVIRONMENT:-dev}"
SETUP_ALL_ENVIRONMENTS="${SETUP_ALL_ENVIRONMENTS:-false}"
RUN_PLAYBOOK="${RUN_PLAYBOOK:-true}"
ANSIBLE_INVENTORY_BASE_PATH="${ANSIBLE_INVENTORY_BASE_PATH:-inventory}"
ANSIBLE_INVENTORY_FILE="${ANSIBLE_INVENTORY_FILE:-hosts.ini}"

# Skip playbook flag (CLI arg takes precedence)
[ "${ARG_SKIP_PLAYBOOK}" == "true" ] && RUN_PLAYBOOK=false

# --------------------------------------------------------------------------
# Validate required config
# --------------------------------------------------------------------------
if [ -z "${K3S_USERNAME:-}" ]; then
    echo "Error: K3S_USERNAME is not set in ${ARG_ENV_FILE}"
    exit 1
fi

# --------------------------------------------------------------------------
# Helper: add section to inventory if absent
# --------------------------------------------------------------------------
add_section_if_not_exists() {
    local section="$1"
    local content="$2"
    local file="$3"

    if ! grep -qF "$section" "$file"; then
        if [ "${ARG_DRY_RUN}" == "true" ]; then
            echo "[DRY-RUN] Would add section '${section}' to ${file}"
        else
            echo -e "\n$content" >> "$file"
        fi
    fi
}

# --------------------------------------------------------------------------
# Helper: add hosts to an inventory section (idempotent)
# --------------------------------------------------------------------------
add_hosts_to_inventory() {
    local inventory_file=$1
    local section=$2
    local ips_list=$3
    local ips=(${ips_list//,/ })

    if ! grep -q "^\[${section}\]$" "${inventory_file}"; then
        if [ "${ARG_DRY_RUN}" == "true" ]; then
            echo "[DRY-RUN] Would add [${section}] to ${inventory_file}"
        else
            echo "[${section}]" >> "${inventory_file}"
        fi
    fi

    for ip in "${ips[@]}"; do
        ip=$(echo "$ip" | xargs)
        [ -z "$ip" ] && continue
        if ! sed -n "/^\[${section}\]$/,/^\[.*\]$/p" "${inventory_file}" | grep -q "^${ip}$"; then
            if [ "${ARG_DRY_RUN}" == "true" ]; then
                echo "[DRY-RUN] Would add ${ip} to [${section}] in $(basename "${inventory_file}")"
            else
                echo "  + ${ip} -> [${section}]"
                sed -i "/^\[${section}\]$/a ${ip}" "${inventory_file}"
            fi
        else
            echo "  = ${ip} already in [${section}] (no change)"
        fi
    done
}

# --------------------------------------------------------------------------
# Helper: run Ansible playbook for an environment
# --------------------------------------------------------------------------
run_playbook_for_env() {
    local env_name=$1
    local inventory_file=$2

    echo ""
    echo "Running playbook for ${env_name} using ${inventory_file}..."

    if [ "${env_name}" == "prod" ] && [ "${ARG_YES}" != "true" ]; then
        echo ""
        echo "  WARNING: You are targeting PRODUCTION!"
        read -rp "  Type 'yes' to confirm: " confirm
        if [ "$confirm" != "yes" ]; then
            echo "  Skipping production deployment."
            return 1
        fi
    fi

    local playbook_args=(-i "${inventory_file}" homelab.yml)
    [ -n "${ARG_TAGS}" ] && playbook_args+=(--tags "${ARG_TAGS}")

    if [ "${ARG_DRY_RUN}" == "true" ]; then
        echo "[DRY-RUN] ansible-playbook ${playbook_args[*]}"
        return 0
    fi

    ansible-playbook "${playbook_args[@]}"

    echo ""
    echo "Cluster status for ${env_name}:"
    kubectl get nodes --context="${env_name}" -o wide 2>/dev/null \
        || echo "  (kubectl context '${env_name}' not yet available)"
}

# --------------------------------------------------------------------------
# Core: process a single environment
# --------------------------------------------------------------------------
process_environment() {
    local env_name=$1
    local masters_var=$2
    local nodes_var=$3
    local enabled_var=$4

    echo ""
    echo "========================================="
    echo "Environment: ${env_name}"
    echo "========================================="

    local inv_path="${ANSIBLE_INVENTORY_BASE_PATH}/${env_name}"
    local inv_file="${inv_path}/${ANSIBLE_INVENTORY_FILE}"

    # Create inventory directory if needed (idempotent)
    if [ ! -d "${inv_path}" ]; then
        echo "  Creating directory: ${inv_path}"
        run mkdir -p "${inv_path}"
    fi

    # Create inventory file from template if needed (idempotent)
    if [ ! -f "${inv_file}" ]; then
        echo "  Creating inventory from template..."
        run cp inventory/example/hosts.ini "${inv_file}"
    else
        echo "  Inventory exists: ${inv_file}"
    fi

    # Ensure [local] section is present
    local local_section="[local]\nlocalhost ansible_connection=local ansible_user=${K3S_USERNAME}"
    add_section_if_not_exists "[local]" "${local_section}" "${inv_file}"

    # Add K3s hosts if enabled
    if [ "${enabled_var}" == "true" ]; then
        [ -n "${masters_var}" ] && add_hosts_to_inventory "${inv_file}" "master" "${masters_var}"
        [ -n "${nodes_var}" ]   && add_hosts_to_inventory "${inv_file}" "node"   "${nodes_var}"

        local cluster_section="[k3s_cluster:children]\nmaster\nnode"
        add_section_if_not_exists "[k3s_cluster:children]" "${cluster_section}" "${inv_file}"

        echo "  Inventory ready: ${inv_file}"

        if [ "${RUN_PLAYBOOK}" == "true" ]; then
            run_playbook_for_env "${env_name}" "${inv_file}"
        else
            echo "  Skipping playbook (--skip-playbook)"
        fi
    else
        echo "  K3s disabled for ${env_name} - inventory created, no hosts added"
    fi

    echo "  Done: ${env_name}"
}

# --------------------------------------------------------------------------
# Step 1: Python venv and dependencies (idempotent)
# --------------------------------------------------------------------------
if [ "${ARG_SKIP_DEPS}" != "true" ]; then
    echo ""
    echo "========================================="
    echo "Dependencies"
    echo "========================================="

    if [ "$(basename "$(pwd)")" != "${REPO_NAME:-MyHomeLab}" ] && [ -d "${REPO_NAME:-}/.git" ]; then
        echo "Entering repo directory: ${REPO_NAME}"
        cd "${REPO_NAME}"
    fi

    if [ ! -d "venv" ]; then
        echo "Creating Python virtual environment..."
        run python3 -m venv venv
    else
        echo "  venv exists (no change)"
    fi

    echo "Activating venv..."
    # shellcheck source=venv/bin/activate
    source venv/bin/activate

    echo "Installing Python requirements..."
    run pip install -q -r requirements.txt

    echo "Installing Ansible collections..."
    run ansible-galaxy collection install -r collections/requirements.yml --force-with-deps 2>/dev/null \
        || echo "  Collections already up to date"
fi

# --------------------------------------------------------------------------
# Step 2: Build inventories and optionally run playbooks
# --------------------------------------------------------------------------
echo ""
echo "========================================="
echo "Mode: $([ "${SETUP_ALL_ENVIRONMENTS}" == "true" ] && echo "ALL ENVIRONMENTS" || echo "SINGLE (${ENVIRONMENT})")"
[ "${ARG_DRY_RUN}"      == "true" ] && echo "  [DRY-RUN enabled]"
[ "${RUN_PLAYBOOK}"     != "true" ] && echo "  [Playbook skipped]"
[ -n "${ARG_TAGS}"                ] && echo "  [Tags: ${ARG_TAGS}]"
echo "========================================="

if [ "${SETUP_ALL_ENVIRONMENTS}" == "true" ]; then
    process_environment "dev"  "${K3S_MASTERS_DEV:-}"  "${K3S_NODES_DEV:-}"  "${K3S_ENABLED_DEV:-false}"
    process_environment "uat"  "${K3S_MASTERS_UAT:-}"  "${K3S_NODES_UAT:-}"  "${K3S_ENABLED_UAT:-false}"
    process_environment "prod" "${K3S_MASTERS_PROD:-}" "${K3S_NODES_PROD:-}" "${K3S_ENABLED_PROD:-false}"

    echo ""
    echo "All inventories updated."
    echo "To deploy a specific environment:"
    echo "  ./setup.sh --env dev"
    echo "  ./setup.sh --env prod --yes"

else
    case "${ENVIRONMENT}" in
        dev)
            process_environment "dev"  "${K3S_MASTERS_DEV:-}"  "${K3S_NODES_DEV:-}"  "${K3S_ENABLED_DEV:-false}"
            ;;
        uat)
            process_environment "uat"  "${K3S_MASTERS_UAT:-}"  "${K3S_NODES_UAT:-}"  "${K3S_ENABLED_UAT:-false}"
            ;;
        prod)
            process_environment "prod" "${K3S_MASTERS_PROD:-}" "${K3S_NODES_PROD:-}" "${K3S_ENABLED_PROD:-false}"
            ;;
        *)
            echo "Error: Unknown environment '${ENVIRONMENT}'. Must be dev, uat, or prod."
            exit 1
            ;;
    esac
fi

echo ""
echo "Setup complete!"
