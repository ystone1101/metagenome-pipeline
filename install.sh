#!/bin/bash
# Dokkaebi Pipeline Automatic Installer (Final Version)
set -euo pipefail

log_info() {
    echo -e "\033[0;32m[INSTALLER] $(date +'%Y-%m-%d %H:%M:%S') | $1\033[0m"
}

# Conda 명령어 확인
if ! command -v conda &> /dev/null; then
    echo -e "\033[0;31mError: conda is not installed or not in your PATH. Please install Miniconda/Anaconda first.\033[0m"
    exit 1
fi

YML_FILES=(
    "environments/kneaddata_env.yml"
    "environments/fastp_env.yml"
    "environments/kraken_env.yml"
    "environments/bbmap_env.yml"
    "environments/megahit_env.yml"
    "environments/metawrap_env.yml"
    "environments/gtdbtk_env.yml"
    "environments/bakta_env.yml"
)

log_info "Starting Dokkaebi Pipeline environment setup..."

for yml in "${YML_FILES[@]}"; do
    if [ ! -f "$yml" ]; then
        log_info "Warning: $yml not found. Skipping."
        continue
    fi
    
    ENV_NAME=$(head -n 1 "$yml" | cut -d' ' -f2)
    log_info "--------------------------------------------------"
    log_info "Processing environment: $ENV_NAME"
    log_info "from file: $yml"
    log_info "--------------------------------------------------"
    
    if conda info --envs | grep -q "^${ENV_NAME}[[:space:]]"; then
        log_info "Environment '$ENV_NAME' already exists. Updating..."
        conda env update --name "$ENV_NAME" --file "$yml" --prune
    else
        log_info "Creating new environment: '$ENV_NAME'..."
        conda env create --file "$yml"
    fi
    
    if [ $? -eq 0 ]; then
        log_info "Successfully created/updated environment: $ENV_NAME"
    else
        echo -e "\033[0;31mError: Failed to create/update environment: $ENV_NAME. Please check the logs.\033[0m"
        exit 1
    fi
done

log_info "All Conda environments are set up successfully!"
log_info "You can now run the Dokkaebi pipeline."
