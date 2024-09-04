#!/bin/bash

# This script deploys a server to Google Cloud Run.
# It handles versioning, updates package.json, and performs git operations before deployment.
# It also includes an auto-update feature.

# Author @VindicoRory

VERSION="2.0.0"
SCRIPT_NAME="$(basename "$0")"
REPO_URL="https://raw.githubusercontent.com/vindicoics/deployment_scripts/main/backend"

# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    echo -e "$1"
}

# Function to convert string to uppercase
to_uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Function to check for updates
check_for_updates() {
    log_message "${YELLOW}🔄 Checking for updates...${NC}"
    local tmp_file="/tmp/$SCRIPT_NAME"
    if curl -sSL "$REPO_URL/$SCRIPT_NAME" -o "$tmp_file"; then
        if [ -f "$tmp_file" ]; then
            remote_version=$(grep "^VERSION=" "$tmp_file" | cut -d'"' -f2)
            if [ "$VERSION" != "$remote_version" ]; then
                log_message "${GREEN}✅ Update available: $remote_version${NC}"
                read -p "Do you want to update? (y/n): " update_confirm
                if [[ $update_confirm == [Yy] ]]; then
                    mv "$tmp_file" "$0"
                    chmod +x "$0"
                    log_message "${GREEN}✅ Script updated. Please run the command again.${NC}"
                    exit 0
                else
                    log_message "${YELLOW}⚠️ Update skipped.${NC}"
                fi
            else
                log_message "${GREEN}✅ Script is up to date.${NC}"
            fi
        fi
    else
        log_message "${RED}❌ Failed to check for updates.${NC}"
    fi
}

# Function to update version
update_version() {
    echo "Select version update type:"
    echo "1) Major"
    echo "2) Minor"
    echo "3) Patch"
    echo "4) Manual"
    read -p "Enter your choice (1-4): " version_choice

    case $version_choice in
        1) npm version major ;;
        2) npm version minor ;;
        3) npm version patch ;;
        4)
            read -p "Enter the new version number: " new_version
            npm version $new_version --no-git-tag-version
            ;;
        *)
            log_message "${RED}Invalid choice. Skipping version update.${NC}"
            return
            ;;
    esac

    log_message "${GREEN}✅ package.json updated${NC}"
}

# Function to commit and push changes
commit_and_push() {
    git add package.json
    git commit -m "Update version for deployment"
    git push origin HEAD

    if [ $? -eq 0 ]; then
        log_message "${GREEN}✅ Changes committed and pushed successfully${NC}"
    else
        log_message "${RED}❌ Failed to commit and push changes${NC}"
        exit 1
    fi
}

# Function to display script usage
usage() {
    echo "Usage: $0 -e <environment> -p <project-id> -n <deployment-name> [OPTIONS]"
    echo
    echo "Required:"
    echo "  -e    Environment (e.g., staging, production)"
    echo "  -p    Google Cloud Project ID"
    echo "  -n    Name of your Cloud Run service"
    echo
    echo "Options:"
    echo "  -r    Deployment region (default: europe-west1)"
    echo "  -s    Source path (default: current directory)"
    echo "  -l    Secret label (default: env=<environment>)"
    echo "  -k    Service key name"
    echo "  -y    Skip deployment confirmation"
    echo "  -u    Check for updates"
    echo "  -h    Display this help message"
    exit 1
}

# Function to fetch secrets based on label and generate secret flags
fetch_secrets() {
    local secret_flags=""
    local secrets=$(gcloud secrets list --filter="labels.$SECRET_LABEL" --format="value(name)")

    if [ -z "$secrets" ]; then
        log_message "${YELLOW}⚠️ No secrets found with label $SECRET_LABEL${NC}"
        return
    fi

    local env_prefix=$(to_uppercase "${ENVIRONMENT}")
    for secret in $secrets; do
        # Remove the environment prefix and underscore
        local secret_name=$(echo "$secret" | sed "s/^${env_prefix}_//")
        secret_flags+="--set-secrets=${secret_name}=${secret}:latest "
    done
    echo $secret_flags
}

# Function to comment out specific lines in .gitignore
comment_out_gitignore_entries() {
    local gitignore_file=".gitignore"

    # Check if the .gitignore file exists
    if [ ! -f "$gitignore_file" ]; then
        log_message "${RED}❌ Error: .gitignore file not found.${NC}"
        exit 1
    fi

    # Lines to be commented out
    local lines_to_comment=(".npmrc" "$SERVICE_KEY_NAME")

    for line in "${lines_to_comment[@]}"; do
        # Comment out the line if it's not already commented
        sed -i '' "/^$line/ s/^/#/" $gitignore_file
    done

    log_message "${GREEN}✅ .gitignore entries commented out.${NC}"
}

# Function to uncomment specific lines in .gitignore
uncomment_gitignore_entries() {
    local gitignore_file=".gitignore"

    # Check if the .gitignore file exists
    if [ ! -f "$gitignore_file" ]; then
        log_message "${RED}❌ Error: .gitignore file not found.${NC}"
        exit 1
    fi

    # Lines to be uncommented
    local lines_to_uncomment=(".npmrc" "$SERVICE_KEY_NAME")

    for line in "${lines_to_uncomment[@]}"; do
        # Uncomment the line if it's commented
        sed -i '' "/^#$line/ s/^#//" $gitignore_file
    done

    log_message "${GREEN}✅ .gitignore entries uncommented.${NC}"
}

# Function to update the Dockerfile with the correct environment setting
update_dockerfile_env() {
    local dockerfile_path="./Dockerfile"

    # Check if the Dockerfile exists
    if [ ! -f "$dockerfile_path" ]; then
        log_message "${RED}❌ Error: Dockerfile not found.${NC}"
        exit 1
    fi

    # macOS compatible sed command to replace the --env setting in the Dockerfile
    sed -i '' "s/--env=[a-z]*/--env=$ENVIRONMENT/g" "$dockerfile_path"

    if [ $? -eq 0 ]; then
        log_message "${GREEN}✅ Dockerfile updated to use --env=$ENVIRONMENT${NC}"
    else
        log_message "${RED}❌ Failed to update Dockerfile.${NC}"
    fi
}

# Default values
DEPLOYMENT_REGION="europe-west1"
SOURCE_PATH="."
SKIP_CONFIRMATION=false
CHECK_UPDATES=false

# Parse command line arguments
while getopts "e:p:n:r:s:l:k:yuh" opt; do
  case $opt in
    e) ENVIRONMENT="$OPTARG" ;;
    p) PROJECT_ID="$OPTARG" ;;
    n) DEPLOYMENT_NAME="$OPTARG" ;;
    r) DEPLOYMENT_REGION="$OPTARG" ;;
    s) SOURCE_PATH="$OPTARG" ;;
    l) SECRET_LABEL="$OPTARG" ;;
    k) SERVICE_KEY_NAME="$OPTARG" ;;
    y) SKIP_CONFIRMATION=true ;;
    u) CHECK_UPDATES=true ;;
    h) usage ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage ;;
  esac
done

# Check for updates if flag is set
if [ "$CHECK_UPDATES" = true ]; then
    check_for_updates
    exit 0
fi

# Check for required arguments
if [ -z "$ENVIRONMENT" ] || [ -z "$PROJECT_ID" ] || [ -z "$DEPLOYMENT_NAME" ]; then
    echo "Error: Missing required arguments"
    usage
fi

# Set default SECRET_LABEL if not provided
SECRET_LABEL=${SECRET_LABEL:-"env=$ENVIRONMENT"}

# --- Main Script Execution ---

echo -e "${YELLOW}🚀 Starting Deployment Process... ${RED}($ENVIRONMENT) ${NC}"

# Version update and git operations
update_version
commit_and_push

# Confirmation before Deployment
if [ "$SKIP_CONFIRMATION" = false ]; then
    read -p "🤔 Are you sure you want to deploy '$DEPLOYMENT_NAME' to '$PROJECT_ID'? (y/n): " confirmation
    if [[ $confirmation != [Yy] ]]; then
        log_message "${YELLOW}🛑 Deployment cancelled by user.${NC}"
        exit 0
    fi
fi

# Update the Dockerfile with the correct environment
update_dockerfile_env

# Call the function to comment out .gitignore entries
comment_out_gitignore_entries

# Setting Project to the specified ID
log_message "🔨 Setting Project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# Verify Project Setting
currentProjectID=$(gcloud config get-value project)
if [ "$currentProjectID" != "$PROJECT_ID" ]; then
    log_message "${RED}❌ Error: Project ID mismatch. Expected: ${PROJECT_ID}, Found: ${currentProjectID}.${NC}"
    exit 1
fi
log_message "${GREEN}✅ Project ID verified: $currentProjectID${NC}"

# Fetch secrets and get secret flags
SECRET_FLAGS=$(fetch_secrets)

# Print out the secret flags (for debugging, remove in production)
log_message "${YELLOW}🔒 Secret Flags: $SECRET_FLAGS${NC}"

# Deployment
log_message "${YELLOW}🚢 Deploying $DEPLOYMENT_NAME to Cloud Run...${NC}"
gcloud run deploy $DEPLOYMENT_NAME \
  --source $SOURCE_PATH \
  --platform managed \
  --region $DEPLOYMENT_REGION \
  --allow-unauthenticated \
  $(echo $SECRET_FLAGS)

# Check the result of the deployment
if [ $? -eq 0 ]; then
    log_message "${GREEN}✅ Deployment of $DEPLOYMENT_NAME Successful!${NC}"
else
    log_message "${RED}❌ Deployment of $DEPLOYMENT_NAME Failed.${NC}"
fi

# Uncomment lines after the deployment process has finished
uncomment_gitignore_entries

# Remove service_key and .npmrc files from git cache
if [ -n "$SERVICE_KEY_NAME" ]; then
    git rm --cached $SERVICE_KEY_NAME .npmrc >> /dev/null 2>&1
fi

# --- Script End ---
