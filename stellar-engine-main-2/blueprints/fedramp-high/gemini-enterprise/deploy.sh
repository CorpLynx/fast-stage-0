#!/bin/bash
set -e

# Ensure gem4gov can be found in the python path
export PYTHONPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gem4gov-cli:$PYTHONPATH"

# --- Global Configuration ---
# These variables are used across multiple functions
PROJECT_ID=""
ORG_ID=""
PREFIX=""
REGION=""
DOMAIN=""
DEPLOYMENT_CHOICE=""
IS_BROWNFIELD="false"
IS_CUSTOM="false"
BUCKET_NAME=""
STATE_BUCKET=""
TENANT_IAC_PROJECT=""
DEFAULT_CMEK_KEY=""
KMS_KEY_ID=""
SKIP_PROMPTS="false"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---

get_tfvar_value() {
    local file="$1"
    local key="$2"
    if [[ -f "$file" ]]; then
        grep "^${key}\s*=" "$file" | head -n 1 | cut -d'=' -f2- | tr -d ' "'
    fi
}

print_header() {
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}   Gemini Enterprise FedRAMP High Blueprint Manager         ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
}

pause() {
    echo ""
    read -p "Press Enter to continue..."
}

normalize_environment() {
    # Capitalize first letter of Environment (e.g. prod -> Prod)
    if [[ -n "$ENVIRONMENT" ]]; then
        CAP_ENV=$(echo "$ENVIRONMENT" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    fi
}

check_dependencies() {
    local missing=0
    for cmd in gcloud terraform pip3 python3 jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: Required command '$cmd' not found.${NC}"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        echo "Please install missing dependencies and try again."
        exit 1
    fi
}

configure_data_stores() {
    # Expects GCS_LIST and BQ_LIST to be defined arrays in the calling scope
    while true; do
        echo ""
        echo -e "${BLUE}--- Data Store Configuration ---${NC}"
        echo "1. Add Google Cloud Storage (GCS) Data Store"
        echo "2. Add BigQuery (BQ) Data Store"
        echo "3. Done"
        read -p "Select an option [1-3]: " DS_MENU_SEL
        
        case $DS_MENU_SEL in
            1)
                read -p "Enter Bucket Name (e.g., company-docs): " GCS_NAME
                if [[ -n "$GCS_NAME" ]]; then
                    GCS_LIST+=("\"$GCS_NAME\"")
                    echo -e "${GREEN}Added GCS Bucket: ${GCS_NAME}${NC}"
                else
                    echo -e "${RED}Invalid Bucket Name.${NC}"
                fi
                ;;
            2)
                read -p "Enter Dataset ID (must contain only letters (a-z, A-Z), numbers (0-9), or underscores (_)): " BQ_DATASET
                read -p "Enter Table ID: " BQ_TABLE
                if [[ -n "$BQ_DATASET" && -n "$BQ_TABLE" ]]; then
                    BQ_LIST+=("{dataset_id = \"$BQ_DATASET\", table_id = \"$BQ_TABLE\"}")
                    echo -e "${GREEN}Added BigQuery Table: ${BQ_DATASET}.${BQ_TABLE}${NC}"
                else
                    echo -e "${RED}Invalid Dataset or Table ID.${NC}"
                fi
                ;;
            3)
                break
                ;;
            *)
                echo "Invalid option."
                ;;
        esac
    done
}

# --- Authentication & Setup ---

auth_and_project_setup() {
    echo -e "${BLUE}--- Authentication & Project Selection ---${NC}"
    
    # 1. Google Account Check
    CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
    echo -e "Current Google Account: ${YELLOW}${CURRENT_ACCOUNT}${NC}"
    read -p "Is this the correct account? (y/N): " CONFIRM_ACCOUNT
    if [[ "$CONFIRM_ACCOUNT" != "y" && "$CONFIRM_ACCOUNT" != "Y" ]]; then
        echo "Starting authentication flow..."
        gcloud auth login
        CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
        echo -e "Now authenticated as: ${YELLOW}${CURRENT_ACCOUNT}${NC}"
    fi

    # 2. ADC Check
    echo "Checking Application Default Credentials (ADC)..."
    if gcloud auth application-default print-access-token &>/dev/null; then
        echo -e "${GREEN}ADC is configured.${NC}"
    else
        echo -e "${YELLOW}Application Default Credentials not found.${NC}"
        read -p "Do you want to authenticate ADC now? (y/N): " DO_AUTH
        if [[ "$DO_AUTH" == "y" || "$DO_AUTH" == "Y" ]]; then
            gcloud auth application-default login
        else
            echo "Warning: Proceeding without ADC. Terraform might fail."
        fi
    fi

    # 3. Project ID Selection
    CURRENT_PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -n "$CURRENT_PROJECT_ID" ]]; then
        echo -e "Current Project ID: ${YELLOW}${CURRENT_PROJECT_ID}${NC}"
        read -p "Is this the correct Project ID for Gemini Enterprise? (y/N): " CONFIRM_PROJECT
        if [[ "$CONFIRM_PROJECT" == "y" || "$CONFIRM_PROJECT" == "Y" ]]; then
            PROJECT_ID=$CURRENT_PROJECT_ID
        else
            read -p "Enter the Google Cloud Project ID: " PROJECT_ID
            if [[ -n "$PROJECT_ID" ]]; then
                gcloud config set project "${PROJECT_ID}"
            fi
        fi
    fi

    if [[ -z "$PROJECT_ID" ]]; then
        read -p "Enter the Google Cloud Project ID: " PROJECT_ID
        if [[ -n "$PROJECT_ID" ]]; then
            gcloud config set project "${PROJECT_ID}"
        fi
    fi

    if [[ -z "$PROJECT_ID" ]]; then
        echo -e "${RED}Project ID is required.${NC}"
        return 1
    fi

    # Set billing quota project
    echo "Setting billing quota project..."
    gcloud config set billing/quota_project "${PROJECT_ID}"
    echo "Setting application default quota project..."
    gcloud auth application-default set-quota-project "${PROJECT_ID}"

    # Discover Org ID
    echo "Discovering Organization ID..."
    ORG_ID=$(gcloud projects get-ancestors "${PROJECT_ID}" --format="value(id)" | tail -n 1)
    echo -e "Found Organization ID: ${YELLOW}${ORG_ID}${NC}"

    # Discover Domain
    echo "Discovering Organization Domain..."
    ORG_DOMAIN=$(gcloud organizations list --filter="name:organizations/${ORG_ID}" --format="value(displayName)" 2>/dev/null)
    if [[ -n "$ORG_DOMAIN" ]]; then
        DOMAIN="${ORG_DOMAIN}"
        echo -e "Found Organization Domain: ${YELLOW}${DOMAIN}${NC}"
    else
        echo -e "${YELLOW}Warning: Could not auto-discover Organization Domain.${NC}"
    fi
    
    return 0
}

enable_apis() {
    echo ""
    echo -e "${BLUE}--- Enabling Required APIs ---${NC}"
    echo "Enabling: Assured Workloads, Access Context Manager, Org Policy, KMS, Storage, IAM, Service Usage..."
    if ! gcloud services enable \
        assuredworkloads.googleapis.com \
        accesscontextmanager.googleapis.com \
        compute.googleapis.com \
        orgpolicy.googleapis.com \
        cloudkms.googleapis.com \
        storage.googleapis.com \
        iam.googleapis.com \
        cloudresourcemanager.googleapis.com \
        serviceusage.googleapis.com \
        --project "${PROJECT_ID}"; then
        echo -e "${RED}Error: Failed to enable required APIs. Check your permissions.${NC}"
        return 1
    fi
    echo -e "${GREEN}APIs enabled successfully.${NC}"
    return 0
}

# --- Deployment Configuration ---

select_deployment_type() {
    echo ""
    echo -e "${BLUE}--- Deployment Topology Selection ---${NC}"
    echo "1. Greenfield (New GCP Project Deployment)"
    echo "2. Brownfield (Stellar Engine Integration)"
    echo "3. Custom Brownfield (Manual Configuration)"
    read -p "Select an option [1-3]: " DEPLOYMENT_CHOICE

    if [[ ! "$DEPLOYMENT_CHOICE" =~ ^[1-3]$ ]]; then
        echo -e "${RED}Invalid selection.${NC}"
        return 1
    fi

    if [[ "$DEPLOYMENT_CHOICE" == "1" ]]; then # Greenfield
        DEPLOYMENT_TYPE_TEXT="Greenfield (New GCP Project Deployment)"
        IS_BROWNFIELD="false"
        IS_CUSTOM="false"
    elif [[ "$DEPLOYMENT_CHOICE" == "2" ]]; then # Brownfield
        DEPLOYMENT_TYPE_TEXT="Brownfield (Stellar Engine Integration)"
        IS_BROWNFIELD="true"
        IS_CUSTOM="false"
    elif [[ "$DEPLOYMENT_CHOICE" == "3" ]]; then # Custom Brownfield
        DEPLOYMENT_TYPE_TEXT="Custom Brownfield (Manual Configuration)"
        IS_BROWNFIELD="false"
        IS_CUSTOM="true"
    fi
    
    return 0
}

discover_infrastructure() {
    # Initialize variables
    ENVIRONMENT=""
    TENANT="g4g"
    TENANT_IAC_PROJECT=""
    CMEK_PROJECT_ID=""
    CMEK_US_KEYRING=""
    CMEK_STATE_KEY=""
    CMEK_US_RESOURCES_KEY=""

    echo ""
    echo -e "${BLUE}--- Infrastructure Discovery ---${NC}"

    # 0. Prefix Discovery
    if [[ "$IS_BROWNFIELD" == "true" ]]; then
        PREFIX=$(echo "$PROJECT_ID" | cut -d'-' -f1 | cut -d'-' -f1-6)
        echo -e "Derived Prefix: ${YELLOW}${PREFIX}${NC}"
    elif [[ "$IS_CUSTOM" == "true" ]]; then
        read -p "Enter a prefix for your resources (<= 6 characters): " INPUT_PREFIX
        PREFIX=${INPUT_PREFIX:-"sedev"}
    else 
        # Greenfield
        read -p "Enter a prefix for your resources (<= 6 characters): " PREFIX
    fi

    if [[ "$IS_BROWNFIELD" == "true" ]]; then
        # 1. Extract Environment and Tenant
        # Format: prefix-env-tenant-main-0
        ENVIRONMENT=$(echo "$PROJECT_ID" | cut -d'-' -f2)
        TENANT_VAL=$(echo "$PROJECT_ID" | cut -d'-' -f3)
        
        # Validate extraction (basic check)
        if [[ -z "$ENVIRONMENT" || -z "$TENANT_VAL" ]]; then
             echo -e "${RED}Error: Could not derive Environment or Tenant from Project ID.${NC}"
             echo -e "${YELLOW}Standard Pattern: prefix-env-tenant-main-0${NC}"
             read -p "Switch to Custom Brownfield? (y/n): " SWITCH
             if [[ "$SWITCH" == "y" || "$SWITCH" == "Y" ]]; then
                 IS_BROWNFIELD="false"
                 IS_CUSTOM="true"
                 discover_infrastructure
                 return
             else
                 return 1
             fi
        fi
        
        # If tenant was extracted, use it (though default is g4g, usually it matches)
        if [[ -n "$TENANT_VAL" ]]; then
            TENANT="$TENANT_VAL"
        fi
        
        normalize_environment
        
        # 2. Check Tenant IaC Project
        POTENTIAL_IAC_PROJECT="${PREFIX}-${ENVIRONMENT}-${TENANT}-iac-core-0"
        echo "Checking for Tenant IaC Project: ${POTENTIAL_IAC_PROJECT}..."
        
        if gcloud projects describe "${POTENTIAL_IAC_PROJECT}" &>/dev/null; then
            TENANT_IAC_PROJECT="${POTENTIAL_IAC_PROJECT}"
            echo -e "Found Tenant IaC Project: ${GREEN}${TENANT_IAC_PROJECT}${NC}"
        else
            echo -e "${YELLOW}Tenant IaC Project not found.${NC}"
            echo -e "${YELLOW}Standard Stellar Engine Landing Zone framework not detected.${NC}"
            read -p "Switch to Custom Brownfield? (y/n): " SWITCH
             if [[ "$SWITCH" == "y" || "$SWITCH" == "Y" ]]; then
                 IS_BROWNFIELD="false"
                 IS_CUSTOM="true"
                 discover_infrastructure
                 return
             else
                 return 1
             fi
        fi

        # 3. Check State Bucket
        POTENTIAL_BUCKET="${PREFIX}-${ENVIRONMENT}-${TENANT}-iac-0"
        echo "Checking for Terraform State Bucket: ${POTENTIAL_BUCKET}..."
        if gcloud storage buckets describe "gs://${POTENTIAL_BUCKET}" &>/dev/null; then
            STATE_BUCKET="${POTENTIAL_BUCKET}"
            echo -e "Found Terraform State Bucket: ${GREEN}${STATE_BUCKET}${NC}"
        else
             echo -e "${YELLOW}Terraform State Bucket not found (Will be created).${NC}"
             STATE_BUCKET=""
        fi

        # 4. Check Keyrings and Keys
        # Prioritize US Multi-Region for CMEK_US_KEYRING
        echo "Searching for CMEK Keyring in the US multi-region..."
        
        CMEK_PROJECT_ID="${TENANT_IAC_PROJECT}"
        # Capitalize first letter of Environment for KeyRing name (e.g. prod -> Prod)
        US_KEYRING_NAME="${CAP_ENV}-${TENANT}-keyring"
        US_KEYRING_ID="projects/${CMEK_PROJECT_ID}/locations/us/keyRings/${US_KEYRING_NAME}"
        
        # Check US Keyring
        if gcloud kms keyrings describe "${US_KEYRING_ID}" &>/dev/null; then
            echo -e "Found US Keyring: ${GREEN}${US_KEYRING_NAME}${NC}"
            CMEK_US_KEYRING="${US_KEYRING_ID}"
            
            # Check 'gcs' key in US Keyring
            GCS_KEY_ID="${CMEK_US_KEYRING}/cryptoKeys/gcs"
            if gcloud kms keys describe "${GCS_KEY_ID}" &>/dev/null; then
                 echo -e "Found US GCS Crypto Key: ${GREEN}gcs${NC}"
                 CMEK_STATE_KEY="${GCS_KEY_ID}"
            fi
            
            # Check 'gemini-enterprise' key in US Keyring
            GEMINI_KEY_ID="${CMEK_US_KEYRING}/cryptoKeys/gemini-enterprise"
            if gcloud kms keys describe "${GEMINI_KEY_ID}" &>/dev/null; then
                 echo -e "Found US Gemini Enterprise Crypto Key: ${GREEN}gemini-enterprise${NC}"
                 CMEK_US_RESOURCES_KEY="${GEMINI_KEY_ID}"
            fi
        else
            echo -e "${YELLOW}US Keyring not found.${NC}"
            CMEK_US_KEYRING=""
        fi

        # 5. Fallback for State Key (Regional) if US GCS Key not found
        if [[ -z "$CMEK_STATE_KEY" ]]; then
             # If state bucket exists, check what key protects it
             if [[ -n "$STATE_BUCKET" ]]; then
                  echo "Checking Terraform State Bucket encryption..."
                  BUCKET_JSON=$(gcloud storage buckets describe "gs://${STATE_BUCKET}" --format="json" 2>/dev/null || echo "{}")
                  BUCKET_KEY=$(echo "$BUCKET_JSON" | jq -r '.default_kms_key // .default_kms_key_name // .encryption.defaultKmsKeyName // empty')
                  if [[ -n "$BUCKET_KEY" ]]; then
                       CMEK_STATE_KEY="${BUCKET_KEY}"
                       echo -e "Using Existing Terraform State Bucket Crypto Key: ${YELLOW}${CMEK_STATE_KEY}${NC}"
                  fi
             fi
             
             # If still no key, check regional keyring
              if [[ -z "$CMEK_STATE_KEY" ]]; then
                   REGIONAL_KEYRING_ID="projects/${CMEK_PROJECT_ID}/locations/${REGION}/keyRings/${CAP_ENV}-${TENANT}-keyring"
                  echo "Checking Regional Keyring: ${REGIONAL_KEYRING_ID}..."
                  if gcloud kms keyrings describe "${REGIONAL_KEYRING_ID}" &>/dev/null; then
                        REGIONAL_GCS_KEY="${REGIONAL_KEYRING_ID}/cryptoKeys/gcs"
                        if gcloud kms keys describe "${REGIONAL_GCS_KEY}" &>/dev/null; then
                             CMEK_STATE_KEY="${REGIONAL_GCS_KEY}"
                             echo -e "Found Regional GCS Crypto Key: ${YELLOW}${CMEK_STATE_KEY}${NC}"
                        fi
                  fi
             fi
        fi

        # Ensure correct outputs
        echo -e "Environment: ${YELLOW}${ENVIRONMENT}${NC}"
        echo -e "Tenant: ${YELLOW}${TENANT}${NC}"

    elif [[ "$IS_CUSTOM" == "true" ]]; then
        read -p "Enter Environment identifier (e.g., prod): " ENVIRONMENT
        normalize_environment
        read -p "Enter Tenant IaC Project ID: " TENANT_IAC_PROJECT
        
        # State Bucket
        read -p "Enter Terraform State Bucket Name (leave blank to create): " STATE_BUCKET
        if [[ -n "$STATE_BUCKET" ]]; then
             # Validate Encryption
             BUCKET_JSON=$(gcloud storage buckets describe "gs://${STATE_BUCKET}" --format="json" 2>/dev/null || echo "{}")
             BUCKET_KEY=$(echo "$BUCKET_JSON" | jq -r '.default_kms_key // .default_kms_key_name // .encryption.defaultKmsKeyName // empty')
             if [[ -z "$BUCKET_KEY" ]]; then
                  echo -e "${RED}WARNING: State Bucket '${STATE_BUCKET}' is NOT encrypted with CMEK.${NC}"
                  echo -e "Compliance requires CMEK. A new bucket will be created."
                  STATE_BUCKET=""
                  CMEK_STATE_KEY=""
             else
                  CMEK_STATE_KEY="${BUCKET_KEY}"
                  echo -e "Using Existing Terraform State Bucket Crypto Key: ${YELLOW}${CMEK_STATE_KEY}${NC}"
             fi
        fi
        
        read -p "Enter CMEK Project ID: " CMEK_PROJECT_ID
        read -p "Enter US Multi-Region Keyring ID (optional): " CMEK_US_KEYRING
        read -p "Enter US Gemini Resources Key ID (optional): " CMEK_US_RESOURCES_KEY

    else 
        # Greenfield
        # Greenfield (No Landing Zone)
        read -p "Enter Environment identifier (e.g., prod): " ENVIRONMENT
        normalize_environment
        TENANT_IAC_PROJECT=""
        STATE_BUCKET="${PREFIX}-${ENVIRONMENT}-${TENANT}-tfstate-0"
        CMEK_PROJECT_ID="${PROJECT_ID}"
        CMEK_STATE_KEY=""
        CMEK_US_KEYRING=""
        CMEK_US_RESOURCES_KEY=""
    fi
    return 0
}

ensure_prerequisites() {
    echo ""
    echo -e "${BLUE}--- Ensuring Prerequisites ---${NC}"
    
    # Defaults
    ENVIRONMENT=${ENVIRONMENT:-"prod"}
    normalize_environment
    
    # 1. State Key Creation (if missing)
    if [[ -z "$CMEK_STATE_KEY" ]]; then
        echo -e "${YELLOW}Searching for CMEK State Key in the US multi-region...${NC}"
        
        KEYRING_NAME="${CAP_ENV}-${TENANT}-keyring"
        KEY_NAME="gcs"
        LOCATION="us"
        
        # Identify Target Project
        TARGET_KMS_PROJECT="${CMEK_PROJECT_ID}"
        
        # Create Keyring if not exists
        if ! gcloud kms keyrings describe "${KEYRING_NAME}" --location="${LOCATION}" --project="${TARGET_KMS_PROJECT}" &>/dev/null; then
             echo "Creating Keyring '${KEYRING_NAME}' in ${LOCATION}..."
             gcloud kms keyrings create "${KEYRING_NAME}" --location="${LOCATION}" --project="${TARGET_KMS_PROJECT}"
        fi
        
        CMEK_US_KEYRING="projects/${TARGET_KMS_PROJECT}/locations/${LOCATION}/keyRings/${KEYRING_NAME}"
        
        # Create Key if not exists
        FULL_KEY_NAME="${CMEK_US_KEYRING}/cryptoKeys/${KEY_NAME}"
        if ! gcloud kms keys describe "${FULL_KEY_NAME}" &>/dev/null; then
             echo "Creating Key '${KEY_NAME}'..."
             gcloud kms keys create "${KEY_NAME}" \
                 --keyring="${KEYRING_NAME}" \
                 --location="${LOCATION}" \
                 --project="${TARGET_KMS_PROJECT}" \
                 --purpose="encryption" \
                 --protection-level="hsm" \
                 --rotation-period="7776000s" \
                 --next-rotation-time="$(date -v+90d -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+90 days' +%Y-%m-%dT%H:%M:%SZ)"
        fi
        
        CMEK_STATE_KEY="${FULL_KEY_NAME}"
        echo -e "Using CMEK State Key: ${GREEN}${CMEK_STATE_KEY}${NC}"
        
        # Grant Permissions
        echo -e "${YELLOW}Granting permissions on CMEK State Key...${NC}"
        CURRENT_USER=$(gcloud config get-value account 2>/dev/null)
        
        # User
        gcloud kms keys add-iam-policy-binding "${CMEK_STATE_KEY}" \
            --member="user:${CURRENT_USER}" \
            --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" --quiet
            
        # Storage Service Account (for the project where the bucket will live)
        # Verify if TENANT_IAC_PROJECT is set, use that, else use PROJECT_ID
        BUCKET_PROJECT="${TENANT_IAC_PROJECT}"
        if [[ -z "$BUCKET_PROJECT" ]]; then
             BUCKET_PROJECT="${PROJECT_ID}"
        fi
        
        BUCKET_PROJECT_NUMBER=$(gcloud projects describe "${BUCKET_PROJECT}" --format="value(projectNumber)")
        STORAGE_SA="service-${BUCKET_PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
               if gcloud kms keys add-iam-policy-binding "${CMEK_STATE_KEY}" \
             --member="serviceAccount:${STORAGE_SA}" \
             --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" --quiet &>/dev/null; then
             echo -e "${GREEN}Granted Storage SA (${STORAGE_SA}) access to CMEK State Key.${NC}"
        else
             echo -e "${YELLOW}Warning: Could not grant Storage SA access. Check permissions.${NC}"
        fi
    fi
    
    # 2. State Bucket Creation (Greenfield only)
    echo -e "${YELLOW}Searching for Terraform State Bucket...${NC}"
    if [[ "$IS_BROWNFIELD" == "false" && "$IS_CUSTOM" == "false" ]]; then
         # Ensure BUCKET_NAME is set from STATE_BUCKET if not already
        if [[ -z "$BUCKET_NAME" && -n "$STATE_BUCKET" ]]; then
            BUCKET_NAME=$(echo "$STATE_BUCKET" | sed 's/gs:\/\/ //' | sed 's/\/$//')
        fi
        
        # Use CMEK_STATE_KEY if available (derived above)
        KMS_KEY_ID="${CMEK_STATE_KEY}"

        if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" &>/dev/null; then
            echo "Creating state bucket gs://${BUCKET_NAME}..."
            
            # Grant Storage Service Agent access to CMEK if used (Double Check / Re-grant just in case)
            if [[ -n "$KMS_KEY_ID" ]]; then
                PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
                STORAGE_SA="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
                
                echo "Ensuring Storage Service Agent (${STORAGE_SA}) has access to ${KMS_KEY_ID}..."
                gcloud kms keys add-iam-policy-binding "${KMS_KEY_ID}" \
                    --member="serviceAccount:${STORAGE_SA}" \
                    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
                    --project="${CMEK_PROJECT_ID}" &>/dev/null || echo "Warning: Failed to grant IAM binding on key."
                
                gcloud storage buckets create "gs://${BUCKET_NAME}" --project "${PROJECT_ID}" --location "us" --uniform-bucket-level-access --default-encryption-key="${KMS_KEY_ID}"
            else
                gcloud storage buckets create "gs://${BUCKET_NAME}" --project "${PROJECT_ID}" --location "us" --uniform-bucket-level-access
            fi
        else
            echo -e "Using Terraform State Bucket: ${GREEN}${BUCKET_NAME}${NC}"
        fi
    fi

    # 2. State Bucket Creation (if missing)
    if [[ -z "$STATE_BUCKET" ]]; then
        echo -e "${YELLOW}Terraform State Bucket not found. Creating...${NC}"
        
        if [[ -n "$TENANT_IAC_PROJECT" ]]; then
             BUCKET_PROJECT="${TENANT_IAC_PROJECT}"
        else
             BUCKET_PROJECT="${PROJECT_ID}"
        fi
        
        # Construct Name
        NEW_BUCKET_NAME="${PREFIX}-${ENVIRONMENT}-${TENANT}-iac-0"
        
        echo "Creating Bucket '${NEW_BUCKET_NAME}' in ${REGION}..."
        # Note: If REGION != 'us' and Key is 'us', this might fail if not dual-region. 
        # Attempting creation.
        if ! gcloud storage buckets create "gs://${NEW_BUCKET_NAME}" \
            --project="${BUCKET_PROJECT}" \
            --location="${REGION}" \
            --default-encryption-key="${CMEK_STATE_KEY}" \
            --uniform-bucket-level-access; then
            
            echo -e "${RED}Failed to create bucket. Retrying with 'US' location if Key is US...${NC}"
            # Fallback logic if region mismatch suspected
             if [[ "$CMEK_STATE_KEY" == *"/locations/us/"* ]]; then
                  gcloud storage buckets create "gs://${NEW_BUCKET_NAME}" \
                    --project="${BUCKET_PROJECT}" \
                    --location="us" \
                    --default-encryption-key="${CMEK_STATE_KEY}" \
                    --uniform-bucket-level-access
             else
                  return 1
             fi
        fi
        
        STATE_BUCKET="${NEW_BUCKET_NAME}"
        echo -e "Using Terraform State Bucket: ${GREEN}${STATE_BUCKET}${NC}"
    fi

    echo -e "${GREEN}Prerequisites met successfully${NC}"
    
    return 0
}

# --- Stage 0 Functions ---

check_org_policies() {
    echo "Checking Organization Policies..."
    local failed=0

    # 1. compute.disableInternetNetworkEndpointGroup
    echo -n "Checking compute.disableInternetNetworkEndpointGroup... "
    POLICY_JSON=$(gcloud org-policies describe compute.disableInternetNetworkEndpointGroup --project="${PROJECT_ID}" --effective --format="json" 2>/dev/null || true)
    
    if [[ -z "$POLICY_JSON" ]]; then
        echo -e "${YELLOW}Unable to verify (Check Manually)${NC}"
    else
        # Check both v1 (booleanPolicy) and v2 (spec.rules) formats
        # If any rule enforces it, we consider it enforced.
        IS_ENFORCED=$(echo "$POLICY_JSON" | jq -r '(.booleanPolicy.enforced == true) or (try (.spec.rules[] | .enforce == true) catch false)' 2>/dev/null | grep "true" || true)
        
        if [[ -n "$IS_ENFORCED" ]]; then
            echo -e "${RED}Enforced (FAIL) - Internet NEGs are disabled${NC}"
            failed=1
        else
            echo -e "${GREEN}Disabled (OK)${NC}"
        fi
    fi

    # 2. compute.restrictLoadBalancerCreationForTypes (Only if External)
    if [[ "$DEPLOYMENT_TYPE" == "external" ]]; then
        echo -n "Checking compute.restrictLoadBalancerCreationForTypes... "
        POLICY_JSON=$(gcloud org-policies describe compute.restrictLoadBalancerCreationForTypes --project="${PROJECT_ID}" --effective --format="json" 2>/dev/null || true)
        
        if [[ -z "$POLICY_JSON" ]]; then
            echo -e "${YELLOW}Unable to verify (Check Manually)${NC}"
        else
            # Extract v1 and v2 values
            ALL_VALUES=$(echo "$POLICY_JSON" | jq -r '.listPolicy.allValues // "Unspecified"' 2>/dev/null || echo "Error")
            V2_ALLOW_ALL=$(echo "$POLICY_JSON" | jq -r 'try (.spec.rules[] | select(.allowAll == true) | "true") catch empty' 2>/dev/null | head -n1)
            V2_DENY_ALL=$(echo "$POLICY_JSON" | jq -r 'try (.spec.rules[] | select(.denyAll == true) | "true") catch empty' 2>/dev/null | head -n1)
            
            HAS_ALLOWED_VALUES=$(echo "$POLICY_JSON" | jq -r 'if (.listPolicy? | has("allowedValues")) or (try any(.spec.rules[]?; .values? | has("allowedValues")) catch false) then "true" else "false" end' 2>/dev/null)
            
            ALLOWED_VALUES=$(echo "$POLICY_JSON" | jq -r '.listPolicy.allowedValues[]?, .spec.rules[].values.allowedValues[]?' 2>/dev/null || true)
            DENIED_VALUES=$(echo "$POLICY_JSON" | jq -r '.listPolicy.deniedValues[]?, .spec.rules[].values.deniedValues[]?' 2>/dev/null || true)
            
            if [[ "$ALL_VALUES" == "Error" ]]; then
                 echo -e "${YELLOW}Error parsing policy (Check Manually)${NC}"
            elif [[ "$ALL_VALUES" == "ALLOW" || "$V2_ALLOW_ALL" == "true" ]]; then
                 echo -e "${GREEN}Allowed (OK)${NC}"
            elif [[ "$ALL_VALUES" == "DENY" || "$V2_DENY_ALL" == "true" ]]; then
                 echo -e "${RED}Denied (FAIL) - Policy Enforces DENY ALL${NC}"
                 failed=1
            else
                 # Check allowed/denied lists
                 IS_ALLOWED="true" # Default to true if not explicitly restricted
                 
                 # If allowed_values is present (key exists), we MUST be in it
                 if [[ "$HAS_ALLOWED_VALUES" == "true" ]]; then
                     IS_ALLOWED="false"
                     if [[ -n "$ALLOWED_VALUES" ]]; then
                         if echo "$ALLOWED_VALUES" | grep -qE "EXTERNAL_HTTP_HTTPS|EXTERNAL_MANAGED_HTTP_HTTPS"; then
                             IS_ALLOWED="true"
                         fi
                     fi
                 fi
                 
                 # If denied_values is present, we MUST NOT be in it
                 if [[ -n "$DENIED_VALUES" ]]; then
                     if echo "$DENIED_VALUES" | grep -qE "EXTERNAL_HTTP_HTTPS|EXTERNAL_MANAGED_HTTP_HTTPS"; then
                         IS_ALLOWED="false"
                     fi
                 fi
                 
                 if [[ "$IS_ALLOWED" == "true" ]]; then
                     echo -e "${GREEN}Allowed (OK)${NC}"
                 else
                     echo -e "${RED}Denied (FAIL) - Policy restricts External Load Balancers${NC}"
                     failed=1
                 fi
            fi
        fi
    fi

    if [[ "$failed" -eq 1 ]]; then
        echo -e "${YELLOW}WARNING: One or more Organization Policies may prevent deployment.${NC}"
        read -p "Do you want to proceed anyway? (y/N): " PROCEED
        if [[ "$PROCEED" != "y" && "$PROCEED" != "Y" ]]; then
            return 1
        fi
    fi
    return 0
}

configure_access_policies() {
    echo -e "${BLUE}--- Configure Access Policies ---${NC}"
    
    # Initialize Defaults
    CREATE_IP_BASED_ACCESS="true"
    CREATE_US_ACCESS="true"
    CREATE_TIME_ACCESS="true"
    CREATE_EXPIRE_ACCESS="true"
    CREATE_LENIENT_DEVICE_ACCESS="true"
    CREATE_MODERATE_DEVICE_ACCESS="true"
    CREATE_STRICT_DEVICE_ACCESS="true"
    ENABLE_CEP_BOOL="false"
    
    # Existing Access Levels Check
    echo "Checking for existing Access Levels in Policy ${ACCESS_POLICY_NUMBER}..."
    EXISTING_LEVELS=$(gcloud access-context-manager levels list --policy="${ACCESS_POLICY_NUMBER}" --format="value(name)" || echo "")
    
    # 1. IP Based Access
    echo ""
    echo -e "--- IP Based Access ---"
    EXISTING_IP_ACCESS=$(echo "$EXISTING_LEVELS" | grep -E "(/|^)ip_based_access$" || true)
    
    if [[ -n "$EXISTING_IP_ACCESS" ]]; then
        # Check if managed by Terraform
        if [[ "$MANAGED_ACCESS_LEVELS" == *"ip_based_access"* ]]; then
             echo -e "${GREEN}Found existing MANAGED Access Level 'ip_based_access'. Preserving/Updating.${NC}"
             CREATE_IP_BASED_ACCESS="true"
             # Still offer to add IPs
             read -p "Do you want to add additional IP ranges? (y/N): " ADD_IPS
        else
             echo -e "${YELLOW}Access Level 'ip_based_access' already exists (Unmanaged).${NC}"
             echo "Current Configuration:"
             gcloud access-context-manager levels describe ip_based_access --policy="${ACCESS_POLICY_NUMBER}" --format="value(basic.conditions.ipSubnetworks)" 2>/dev/null || echo "Error fetching IPs"
             
             read -p "Do you want to add additional IP ranges? (y/N): " ADD_IPS
             if [[ "$ADD_IPS" == "y" || "$ADD_IPS" == "Y" ]]; then
                 CREATE_IP_BASED_ACCESS="true"
             else
                 echo "Skipping update of 'ip_based_access'."
                 CREATE_IP_BASED_ACCESS="false"
             fi
        fi
    else
        echo "Access Level 'ip_based_access' does not exist."
        CREATE_IP_BASED_ACCESS="true"
    fi
    
    # Prompt for IPs if we are creating or updating
    ALLOWED_IPS="[]"
    if [[ "$CREATE_IP_BASED_ACCESS" == "true" ]]; then
        echo ""
        echo "Enter IP ranges allowed to access the Load Balancer (CIDR format)."
        echo "RECOMMENDED: Set this to the IP range of the agency's corporate gateway."
        read -p "Enter IP Ranges (comma-separated, e.g., 203.0.113.0/24): " IP_RANGES_INPUT
        
        if [[ -n "$IP_RANGES_INPUT" ]]; then
            IFS=',' read -ra IP_ADDRS <<< "$IP_RANGES_INPUT"
            JSON_IPS=""
            for ip in "${IP_ADDRS[@]}"; do
                ip=$(echo "$ip" | xargs)
                if [[ -n "$JSON_IPS" ]]; then
                    JSON_IPS="$JSON_IPS, \"$ip\""
                else
                    JSON_IPS="\"$ip\""
                fi
            done
            ALLOWED_IPS="[$JSON_IPS]"
        fi
    fi

    # 2. US Region Access
    echo ""
    echo -e "--- US Region Access ---"
    if echo "$EXISTING_LEVELS" | grep -qE "(/|^)us$"; then
        if [[ "$MANAGED_ACCESS_LEVELS" == *"us"* ]]; then
             echo -e "${GREEN}Found existing MANAGED Access Level 'us'. Preserving.${NC}"
             CREATE_US_ACCESS="true"
        else
             echo -e "${YELLOW}Access Level 'us' already exists (Unmanaged). Skipping.${NC}"
             CREATE_US_ACCESS="false"
        fi
    else
        read -p "Restrict incoming traffic to only originate from the 'US'? (y/N): " US_CHOICE
        if [[ "$US_CHOICE" == "y" || "$US_CHOICE" == "Y" ]]; then
            CREATE_US_ACCESS="true"
        else
            CREATE_US_ACCESS="false"
        fi
    fi

    # 3. Time Based Access
    echo ""
    echo -e "--- Time Based Access ---"
    if echo "$EXISTING_LEVELS" | grep -qE "(/|^)time$"; then
        if [[ "$MANAGED_ACCESS_LEVELS" == *"time"* ]]; then
             echo -e "${GREEN}Found existing MANAGED Access Level 'time'. Preserving.${NC}"
             CREATE_TIME_ACCESS="true"
        else
             echo -e "${YELLOW}Access Level 'time' already exists (Unmanaged). Skipping.${NC}"
             CREATE_TIME_ACCESS="false"
        fi
    else
        read -p "Restrict incoming traffic based on a specific time schedule (Business Hours)? (y/N): " TIME_CHOICE
        if [[ "$TIME_CHOICE" == "y" || "$TIME_CHOICE" == "Y" ]]; then
            CREATE_TIME_ACCESS="true"
            read -p "Enter Start Day (1=Mon, 7=Sun) [1]: " ACCESS_START_DAY
            ACCESS_START_DAY=${ACCESS_START_DAY:-1}
            read -p "Enter End Day (1=Mon, 7=Sun) [5]: " ACCESS_END_DAY
            ACCESS_END_DAY=${ACCESS_END_DAY:-5}
            read -p "Enter Start Hour (0-23) [7]: " ACCESS_START_HOUR
            ACCESS_START_HOUR=${ACCESS_START_HOUR:-7}
            read -p "Enter End Hour (0-23) [21]: " ACCESS_END_HOUR
            ACCESS_END_HOUR=${ACCESS_END_HOUR:-21}
            read -p "Enter Time Zone (e.g. America/New_York) [America/New_York]: " ACCESS_TIME_ZONE
            ACCESS_TIME_ZONE=${ACCESS_TIME_ZONE:-"America/New_York"}
        else
            CREATE_TIME_ACCESS="false"
        fi
    fi

    # 4. Expiration Access
    echo ""
    echo -e "--- Expiration Access ---"
    if echo "$EXISTING_LEVELS" | grep -qE "(/|^)expire$"; then
        if [[ "$MANAGED_ACCESS_LEVELS" == *"expire"* ]]; then
             echo -e "${GREEN}Found existing MANAGED Access Level 'expire'. Preserving.${NC}"
             CREATE_EXPIRE_ACCESS="true"
        else
             echo -e "${YELLOW}Access Level 'expire' already exists (Unmanaged). Skipping.${NC}"
             CREATE_EXPIRE_ACCESS="false"
        fi
    else
        read -p "Block incoming traffic after a certain expiration date? (y/N): " EXPIRE_CHOICE
        if [[ "$EXPIRE_CHOICE" == "y" || "$EXPIRE_CHOICE" == "Y" ]]; then
            CREATE_EXPIRE_ACCESS="true"
            read -p "Enter Expiration Timestamp (RFC 3339 format, e.g. 2028-01-01T00:00:00Z) [2028-01-01T00:00:00Z]: " ACCESS_EXPIRATION_TIMESTAMP
            ACCESS_EXPIRATION_TIMESTAMP=${ACCESS_EXPIRATION_TIMESTAMP:-"2028-01-01T00:00:00Z"}
        else
            CREATE_EXPIRE_ACCESS="false"
        fi
    fi

    # 5. Chrome Enterprise Premium
    echo ""
    echo -e "--- Chrome Enterprise Premium ---"
    read -p "Enable Chrome Enterprise Premium (Zero Trust) to access device-level attributes? (y/N): " CEP_CHOICE
    if [[ "$CEP_CHOICE" == "y" || "$CEP_CHOICE" == "Y" ]]; then
        ENABLE_CEP_BOOL="true"
        echo -e "${YELLOW}Note: This requires an additional subscription.${NC}"
        echo -e "Subscribe here: https://console.cloud.google.com/security/cep"
    else
        ENABLE_CEP_BOOL="false"
    fi

    # 6. Derived Device Policies
    echo ""
    echo -e "--- Device Policy Access Levels (Lenient / Moderate / Strict) ---"
    
    # Lenient Device
    if echo "$EXISTING_LEVELS" | grep -qE "(/|^)lenient_device$"; then
        if [[ "$MANAGED_ACCESS_LEVELS" == *"lenient_device"* ]]; then
             CREATE_LENIENT_DEVICE_ACCESS="true"
        else
             CREATE_LENIENT_DEVICE_ACCESS="false"
        fi
    else
        if [[ "$CREATE_US_ACCESS" == "true" || "$CREATE_IP_BASED_ACCESS" == "true" ]]; then
            CREATE_LENIENT_DEVICE_ACCESS="true"
        else
            CREATE_LENIENT_DEVICE_ACCESS="false"
        fi
    fi
    
    # Moderate Device
    if echo "$EXISTING_LEVELS" | grep -qE "(/|^)moderate_device$"; then
        if [[ "$MANAGED_ACCESS_LEVELS" == *"moderate_device"* ]]; then
             CREATE_MODERATE_DEVICE_ACCESS="true"
        else
             CREATE_MODERATE_DEVICE_ACCESS="false"
        fi
    else
        if [[ "$CREATE_US_ACCESS" == "true" || "$CREATE_TIME_ACCESS" == "true" || "$CREATE_EXPIRE_ACCESS" == "true" || "$CREATE_IP_BASED_ACCESS" == "true" ]]; then
            CREATE_MODERATE_DEVICE_ACCESS="true"
        else
            CREATE_MODERATE_DEVICE_ACCESS="false"
        fi
    fi
    
    # Strict Device
    if echo "$EXISTING_LEVELS" | grep -qE "(/|^)strict_device$"; then
        if [[ "$MANAGED_ACCESS_LEVELS" == *"strict_device"* ]]; then
             CREATE_STRICT_DEVICE_ACCESS="true"
        else
             CREATE_STRICT_DEVICE_ACCESS="false"
        fi
    else
        if [[ "$ENABLE_CEP_BOOL" == "true" ]]; then
            CREATE_STRICT_DEVICE_ACCESS="true"
        else
            CREATE_STRICT_DEVICE_ACCESS="false"
        fi
    fi

    echo -e "${GREEN}Access Policy Configuration Complete.${NC}"
}

configure_stage_0() {
    echo ""
    echo -e "${BLUE}--- Configure Stage 0 (Infrastructure) ---${NC}"
    mkdir -p gemini-stage-0
    
    # Check if we can reuse existing config
    if [[ -f "gemini-stage-0/terraform.tfvars" ]]; then
        echo -e "${YELLOW}Found existing configuration.${NC}"
        read -p "Reuse existing configuration? (Y/n): " REUSE_CONFIG
        if [[ "$REUSE_CONFIG" != "n" && "$REUSE_CONFIG" != "N" ]]; then
            echo -e "${GREEN}Using existing configuration.${NC}"
            
            # Extract CREATE_DS_BOOL from existing tfvars for "Action Required" message logic
            echo -e "Using configuration to populate important environment variables..."
            if grep -q "create_data_stores" gemini-stage-0/terraform.tfvars; then
                EXISTING_DS_BOOL=$(grep "create_data_stores" gemini-stage-0/terraform.tfvars | awk -F'=' '{print $2}' | tr -d ' "')
                if [[ "$EXISTING_DS_BOOL" == "true" ]]; then
                    CREATE_DS_BOOL="true"
                fi
            fi
            
            # Even when reusing, check if Terraform State dictates we should suppress CMEK variables
            # This handles cases where resources were created, but tfvars still points to "new" logic
            echo -e "Checking configuration against existing resources in Terraform State..."
            cd gemini-stage-0
            
            # We need BUCKET_NAME. Try to grab it from deploy vars or tfvars
            if [[ -z "$BUCKET_NAME" ]]; then
                 # Try to extract from tfvars if not in env
                 BUCKET_NAME=$(grep 'terraform_state_bucket' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
                 # Clean up gs:// prefix if present in tfvars
                 BUCKET_NAME=$(echo "$BUCKET_NAME" | sed 's/gs:\/\/ //' | sed 's/\/$//')
            fi
            
            if [[ -n "$BUCKET_NAME" ]]; then
                if terraform init -migrate-state -backend-config="bucket=${BUCKET_NAME}" -backend-config="prefix=terraform/state/stage-0" &>/dev/null; then
                     if terraform state list | grep -q "google_kms_key_ring.created"; then
                         echo -e "${YELLOW}KeyRing found in Terraform State. Updating existing config to use managed resource.${NC}"
                         # Update tfvars to clear us_keyring_name
                         # Use strict matching or regex to avoid partial matches
                         # Assuming standard format: us_keyring_name = "..."
                         sed -i '' 's/us_keyring_name *= *".*"/us_keyring_name = ""/' terraform.tfvars 2>/dev/null || sed -i 's/us_keyring_name *= *".*"/us_keyring_name = ""/' terraform.tfvars
                     fi
                     
                     if terraform state list | grep -q "google_kms_crypto_key.gemini_enterprise"; then
                         echo -e "${YELLOW}gemini-enterprise Key found in Terraform State. Updating existing config to use managed resource.${NC}"
                         sed -i '' 's/kms_key_id *= *".*"/kms_key_id = ""/' terraform.tfvars 2>/dev/null || sed -i 's/kms_key_id *= *".*"/kms_key_id = ""/' terraform.tfvars
                     fi
                     
                     if terraform state list | grep -q "google_access_context_manager_access_level"; then
                         echo -e "${YELLOW}Access Levels found in Terraform State. Setting flags to preserve resources.${NC}"
                         # If we find generic access levels we might want to default everything to true?
                         # Or just rely on the granular discovery logic below if we don't overwrite them?
                         # Requirement is to remove 'create_access_policies'.
                         # The new logic relies on 'configure_access_policies' which is called later.
                         # If reusing, users might skip 'configure_access_policies' if they say 'Reuse config'.
                         # If 'terraform.tfvars' exists, it has the granular flags.
                         # We should ensure granular flags are set to true if they are missing?
                         # Actually, if reusing config, we trust the tfvars file.
                         # So we probably don't need to SED replace create_access_policies anymore.
                         # We might want to remove the SED command that sets it.
                     fi
                fi
            fi
            cd ..
            
            return 0
        fi
    fi

    # Run Discovery (Only if not already done)
    # If ENVIRONMENT is set, we assume discovery ran successfully at startup or was manually set.
    if [[ -z "$ENVIRONMENT" ]]; then
        if ! discover_infrastructure; then
            echo -e "${RED}Infrastructure Discovery Failed.${NC}"
            pause
            return
        fi
    fi
    
    # Ensure Prerequisites (Bucket, CMEK)
    if ! ensure_prerequisites; then
        echo -e "${RED}Prerequisite check failed.${NC}"
        pause
        return
    fi

    # 1. Assured Workloads Check
    echo ""
    echo -e "${BLUE}--- Compliance Regime (Assured Workloads) ---${NC}"
    echo "1. FedRAMP High (Default)"
    echo "2. IL4"
    echo "3. None"
    read -p "What compliance regime will you be using? [1]: " REGIME_CHOICE
    REGIME_CHOICE=${REGIME_CHOICE:-1}

    COMPLIANCE_REGIME=""
    REGIME_DISPLAY=""

    case $REGIME_CHOICE in
        1)
            COMPLIANCE_REGIME="FEDRAMP_HIGH"
            REGIME_DISPLAY="FedRAMP High"
            ;;
        2)
            COMPLIANCE_REGIME="IL4"
            REGIME_DISPLAY="IL4"
            ;;
        3)
            echo -e "${YELLOW}WARNING: Gemini for Government currently only supports deployment within FedRAMP High / IL4 Assured Workloads folders.${NC}"
            echo -e "${YELLOW}Proceed at your own risk.${NC}"
            read -p "Press Enter to acknowledge..."
            ;;
        *)
            echo -e "${RED}Invalid selection. Defaulting to FedRAMP High.${NC}"
            COMPLIANCE_REGIME="FEDRAMP_HIGH"
            REGIME_DISPLAY="FedRAMP High"
            ;;
    esac

    if [[ -n "$COMPLIANCE_REGIME" ]]; then
        read -p "Is this project deployed in a ${REGIME_DISPLAY} Assured Workloads folder? (y/N): " IS_ASSURED
        if [[ "$IS_ASSURED" == "y" || "$IS_ASSURED" == "Y" ]]; then
            read -p "Enter the region (e.g., us-east4): " WORKLOAD_REGION
            if [[ -n "$WORKLOAD_REGION" ]]; then
                echo "Fetching ${REGIME_DISPLAY} Assured Workload folders in ${WORKLOAD_REGION}..."
                WORKLOAD_NAME=$(gcloud assured workloads list --location="${WORKLOAD_REGION}" --organization="${ORG_ID}" --filter="complianceRegime=${COMPLIANCE_REGIME}" --format="value(displayName)" 2>/dev/null | head -n 1 || true)
                
                if [[ -z "$WORKLOAD_NAME" ]]; then
                    echo -e "${YELLOW}Warning: Could not find ${REGIME_DISPLAY} Assured Workload folder in ${WORKLOAD_REGION}.${NC}"
                    echo -e "${YELLOW}Skipping automated Assured Workloads updates.${NC}"
                else
                    echo ""
                    echo -e "${YELLOW}ACTION REQUIRED: Please update your Assured Workload environment manually.${NC}"
                    echo -e "1. Navigate to the following URL in your browser:"
                    echo -e "${BLUE}https://console.cloud.google.com/compliance/assuredworkloads?organizationId=${ORG_ID}${NC}"
                    echo -e "2. Click on the ${REGIME_DISPLAY} Assured Workload named: ${GREEN}${WORKLOAD_NAME}${NC}"
                    echo -e "3. Click on the button to ${GREEN}\"Review available updates\"${NC} and apply them."
                    echo ""
                    read -p "Press Enter after you have confirmed the updates have been made..."
                    echo -e "${GREEN}Assured Workload folder ${WORKLOAD_NAME} validated / updated${NC}"
                fi
            fi
        fi
    fi


    # 2. Shared VPC
    USE_SHARED_VPC="false"
    SHARED_VPC_HOST_PROJECT=""
    SHARED_VPC_NETWORK=""
    SHARED_VPC_SUBNET=""
    SHARED_VPC_PROXY_SUBNET=""
    echo ""
    echo -e "${BLUE}--- Networking ---${NC}"
    read -p "Do you want to use an existing Shared VPC? (y/N) [N]: " USE_SHARED_VPC_CHOICE
    if [[ "$USE_SHARED_VPC_CHOICE" == "y" || "$USE_SHARED_VPC_CHOICE" == "Y" ]]; then
        USE_SHARED_VPC="true"
        
        # 1. Determine Host Project & Verify Attachment
        SHARED_VPC_HOST_PROJECT=$(gcloud compute shared-vpc get-host-project "${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)

        # If not attached, fail and advise user
        if [[ -z "$SHARED_VPC_HOST_PROJECT" ]]; then
            POTENTIAL_HOST_PROJECT=$(echo "$PROJECT_ID" | cut -d'-' -f1-2 | sed 's/$/-net-host/')
            
            echo -e "${RED}ERROR: Project '${PROJECT_ID}' is not attached to a Shared VPC Host.${NC}"
            echo -e "${YELLOW}To proceed, you must:${NC}"
            echo -e "1. Attach this project to the Shared VPC Host Project."
            echo -e "   (Command: gcloud compute shared-vpc associated-projects add ${PROJECT_ID} --host-project ${POTENTIAL_HOST_PROJECT})"
            echo -e "2. Share the VPC Host Project subnets with this Service Project."
            echo -e "${YELLOW}Please configure this and rerun deploy.sh.${NC}"
            return 1
        fi
        
        echo -e "Using Shared VPC: ${GREEN}Yes${NC}"
        echo -e "Using Network Host Project: ${YELLOW}${SHARED_VPC_HOST_PROJECT}${NC}"

        # 2. Auto-discover Network and Subnets
        if [[ -z "$SHARED_VPC_NETWORK" ]]; then
            echo "Scanning for subnets shared from ${SHARED_VPC_HOST_PROJECT} to ${PROJECT_ID}..."
            
            # Get all subnets from the Host Project directly in JSON format
            USABLE_SUBNETS_JSON=$(gcloud compute networks subnets list --project "${SHARED_VPC_HOST_PROJECT}" --format="json" 2>/dev/null)
            
            if [[ -z "$USABLE_SUBNETS_JSON" || "$USABLE_SUBNETS_JSON" == "[]" ]]; then
                 echo -e "${RED}ERROR: No subnets found in Host Project '${SHARED_VPC_HOST_PROJECT}' or permission denied.${NC}"
                 echo -e "${YELLOW}Please ensure that:${NC}"
                 echo -e "1. The Host Project exists and you have permissions to list subnets."
                 echo -e "2. You have shared the necessary subnets with this Service Project."
                 echo -e "3. You are authenticated correctly."
                 return 1
            fi

            # 1. Discover Private Subnet & Network (Atomic operation to ensure consistency)
            # We pick the first usable PRIVATE subnet in the Host Project AND in the correct Region (defaulting to us-east4 if not set)
            DISCOVERY_REGION=$(gcloud config get-value compute/region 2>/dev/null)
            DISCOVERY_REGION=${DISCOVERY_REGION:-"us-east4"}
            
            # We also normalize 'selfLink' to 'subnetwork' to handle both 'list-usable' and 'list' output formats
            FIRST_USABLE_SUBNET_JSON=$(echo "$USABLE_SUBNETS_JSON" | jq -r ".[] | .subnetwork = (.subnetwork // .selfLink) | select(.network | contains(\"projects/${SHARED_VPC_HOST_PROJECT}/\")) | select(.subnetwork | contains(\"/${DISCOVERY_REGION}/\")) | select(.purpose == \"PRIVATE\" or .purpose == null) | {network: .network, subnetwork: .subnetwork} | tojson" | head -n 1)
            
            if [[ -n "$FIRST_USABLE_SUBNET_JSON" ]]; then
                SHARED_VPC_NETWORK_URL=$(echo "$FIRST_USABLE_SUBNET_JSON" | jq -r .network)
                SHARED_VPC_NETWORK=$(basename "$SHARED_VPC_NETWORK_URL")
                
                SHARED_VPC_SUBNET_URL=$(echo "$FIRST_USABLE_SUBNET_JSON" | jq -r .subnetwork)
                SHARED_VPC_SUBNET=$(basename "$SHARED_VPC_SUBNET_URL")
                
                # Extract Region from Subnet URL to ensure consistency
                # URL format: .../regions/REGION/subnetworks/SUBNET
                REGION=$(echo "$SHARED_VPC_SUBNET_URL" | sed -E 's/.*\/regions\/([^\/]+)\/.*/\1/')
            fi

            # 2. Discover Proxy Subnet (purpose=REGIONAL_MANAGED_PROXY, in the SAME Network and Region)
            if [[ -n "$SHARED_VPC_NETWORK_URL" ]]; then
                SHARED_VPC_PROXY_SUBNET_URL=$(echo "$USABLE_SUBNETS_JSON" | jq -r ".[] | .subnetwork = (.subnetwork // .selfLink) | select(.network == \"$SHARED_VPC_NETWORK_URL\") | select(.subnetwork | contains(\"/${REGION}/\")) | select(.purpose == \"REGIONAL_MANAGED_PROXY\") | .subnetwork" | head -n 1)
                SHARED_VPC_PROXY_SUBNET=$(basename "$SHARED_VPC_PROXY_SUBNET_URL")
            fi
        fi

        # Fallbacks if discovery fails
        if [[ -z "$SHARED_VPC_NETWORK" ]]; then
            read -p "Enter Shared VPC Network Name: " INPUT_NETWORK
            SHARED_VPC_NETWORK=${INPUT_NETWORK}
        fi
        if [[ -z "$SHARED_VPC_SUBNET" ]]; then
            read -p "Enter Shared VPC Subnet Name: " INPUT_SUBNET
            SHARED_VPC_SUBNET=${INPUT_SUBNET}
        fi
        if [[ -z "$SHARED_VPC_PROXY_SUBNET" ]]; then
            read -p "Enter Shared VPC Proxy Subnet Name: " INPUT_PROXY_SUBNET
            SHARED_VPC_PROXY_SUBNET=${INPUT_PROXY_SUBNET}
        fi
        
        echo -e "Network: ${YELLOW}${SHARED_VPC_NETWORK}${NC}"
        echo -e "Subnet: ${YELLOW}${SHARED_VPC_SUBNET}${NC}"
        echo -e "Proxy Subnet: ${YELLOW}${SHARED_VPC_PROXY_SUBNET}${NC}"
    fi

    # 3. Region
    if [[ -z "$REGION" ]]; then
        REGION=$(gcloud config get-value compute/region 2>/dev/null)
        REGION=${REGION:-"us-east4"}
        read -p "Enter Region [${REGION}]: " INPUT_REGION
        REGION=${INPUT_REGION:-$REGION}
    fi
    echo -e "Using Region: ${YELLOW}${REGION}${NC}"

    # 4. Load Balancer Type
    echo ""
    echo -e "Select Load Balancer Type:"
    echo "1) Regional External (Internet facing)"
    echo "2) Regional Internal (VPN / Interconnect)"
    read -p "Enter selection [1]: " LB_SEL
    if [[ "$LB_SEL" == "2" ]]; then
        DEPLOYMENT_TYPE="internal"
    else
        DEPLOYMENT_TYPE="external"
    fi

    # 5. Domain
    if [[ -z "$DOMAIN" ]]; then
        ORG_DOMAIN=$(gcloud organizations list --filter="name:organizations/${ORG_ID}" --format="value(displayName)" 2>/dev/null)
        DOMAIN=${ORG_DOMAIN}
    fi

    if [[ -z "$DOMAIN" ]]; then
        read -p "Enter Domain (e.g., example.com): " DOMAIN
    else
        echo -e "Using Domain: ${YELLOW}${DOMAIN}${NC}"
    fi

    # 6. Identity Provider
    echo ""
    echo -e "${BLUE}--- Identity and Access ---${NC}"
    echo "Select Gemini Enterprise Identity Provider:"
    echo "----------------------------------------------------------------"
    echo "1) GSUITE (Default)"
    echo "   - Best for users with Google Workspace accounts."
    echo "   - Uses standard Google Groups (e.g., gcp-gemini-enterprise-admins@${DOMAIN})."
    echo "   - Simple setup, requires Cloud Identity or Google Workspace."
    echo ""
    echo "2) THIRD_PARTY (Workforce Identity Federation)"
    echo "   - Best for external identity providers (Okta, Azure AD, etc.)."
    echo "   - Syncless: No need to sync users to Google Cloud."
    echo "   - Uses Attribute-Based Access Control (ABAC)."
    echo "   - Requires a configured Workforce Identity Pool."
    echo "----------------------------------------------------------------"
    read -p "Enter selection [1]: " ACL_SELECTION
    
    ACL_IDP_TYPE="GSUITE"
    ACL_POOL_NAME=""
    ACL_PROVIDER_ID=""
    
    if [[ "$ACL_SELECTION" == "2" ]]; then
        ACL_IDP_TYPE="THIRD_PARTY"
        
        # Auto-discover Workforce Pools
        echo ""
        echo "Discovering Workforce Identity Pools..."
        POOLS_JSON=$(gcloud iam workforce-pools list --organization="${ORG_ID}" --location="global" --format="json" 2>/dev/null)
        
        if [[ -n "$POOLS_JSON" && "$POOLS_JSON" != "[]" ]]; then
            echo ""
            echo "Available Workforce Pools:"
            echo "$POOLS_JSON" | jq -r '.[] | "\(.name) (\(.displayName))"' | nl -w2 -s") "
            
            read -p "Select a Workforce Pool [1]: " POOL_SEL
            POOL_SEL=${POOL_SEL:-1}
            
            # Extract selected pool name (full resource name)
            ACL_POOL_NAME=$(echo "$POOLS_JSON" | jq -r ".[$((POOL_SEL-1))].name")
        fi
        
        if [[ -z "$ACL_POOL_NAME" ]]; then
            echo -e "${YELLOW}No pools found or invalid selection. Switching to manual entry.${NC}"
            read -p "Enter Workforce Pool ID: " ACL_POOL_ID
            ACL_POOL_NAME="locations/global/workforcePools/${ACL_POOL_ID}"
        else
            echo -e "Selected Pool: ${YELLOW}${ACL_POOL_NAME}${NC}"
        fi
        
        # Auto-discover Providers
        echo ""
        echo "Discovering Providers in ${ACL_POOL_NAME}..."
        PROVIDERS_JSON=$(gcloud iam workforce-pools providers list --workforce-pool="${ACL_POOL_NAME}" --location="global" --format="json" 2>/dev/null)
        
        if [[ -n "$PROVIDERS_JSON" && "$PROVIDERS_JSON" != "[]" ]]; then
            echo "Available Providers:"
            echo "$PROVIDERS_JSON" | jq -r '.[] | "\(.name) (\(.displayName))"' | nl -w2 -s") "
            
            read -p "Select a Provider [1]: " PROV_SEL
            PROV_SEL=${PROV_SEL:-1}
            
            # Extract selected provider ID (last part of name)
            FULL_PROV_NAME=$(echo "$PROVIDERS_JSON" | jq -r ".[$((PROV_SEL-1))].name")
            ACL_PROVIDER_ID=$(basename "$FULL_PROV_NAME")
        fi
        
        if [[ -z "$ACL_PROVIDER_ID" ]]; then
            echo -e "${YELLOW}No providers found or invalid selection. Switching to manual entry.${NC}"
            read -p "Enter Workforce Provider ID: " ACL_PROVIDER_ID
        else
            echo -e "Selected Provider: ${YELLOW}${ACL_PROVIDER_ID}${NC}"
        fi
        
        # Extract Pool ID for display/verification if needed (though we have full name now)
        ACL_POOL_ID=$(basename "$ACL_POOL_NAME")
        
        echo ""
        echo -e "${YELLOW}ACTION REQUIRED: Please verify the attribute mapping for your provider.${NC}"
        echo -e "1. Navigate to the Workforce Identity Pools page:"
        echo -e "${BLUE}https://console.cloud.google.com/iam-admin/workforce-identity-pools?orgonly=true&organizationId=${ORG_ID}&supportedpurview=organizationId${NC}"
        echo -e "2. Select the pool: ${GREEN}${ACL_POOL_ID}${NC}"
        echo -e "3. Go to the ${GREEN}Providers${NC} tab and select your provider: ${GREEN}${ACL_PROVIDER_ID}${NC}"
        echo -e "4. Click ${GREEN}EDIT${NC} and go to the ${GREEN}Attribute Mapping${NC} section."
        echo -e "5. Ensure that the attribute ${YELLOW}google.email${NC} is mapped from your identity provider's email attribute."
        echo -e "   (Example mapping: ${YELLOW}assertion.email${NC} or ${YELLOW}assertion.sub${NC})"
        echo ""
        read -p "Press Enter after you have confirmed the attribute mapping is correct..."
    fi

    # 7. Groups
    if [[ "$ACL_IDP_TYPE" == "GSUITE" ]]; then
        DEFAULT_ADMIN="gcp-gemini-enterprise-admins@${DOMAIN}"
        DEFAULT_USER="gcp-gemini-enterprise-users@${DOMAIN}"
        read -p "Enter Admin Group [${DEFAULT_ADMIN}]: " ADMIN_GROUP
        ADMIN_GROUP=${ADMIN_GROUP:-$DEFAULT_ADMIN}
        read -p "Enter User Group [${DEFAULT_USER}]: " USER_GROUP
        USER_GROUP=${USER_GROUP:-$DEFAULT_USER}
        
        # Add group: prefix
        [[ "$ADMIN_GROUP" != *":"* ]] && ADMIN_GROUP="group:${ADMIN_GROUP}"
        [[ "$USER_GROUP" != *":"* ]] && USER_GROUP="group:${USER_GROUP}"
    else
        echo ""
        echo -e "${YELLOW}For Workforce Identity, please enter the full Principal / Principal Set.${NC}"
        echo "This allows you to map groups, users, or attributes from your IdP to IAM roles."
        echo ""
        echo "Examples:"
        echo " - Single user in a workforce identity pool:"
        echo -e "   principal://iam.googleapis.com/${ACL_POOL_NAME}/subject/${YELLOW}SUBJECT_ATTRIBUTE_VALUE${NC}"
        echo ""
        echo " - All users in a workforce identity pool group:"
        echo -e "   principalSet://iam.googleapis.com/${ACL_POOL_NAME}/group/${YELLOW}GROUP_ID${NC}"
        echo ""
        echo " - All users with a specific attribute (e.g., department=engineering):"
        echo -e "   principalSet://iam.googleapis.com/${ACL_POOL_NAME}/${YELLOW}attribute.department${NC}/${YELLOW}engineering${NC}"
        echo ""
        echo " - All users in the pool (Use with caution):"
        echo -e "   principalSet://iam.googleapis.com/${ACL_POOL_NAME}/${YELLOW}*${NC}"
        echo ""
        
        read -p "Enter Admin Principal/Principal Set: " ADMIN_GROUP
        read -p "Enter User Principal/Principal Set: " USER_GROUP
    fi

    # 8. Access Policy
    echo ""
    echo -e "${BLUE}--- Access Policies ---${NC}"
    echo "Discovering Access Policy..."
    ACCESS_POLICY_NUMBER=$(gcloud access-context-manager policies list --organization "${ORG_ID}" --format="value(name)" --quiet 2>/dev/null | head -n 1)
    if [ -z "$ACCESS_POLICY_NUMBER" ]; then
        echo -e "${YELLOW}Warning: Could not auto-discover Access Policy Number.${NC}"
        read -p "Enter Access Policy Number: " ACCESS_POLICY_NUMBER
    else
        ACCESS_POLICY_NUMBER=$(basename "${ACCESS_POLICY_NUMBER}")
        echo -e "Found Access Policy Number: ${YELLOW}${ACCESS_POLICY_NUMBER}${NC}"
    fi

    if [[ -z "$ACCESS_POLICY_NUMBER" ]]; then
        echo -e "${RED}Error: Access Policy Number is required.${NC}"
        return 1
    fi
    
    # Pre-check Terraform State for managed Access Levels
    # This requires determining BUCKET_NAME and running terraform init early
    echo "Checking Terraform State for managed resources..."
    cd gemini-stage-0
    
    # Resolve Bucket Name Logic (Duplicates logic from deploy_stage_0/configure_stage_0 reuse block)
    # If using existing tfvars, use it. If not, use derived STATE_BUCKET.
    TEMP_BUCKET_NAME="${BUCKET_NAME}"
    if [[ -z "$TEMP_BUCKET_NAME" ]]; then
         if [[ -f "terraform.tfvars" ]]; then
             TEMP_BUCKET_NAME=$(grep 'terraform_state_bucket' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
             TEMP_BUCKET_NAME=$(echo "$TEMP_BUCKET_NAME" | sed 's/gs:\/\/ //' | sed 's/\/$//')
         fi
    fi
    # If still empty, fall back to global STATE_BUCKET
    if [[ -z "$TEMP_BUCKET_NAME" && -n "$STATE_BUCKET" ]]; then
        TEMP_BUCKET_NAME=$(echo "$STATE_BUCKET" | sed 's/gs:\/\/ //' | sed 's/\/$//')
    fi
    
    MANAGED_ACCESS_LEVELS=""
    if [[ -n "$TEMP_BUCKET_NAME" ]]; then
        echo "Initializing Terraform (Read-Only) to check state in ${TEMP_BUCKET_NAME}..."
        # We suppress output to keep UI clean, but allow errors to show if critical
        if terraform init -migrate-state -backend-config="bucket=${TEMP_BUCKET_NAME}" -backend-config="prefix=terraform/state/stage-0" &>/dev/null; then
             MANAGED_ACCESS_LEVELS=$(terraform state list | grep "google_access_context_manager_access_level" || true)
             if [[ -n "$MANAGED_ACCESS_LEVELS" ]]; then
                 echo -e "${GREEN}Found managed Access Levels in state.${NC}"
             fi
        else
             echo -e "${YELLOW}Warning: Could not initialize Terraform state check. Proceeding as fresh deployment.${NC}"
        fi
    else
        echo "State bucket not determined. Skipping managed resource check."
    fi
    cd ..

    configure_access_policies

    # Cloud Armor WAF Information
    echo ""
    echo -e "${BLUE}--- Cloud Armor (WAF) ---${NC}"
    echo -e "${YELLOW}Cloud Armor will act as a Web Application Firewall (WAF) for your Gemini Enterprise application.${NC}"
    echo -e "It will be deployed with predefined rules and sensitivity levels."
    echo ""
    echo -e "Please review the configuration in: ${BLUE}blueprints/fedramp-high/gemini-enterprise/gemini-stage-0/data/cloudarmor.yaml${NC}"
    echo -e "For more information on predefined WAF rules, visit: ${BLUE}https://docs.cloud.google.com/armor/docs/waf-rules${NC}"
    echo ""
    read -p "Press Enter to acknowledge and continue..."

    # 9. Data Stores
    echo ""
    echo -e "${BLUE}--- Data Stores (Cloud Storage / BigQuery) ---${NC}"
    echo -e "${YELLOW}--- NOTE: Data Stores can be created and associated with a Gemini Enterprise application at a later time. ---${NC}"
    read -p "Create Data Stores? (y/N): " DS_CHOICE
    CREATE_DS_BOOL="false"
    GCS_DATA_STORES="[]"
    BQ_DATA_STORES="[]"
    
    if [[ "$DS_CHOICE" == "y" || "$DS_CHOICE" == "Y" ]]; then
        CREATE_DS_BOOL="true"
        
        GCS_LIST=()
        BQ_LIST=()
        
        configure_data_stores
        
        if [[ ${#GCS_LIST[@]} -gt 0 ]]; then
            GCS_DATA_STORES="[$(IFS=,; echo "${GCS_LIST[*]}")]"
        fi
        if [[ ${#BQ_LIST[@]} -gt 0 ]]; then
            BQ_DATA_STORES="[$(IFS=,; echo "${BQ_LIST[*]}")]"
        fi
    fi

    # 10. Organization Policy Check
    echo ""
    echo -e "${BLUE}--- Organization Policies (Project-Level) ---${NC}"
    check_org_policies
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    echo ""
    echo -e "${BLUE}--- Manual Steps ---${NC}"
    echo -e "${YELLOW}IMPORTANT: Before proceeding, ensure you have completed the following manual prerequisites:${NC}"
    echo "1. OAuth Consent Screen: Configured as Internal."
    echo -e "   Link: ${BLUE}https://console.cloud.google.com/auth/branding?orgonly=true&project=${PROJECT_ID}&supportedpurview=organizationId${NC}"
    echo "2. User Role Groups: Created admin/user groups in Cloud Identity / third-party identity provider (${ADMIN_GROUP}, ${USER_GROUP})."
    echo ""
    read -p "Have you completed these steps? (y/N): " CONFIRM_PRE
    if [[ "$CONFIRM_PRE" != "y" && "$CONFIRM_PRE" != "Y" ]]; then
        echo "Please complete the prerequisites and try again."
        return 1
    fi

    # Greenfield: Create KeyRing and Key if needed
    if [[ "$IS_BROWNFIELD" == "false" && "$IS_CUSTOM" == "false" && -z "$KMS_KEY_ID" ]]; then
        echo "Greenfield Deployment: Checking/Creating KMS KeyRing and Key..."
        KEYRING_NAME="gemini-enterprise-keyring"
        KEY_NAME="state-key"
        KEYRING_LOCATION="us"

        # Check/Create KeyRing
        if ! gcloud kms keyrings describe "$KEYRING_NAME" --location="$KEYRING_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
            echo "Creating KeyRing ${KEYRING_NAME} in ${KEYRING_LOCATION}..."
            gcloud kms keyrings create "$KEYRING_NAME" --location="$KEYRING_LOCATION" --project="$PROJECT_ID"
        else
            echo "KeyRing ${KEYRING_NAME} already exists."
        fi

        # Check/Create Key
        if ! gcloud kms keys describe "$KEY_NAME" --keyring="$KEYRING_NAME" --location="$KEYRING_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
            echo "Creating Key ${KEY_NAME} (HSM, 90-day rotation)..."
            # Calculate next rotation time (90 days from now) using Python for portability
            NEXT_ROTATION_TIME=$(python3 -c 'import datetime; print((datetime.datetime.utcnow() + datetime.timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
            
            gcloud kms keys create "$KEY_NAME" \
                --keyring="$KEYRING_NAME" \
                --location="$KEYRING_LOCATION" \
                --purpose="encryption" \
                --protection-level="hsm" \
                --rotation-period="7776000s" \
                --next-rotation-time="$NEXT_ROTATION_TIME" \
                --project="$PROJECT_ID"
        else
            echo "Key ${KEY_NAME} already exists."
        fi
        
        KMS_KEY_ID="projects/${PROJECT_ID}/locations/${KEYRING_LOCATION}/keyRings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"
        echo -e "Using KMS Key: ${YELLOW}${KMS_KEY_ID}${NC}"
    fi

    # Determine create_resource_keys
    # If Brownfield or Custom, and we have a KMS Key ID, we assume we are using existing keys
    # and do not need to create new ones.
    CREATE_RESOURCE_KEYS_BOOL="true"
    if [[ ("$IS_BROWNFIELD" == "true" || "$IS_CUSTOM" == "true") && -n "$KMS_KEY_ID" ]]; then
        CREATE_RESOURCE_KEYS_BOOL="false"
    fi

    # Initialize Terraform early to check state
    echo ""
    echo -e "${BLUE}--- Existing Terraform State Check ---${NC}"
    cd gemini-stage-0
    # Ensure BUCKET_NAME is set for backend init
    if [[ -z "$BUCKET_NAME" && -n "$STATE_BUCKET" ]]; then
        BUCKET_NAME=$(echo "$STATE_BUCKET" | sed 's/gs:\/\/ //' | sed 's/\/$//')
    fi
    terraform init -migrate-state -backend-config="bucket=${BUCKET_NAME}" -backend-config="prefix=terraform/state/stage-0" || echo "Warning: Init failed during state check."

    # Check if KeyRing is in state
    if terraform state list | grep -q "google_kms_key_ring.created"; then
        echo -e "${YELLOW}CMEK Keyring found in Terraform State. Will use managed resource instead of data source.${NC}"
        CMEK_US_KEYRING=""
    fi

    # Check if Key is in state (only if not explicitly provided by user)
    if [[ -z "$CMEK_US_RESOURCES_KEY" ]] && terraform state list | grep -q "google_kms_crypto_key.gemini_enterprise"; then
        echo -e "${YELLOW}gemini-enterprise Crypto Key found in Terraform State. Will use managed resource instead of data source.${NC}"
    fi
    cd ..

    # Generate terraform.tfvars
    cat > gemini-stage-0/terraform.tfvars <<EOF
main_project_id             = "${PROJECT_ID}"
environment                 = "${ENVIRONMENT}"
tenant                      = "${TENANT}"
kms_project_id              = "${CMEK_PROJECT_ID}"
us_keyring_name             = "${CMEK_US_KEYRING}"
kms_key_id                  = "${CMEK_US_RESOURCES_KEY}"
terraform_state_bucket      = "${STATE_BUCKET}"
region                      = "${REGION}"
domain                      = "${DOMAIN}"
prefix                      = "${PREFIX}"
deployment_type             = "${DEPLOYMENT_TYPE}"
access_policy_number        = ${ACCESS_POLICY_NUMBER}
admin_group                 = "${ADMIN_GROUP}"
user_group                  = "${USER_GROUP}"
acl_idp_type                = "${ACL_IDP_TYPE}"
acl_workforce_pool_name     = "${ACL_POOL_NAME}"
acl_workforce_provider_id   = "${ACL_PROVIDER_ID}"
use_shared_vpc              = ${USE_SHARED_VPC}
network_project_id          = "${SHARED_VPC_HOST_PROJECT}"
shared_vpc_network_name     = "${SHARED_VPC_NETWORK}"
shared_vpc_subnet_name      = "${SHARED_VPC_SUBNET}"
shared_vpc_proxy_subnet_name = "${SHARED_VPC_PROXY_SUBNET}"
create_data_stores          = ${CREATE_DS_BOOL}
EOF

    
    # Add example data stores
    if [[ "$CREATE_DS_BOOL" == "true" ]]; then
        cat >> gemini-stage-0/terraform.tfvars <<EOF
gcs_data_store_names = ${GCS_DATA_STORES}
bq_data_store_configs = ${BQ_DATA_STORES}
EOF
    fi

    # Construct Access Level Lists
    LENIENT_LIST=()
    MODERATE_LIST=()
    
    PREFIX_PATH="accessPolicies/${ACCESS_POLICY_NUMBER}/accessLevels"
    
    if [[ "$CREATE_US_ACCESS" == "true" ]]; then
        LENIENT_LIST+=("\"${PREFIX_PATH}/us\"")
        MODERATE_LIST+=("\"${PREFIX_PATH}/us\"")
    fi
    
    if [[ "$CREATE_IP_BASED_ACCESS" == "true" ]]; then
         LENIENT_LIST+=("\"${PREFIX_PATH}/ip_based_access\"")
         MODERATE_LIST+=("\"${PREFIX_PATH}/ip_based_access\"")
    fi
    
    if [[ "$CREATE_TIME_ACCESS" == "true" ]]; then
        MODERATE_LIST+=("\"${PREFIX_PATH}/time\"")
    fi
    
    if [[ "$CREATE_EXPIRE_ACCESS" == "true" ]]; then
        MODERATE_LIST+=("\"${PREFIX_PATH}/expire\"")
    fi
    
    LENIENT_STR="[$(IFS=,; echo "${LENIENT_LIST[*]}")]"
    MODERATE_STR="[$(IFS=,; echo "${MODERATE_LIST[*]}")]"

    # Add Access Policy Creation Flags
    cat >> gemini-stage-0/terraform.tfvars <<EOF
create_ip_based_access          = ${CREATE_IP_BASED_ACCESS}
create_us_access                = ${CREATE_US_ACCESS}
create_time_access              = ${CREATE_TIME_ACCESS}
create_expire_access            = ${CREATE_EXPIRE_ACCESS}
create_lenient_device_access    = ${CREATE_LENIENT_DEVICE_ACCESS}
create_moderate_device_access   = ${CREATE_MODERATE_DEVICE_ACCESS}
create_strict_device_access     = ${CREATE_STRICT_DEVICE_ACCESS}
enable_chrome_enterprise_premium = ${ENABLE_CEP_BOOL}
lenient_device_access_levels    = ${LENIENT_STR}
moderate_device_access_levels   = ${MODERATE_STR}
EOF
    
    # Add Time variables if set
    if [[ -n "$ACCESS_START_DAY" ]]; then
         echo "access_start_day = ${ACCESS_START_DAY}" >> gemini-stage-0/terraform.tfvars
    fi
    if [[ -n "$ACCESS_END_DAY" ]]; then
         echo "access_end_day = ${ACCESS_END_DAY}" >> gemini-stage-0/terraform.tfvars
    fi
    if [[ -n "$ACCESS_START_HOUR" ]]; then
         echo "access_start_hour = ${ACCESS_START_HOUR}" >> gemini-stage-0/terraform.tfvars
    fi
    if [[ -n "$ACCESS_END_HOUR" ]]; then
         echo "access_end_hour = ${ACCESS_END_HOUR}" >> gemini-stage-0/terraform.tfvars
    fi
    if [[ -n "$ACCESS_TIME_ZONE" ]]; then
         echo "access_time_zone = \"${ACCESS_TIME_ZONE}\"" >> gemini-stage-0/terraform.tfvars
    fi
    if [[ -n "$ACCESS_EXPIRATION_TIMESTAMP" ]]; then
         echo "access_expiration_timestamp = \"${ACCESS_EXPIRATION_TIMESTAMP}\"" >> gemini-stage-0/terraform.tfvars
    fi
    
    # Add Allowed IPs
    echo "allowed_ip_ranges = ${ALLOWED_IPS}" >> gemini-stage-0/terraform.tfvars

    echo -e "${GREEN}Configuration generated in gemini-stage-0/terraform.tfvars${NC}"

    return 0
}

deploy_stage_0() {
    echo ""
    echo -e "${BLUE}--- Deploying Stage 0 ---${NC}"
    
    cd gemini-stage-0
    rm -f backend.tf
    
    echo "Initializing Terraform..."
    if ! terraform init -migrate-state -backend-config="bucket=${BUCKET_NAME}" -backend-config="prefix=terraform/state/stage-0"; then
        echo -e "${RED}Terraform Init failed! Please try resolving the error and running the Step again.${NC}"
        cd ..
        pause
        return 1
    fi
    
    echo ""
    echo "Applying Terraform..."
    if ! terraform apply -var-file="terraform.tfvars"; then
        echo -e "${RED}Terraform Apply failed! Please try resolving the error and running the Step again.${NC}"
        cd ..
        pause
        return 1
    fi
    
    GEMINI_IP=$(terraform output -raw gemini_enterprise_ip 2>/dev/null || echo "N/A")
    cd ..
    echo -e "${GREEN}Stage 0 Deployment Complete!${NC}"

    if [[ "$CREATE_DS_BOOL" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}ACTION REQUIRED: Populate the created Data Stores with data.${NC}"
        echo ""
        echo -e "${BLUE}GCS${NC}: Upload your documents to the GCS bucket(s) created by Terraform (see output above \`gcs_data_store_to_bucket\`)."
        echo -e "${BLUE}BigQuery${NC}: Populate the BigQuery table(s) created by Terraform (see output above \`bq_data_store_to_dataset_table\`)"
        echo ""
        echo -e "After uploading documents into the bucket / table, navigate to ${YELLOW}Helper Functions${NC} > ${YELLOW}Populate Data Stores${NC}"
        echo -e "to import the data into the Gemini Enterprise Data Stores and begin the indexing process."
        read -p "Press Enter to continue..."
    fi
    
    echo ""
    echo -e "${YELLOW}IMPORTANT NEXT STEPS:${NC}"
    echo -e "1. From the Main Menu select ${BLUE}Step 2 - Create Gemini Enterprise App (gem4gov-cli)${NC}."
    echo -e "2. Setup DNS A Record that points the desired Gemini Enterprise subdomain (i.e. gemini.yourdomain.com) to the provisioned Load Balancer IP address (${GEMINI_IP})."
    echo -e "3. Provision an SSL Certificate and upload it to Google Cloud Certificate Manager (${YELLOW}Helper Functions > Upload SSL Certificate${NC})."
    echo -e "4. From the Main Menu select ${BLUE}Step 3 - Configure & Deploy Load Balancer / Access Policies (gemini-stage-1)${NC}."
    pause
}

# --- Gem4Gov Functions ---

ensure_gem4gov_installed() {
    if ! command -v gem4gov &> /dev/null; then
        if [[ -d "gem4gov-cli" ]]; then
            echo "Installing gem4gov CLI..."
            pip3 install -e gem4gov-cli
            export PATH="$PATH:$(python3 -m site --user-base)/bin"
        else
            echo -e "${RED}gem4gov-cli directory not found.${NC}"
            return 1
        fi
    fi
    return 0
}

configure_gem4gov() {
    echo ""
    echo -e "${BLUE}--- Configure Gemini Enterprise App (gem4gov) ---${NC}"
    
    if ! ensure_gem4gov_installed; then
        return 1
    fi

    # Retrieve outputs from Stage 0 state
    # Ensure BUCKET_NAME is set from STATE_BUCKET if not already
    if [[ -z "$BUCKET_NAME" && -n "$STATE_BUCKET" ]]; then
        BUCKET_NAME=$(echo "$STATE_BUCKET" | sed 's/gs:\/\/ //' | sed 's/\/$//')
    fi
    
    echo "Retrieving state from gs://${BUCKET_NAME}/terraform/state/stage-0/default.tfstate..."
    STATE_CONTENT=$(gcloud storage cat "gs://${BUCKET_NAME}/terraform/state/stage-0/default.tfstate" 2>/dev/null || echo "{}")
    
    # Parse needed values
    PROJECT_ID_STATE=$(echo "$STATE_CONTENT" | jq -r '.outputs.main_project_id.value // empty')
    PROJECT_ID=${PROJECT_ID_STATE:-$PROJECT_ID}
    
    # Parse Load Balancer IP for display
    GEMINI_IP=$(echo "$STATE_CONTENT" | jq -r '.outputs.gemini_enterprise_ip.value // "N/A"')
    
    # Construct command
    CMD="gem4gov app create --project-id ${PROJECT_ID} --compliance-regime FEDRAMP_HIGH"
    
    # 1. Extract Data Store IDs
    # Retrieve both GCS and BQ Data Store IDs from outputs and concatenate them
    ALL_IDS_LIST=$(echo "$STATE_CONTENT" | jq -r '.outputs.gcs_data_store_ids.value[], .outputs.bq_data_store_ids.value[]' 2>/dev/null)
    
    # Join with commas for the CLI argument
    ALL_IDS=$(echo "$ALL_IDS_LIST" | tr '\n' ',' | sed 's/,$//')
    
    if [[ -n "$ALL_IDS" ]]; then
        CMD="$CMD --data-stores $ALL_IDS"
    fi

    # 2. Extract Workforce Identity Details
    POOL_NAME=$(echo "$STATE_CONTENT" | jq -r '.outputs.acl_workforce_pool_name.value // empty')
    PROVIDER_ID=$(echo "$STATE_CONTENT" | jq -r '.outputs.acl_workforce_provider_id.value // empty')
    
    # Check IdP Type for debugging/validation
    IDP_TYPE=$(echo "$STATE_CONTENT" | jq -r '.outputs.acl_idp_type.value // empty')

    if [[ "$IDP_TYPE" == "THIRD_PARTY" ]]; then
        if [[ -z "$POOL_NAME" || -z "$PROVIDER_ID" ]]; then
             echo -e "${RED}Error: Third Party IdP selected but Pool/Provider details missing in state.${NC}"
             echo "Please ensure Stage 0 was deployed with Third Party configuration."
        fi
    fi
    
    if [[ -n "$POOL_NAME" && -n "$PROVIDER_ID" ]]; then
        # Extract Pool ID from full name (locations/global/workforcePools/POOL_ID)
        POOL_ID=$(basename "$POOL_NAME")
        CMD="$CMD --workforce-pool-id $POOL_ID --workforce-provider-id $PROVIDER_ID"
    fi


    echo "Running: $CMD"
    echo ""
    export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
    export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT_ID}"
    $CMD
    
    echo -e "${GREEN}Gemini Enterprise Application configured.${NC}"

    echo ""
    echo -e "${YELLOW}IMPORTANT NEXT STEPS:${NC}"
    echo -e "1. Take note of the ${GREEN}Gemini Enterprise Widget Config ID${NC} from the output above for the configuration of the Load Balancer.${NC}"
    echo -e "2. Setup DNS A Record that points the desired Gemini Enterprise subdomain (i.e. gemini.yourdomain.com) to the provisioned Load Balancer IP address (${GEMINI_IP})."
    echo -e "3. Provision an SSL Certificate and upload it to Google Cloud Certificate Manager (${YELLOW}Helper Functions > Upload SSL Certificate${NC})."
    echo -e "4. From the Main Menu select ${BLUE}Step 3 - Configure & Deploy Load Balancer / Access Policies (gemini-stage-1)${NC}."
    pause
}

update_app_compliance() {
    echo -e "${BLUE}--- Update Gemini Enterprise App Compliance ---${NC}"

    if ! ensure_gem4gov_installed; then
        return 1
    fi

    # Ensure Project ID is set
    if [[ -z "$PROJECT_ID" ]]; then
        echo -e "${RED}Project ID is required. Please select a project first.${NC}"
        return 1
    fi

    read -p "Enter Gemini Enterprise Engine ID: " ENGINE_ID
    if [[ -z "$ENGINE_ID" ]]; then
        echo -e "${RED}Engine ID is required.${NC}"
        return 1
    fi

    echo "Select Compliance Regime:"
    echo "1. FedRAMP High"
    echo "2. IL4"
    read -p "Select an option [1-2]: " COMPLIANCE_SEL

    COMPLIANCE_REGIME=""
    if [[ "$COMPLIANCE_SEL" == "1" ]]; then
        COMPLIANCE_REGIME="FEDRAMP_HIGH"
    elif [[ "$COMPLIANCE_SEL" == "2" ]]; then
        COMPLIANCE_REGIME="IL4"
    else
        echo -e "${RED}Invalid selection.${NC}"
        return 1
    fi

    CMD="gem4gov app update-compliance --project-id ${PROJECT_ID} --engine-id ${ENGINE_ID} --compliance-regime ${COMPLIANCE_REGIME}"
    
    echo "Running: $CMD"
    export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
    export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT_ID}"
    $CMD
    
    pause
}

# --- Helper Functions ---

upload_ssl_certificate() {
    echo -e "${BLUE}--- Upload SSL Certificate ---${NC}"
    
    # Ensure Project ID is set
    if [[ -z "$PROJECT_ID" ]]; then
        echo -e "${RED}Project ID is required. Please select a project first.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Requirements for Self-Managed SSL Certificates:${NC}"
    echo -e "1. Certificate and Key must be in ${BLUE}PEM format${NC}."
    echo -e "2. Private Key must ${RED}NOT${NC} be protected by a passphrase."
    echo -e "3. Encryption algorithm must be either ${BLUE}RSA${NC} or ${BLUE}ECDSA${NC}."
    echo -e "   - RSA-2048 or ECDSA P-256 are recommended."
    echo ""
    echo -e "For more details, see: https://docs.cloud.google.com/load-balancing/docs/ssl-certificates/self-managed-certs#create-key-and-cert"
    echo ""

    read -p "Enter Certificate Name (e.g., my-cert): " CERT_NAME
    if [[ -z "$CERT_NAME" ]]; then
        echo -e "${RED}Certificate Name is required.${NC}"
        return 1
    fi

    # Default region
    DEFAULT_REGION=${REGION:-"us-east4"}
    read -p "Enter Region [${DEFAULT_REGION}]: " INPUT_REGION
    CERT_REGION=${INPUT_REGION:-$DEFAULT_REGION}

    while true; do
        read -p "Enter path to Certificate File (.crt/.pem): " CERT_PATH
        # Expand tilde if present
        CERT_PATH="${CERT_PATH/#\~/$HOME}"
        if [[ -f "$CERT_PATH" ]]; then
            if grep -qE -e "-----BEGIN CERTIFICATE-----" "$CERT_PATH"; then
                break
            else
                echo -e "${RED}Error: File does not appear to be a PEM-formatted certificate (missing '-----BEGIN CERTIFICATE-----').${NC}"
            fi
        else
            echo -e "${RED}File not found: $CERT_PATH${NC}"
        fi
    done

    while true; do
        read -p "Enter path to Private Key File (.key/.pem): " KEY_PATH
        # Expand tilde if present
        KEY_PATH="${KEY_PATH/#\~/$HOME}"
        if [[ -f "$KEY_PATH" ]]; then
            if grep -qE -e "-----BEGIN .*PRIVATE KEY-----" "$KEY_PATH"; then
                break
            else
                echo -e "${RED}Error: File does not appear to be a PEM-formatted private key (missing '-----BEGIN ... PRIVATE KEY-----').${NC}"
            fi
        else
            echo -e "${RED}File not found: $KEY_PATH${NC}"
        fi
    done

    echo ""
    echo "Creating Regional SSL Certificate..."
    echo "Name: ${CERT_NAME}"
    echo "Region: ${CERT_REGION}"
    echo "Certificate: ${CERT_PATH}"
    echo "Key: ${KEY_PATH}"
    echo ""
    
    if gcloud compute ssl-certificates create "$CERT_NAME" \
        --certificate="$CERT_PATH" \
        --private-key="$KEY_PATH" \
        --region="$CERT_REGION" \
        --project="$PROJECT_ID"; then
        echo -e "${GREEN}SSL Certificate '${CERT_NAME}' created successfully!${NC}"
    else
        echo -e "${RED}Failed to create SSL Certificate.${NC}"
    fi
    
    pause
}

replace_gemini_app() {
    echo -e "${BLUE}--- Replace Gemini Enterprise Application / Load Balancer Routing ---${NC}"
    echo -e "${YELLOW}WARNING: This will create a NEW Gemini Enterprise Application and update the Load Balancer to route traffic to it.${NC}"
    echo -e "${YELLOW}The old application will NOT be deleted automatically.${NC}"
    echo ""
    read -p "Are you sure you want to proceed? (y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        return 0
    fi

    # 1. Create new App
    configure_gem4gov

    # 2. Update Networking (Stage 1)
    echo ""
    echo -e "${YELLOW}IMPORTANT: When prompted to 'Reuse existing configuration' for Stage 1, answer 'n' (No).${NC}"
    echo -e "${YELLOW}You MUST enter the NEW Gemini Enterprise Widget Config ID from the previous step.${NC}"
    echo ""
    pause

    configure_stage_1 || return 1
    deploy_stage_1
}

import_documents_helper() {
    echo ""
    echo -e "${BLUE}--- Import Documents into Data Store ---${NC}"

    if ! ensure_gem4gov_installed; then
        return 1
    fi
    
    # Ensure Project ID is set
    if [[ -z "$PROJECT_ID" ]]; then
        echo -e "${RED}Project ID is required. Please select a project first.${NC}"
        return 1
    fi

    # Ensure BUCKET_NAME is set from STATE_BUCKET if not already
    # This covers the case where the user navigates directly to this helper function
    if [[ -z "$BUCKET_NAME" && -n "$STATE_BUCKET" ]]; then
        BUCKET_NAME=$(echo "$STATE_BUCKET" | sed 's/gs:\/\/ //' | sed 's/\/$//')
    fi

    echo "Retrieving state from gs://${BUCKET_NAME}/terraform/state/stage-0/default.tfstate..."
    STATE_CONTENT=$(gcloud storage cat "gs://${BUCKET_NAME}/terraform/state/stage-0/default.tfstate" 2>/dev/null || echo "{}")

    # Parse GCS Data Stores
    # Output: gcs_data_store_to_bucket = { "ds-id": "bucket-name" }
    GCS_DS_MAP=$(echo "$STATE_CONTENT" | jq -r '.outputs.gcs_data_store_to_bucket.value // {}')

    # Parse BigQuery Data Stores
    # Output: bq_data_store_to_dataset_table = { "ds-id": { "dataset_id": "...", "table_id": "..." } }
    BQ_DS_MAP=$(echo "$STATE_CONTENT" | jq -r '.outputs.bq_data_store_to_dataset_table.value // {}')

    echo ""
    echo "Available Data Stores:"
    
    # Create arrays to store options
    DS_IDS=()
    DS_TYPES=()
    DS_SOURCES=()
    
    COUNT=0
    
    # List GCS Data Stores
    for key in $(echo "$GCS_DS_MAP" | jq -r 'keys[]'); do
        BUCKET=$(echo "$GCS_DS_MAP" | jq -r --arg k "$key" '.[$k]')
        COUNT=$((COUNT+1))
        echo "${COUNT}. [GCS] ${key} (Bucket: ${BUCKET})"
        DS_IDS+=("$key")
        DS_TYPES+=("gcs")
        DS_SOURCES+=("$BUCKET") # Store bucket name for display/verification if needed
    done

    # List BigQuery Data Stores
    for key in $(echo "$BQ_DS_MAP" | jq -r 'keys[]'); do
        DATASET=$(echo "$BQ_DS_MAP" | jq -r --arg k "$key" '.[$k].dataset_id')
        TABLE=$(echo "$BQ_DS_MAP" | jq -r --arg k "$key" '.[$k].table_id')
        COUNT=$((COUNT+1))
        echo "${COUNT}. [BigQuery] ${key} (Table: ${DATASET}.${TABLE})"
        DS_IDS+=("$key")
        DS_TYPES+=("bigquery")
        DS_SOURCES+=("${DATASET}.${TABLE}")
    done

    if [[ "$COUNT" -eq 0 ]]; then
        echo -e "${YELLOW}No data stores found in Stage 0 state.${NC}"
        pause
        return 0
    fi

    echo ""
    read -p "Select a Data Store to import into [1-${COUNT}]: " SELECTION

    if [[ ! "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt "$COUNT" ]]; then
        echo -e "${RED}Invalid selection.${NC}"
        pause
        return 1
    fi

    # valid selection (0-indexed array)
    INDEX=$((SELECTION-1))
    SELECTED_ID="${DS_IDS[$INDEX]}"
    SELECTED_TYPE="${DS_TYPES[$INDEX]}"
    
    echo -e "${GREEN}Selected: ${SELECTED_ID} (${SELECTED_TYPE})${NC}"
    echo ""

    CMD="gem4gov datastore import --project-id ${PROJECT_ID} --data-store-id ${SELECTED_ID} --source-type ${SELECTED_TYPE}"
    
    echo "Running: $CMD"
    export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
    export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT_ID}"
    $CMD
    
    pause
}

helper_menu() {
    while true; do
        clear
        print_header
        echo -e "${BLUE}--- Helper Functions ---${NC}"
        echo "1. Update Gemini Enterprise App Compliance"
        echo "2. Replace Gemini Enterprise Application / Load Balancer Routing"
        echo "3. Import Documents to Gemini Enterprise Data Store (Cloud Storage / BigQuery)"
        echo "4. Upload SSL Certificate"
        echo "5. Back to Main Menu"
        echo "-----------------------------------"
        read -p "Select an option [1-5]: " OPTION

        case $OPTION in
            1)
                update_app_compliance
                ;;
            2)
                replace_gemini_app
                ;;
            3)  
                import_documents_helper
                ;;
            4)
                upload_ssl_certificate
                ;;
            5)
                return 0
                ;;
            *)
                echo "Invalid option."
                pause
                ;;
        esac
    done
}

# --- Stage 1 Functions ---

configure_stage_1() {
    echo ""
    echo -e "${BLUE}--- Configure Stage 1 (Load Balancer / Access Policies) ---${NC}"
    mkdir -p gemini-stage-1
    
    if [[ -f "gemini-stage-1/terraform.tfvars" ]]; then
        read -p "Reuse existing configuration? (Y/n): " REUSE_CONFIG
        if [[ "$REUSE_CONFIG" != "n" && "$REUSE_CONFIG" != "N" ]]; then
            return 0
        fi
    fi

    # Retrieve Region from Stage 0 state if not set
    if [[ -z "$REGION" ]]; then
        echo "Retrieving region from state..."
        
        # Ensure BUCKET_NAME is set from STATE_BUCKET if not already
        if [[ -z "$BUCKET_NAME" && -n "$STATE_BUCKET" ]]; then
            BUCKET_NAME=$(echo "$STATE_BUCKET" | sed 's/gs:\/\/ //' | sed 's/\/$//')
        fi
        
        STATE_CONTENT=$(gcloud storage cat "gs://${BUCKET_NAME}/terraform/state/stage-0/default.tfstate" 2>/dev/null || echo "{}")
        REGION=$(echo "$STATE_CONTENT" | jq -r '.outputs.region.value // empty')
        
        if [[ -z "$REGION" ]]; then
             # Try to get it from the bucket location or default
             REGION="us-central1"
             echo -e "${YELLOW}Warning: Could not retrieve region from state. Using default: ${REGION}${NC}"
        else
             echo -e "Region retrieved: ${YELLOW}${REGION}${NC}"
        fi
    fi

    read -p "Enter Gemini Enterprise Domain (e.g., gemini.example.com): " GEMINI_DOMAIN
    
    # Validate DNS
    echo "Validating DNS for ${GEMINI_DOMAIN}..."
    if [[ -z "$STATE_CONTENT" ]]; then
        STATE_CONTENT=$(gcloud storage cat "gs://${BUCKET_NAME}/terraform/state/stage-0/default.tfstate" 2>/dev/null || echo "{}")
    fi
    
    LB_IP=$(echo "$STATE_CONTENT" | jq -r '.outputs.gemini_enterprise_ip.value // empty')
    
    if [[ -n "$LB_IP" ]]; then
        CURRENT_IP=$(dig +short "$GEMINI_DOMAIN" | grep "$LB_IP")
        if [[ -n "$CURRENT_IP" ]]; then
             echo -e "${GREEN}DNS Validation Successful: ${GEMINI_DOMAIN} resolves to ${LB_IP}${NC}"
        else
             RESOLVED_IPS=$(dig +short "$GEMINI_DOMAIN" | tr '\n' ' ')
             echo -e "${YELLOW}WARNING: DNS Validation Failed!${NC}"
             echo -e "Expected IP: ${LB_IP}"
             echo -e "Resolved IPs: ${RESOLVED_IPS:-None}"
             echo -e "${YELLOW}Please ensure your DNS A record is correctly pointing to ${LB_IP}.${NC}"
             read -p "Continue anyway? (y/N): " CONFIRM_DNS
             if [[ "$CONFIRM_DNS" != "y" && "$CONFIRM_DNS" != "Y" ]]; then
                 return 1
             fi
        fi
    else
        echo -e "${YELLOW}Warning: Could not retrieve Load Balancer IP from state. Skipping DNS validation.${NC}"
    fi
    
    # Auto-discover SSL Certificates
    echo ""
    echo "Discovering SSL Certificates in Region ${REGION}..."
    CERTS_JSON=$(gcloud compute ssl-certificates list --filter="region:(${REGION})" --format="json" 2>/dev/null)
    
    if [[ -n "$CERTS_JSON" && "$CERTS_JSON" != "[]" ]]; then
        echo "Available SSL Certificates:"
        echo "$CERTS_JSON" | jq -r '.[] | "\(.name) (\(.type))"' | nl -w2 -s") "
        
        read -p "Select an SSL Certificate [1]: " CERT_SEL
        CERT_SEL=${CERT_SEL:-1}
        
        SSL_CERT_NAME=$(echo "$CERTS_JSON" | jq -r ".[$((CERT_SEL-1))].name")
        echo -e "Selected Certificate: ${YELLOW}${SSL_CERT_NAME}${NC}"
    else
        echo -e "${YELLOW}No SSL Certificates found in region ${REGION}.${NC}"
        read -p "Enter SSL Certificate Name (must exist in GCP): " SSL_CERT_NAME
    fi

    read -p "Enter Gemini Widget Config ID (from Step 2 output): " GEMINI_CONFIG_ID
    
    cat > gemini-stage-1/terraform.tfvars <<EOF
stage_0_state_bucket = "${BUCKET_NAME}"
gemini_enterprise_domain = "${GEMINI_DOMAIN}"
ssl_certificate_name = "${SSL_CERT_NAME}"
gemini_config_id = "${GEMINI_CONFIG_ID}"
EOF

    # Add Shared VPC vars if needed (simple check)
    if [[ -n "$SHARED_VPC_NETWORK" ]]; then
        echo "network_name = \"${SHARED_VPC_NETWORK}\"" >> gemini-stage-1/terraform.tfvars
        echo "host_project_id = \"${SHARED_VPC_HOST_PROJECT}\"" >> gemini-stage-1/terraform.tfvars
    fi

    echo -e "${GREEN}Configuration generated in gemini-stage-1/terraform.tfvars${NC}"
    return 0
}

deploy_stage_1() {
    echo ""
    echo -e "${BLUE}--- Deploying Stage 1 ---${NC}"
    
    cd gemini-stage-1
    rm -f backend.tf
    
    echo "Initializing Terraform..."
    if ! terraform init -migrate-state -backend-config="bucket=${BUCKET_NAME}" -backend-config="prefix=terraform/state/stage-1"; then
        echo -e "${RED}Terraform Init failed! Please try resolving the error and running the Step again.${NC}"
        cd ..
        pause
        return 1
    fi
    
    echo ""
    echo "Applying Terraform..."
    if ! terraform apply -var-file="terraform.tfvars"; then
        echo -e "${RED}Terraform Apply failed! Please try resolving the error and running the Step again.${NC}"
        cd ..
        pause
        return 1
    fi
    
    cd ..
    echo -e "${GREEN}Stage 1 Deployment Complete!${NC}"
    
    # Post-Deployment: Third Party OAuth Setup
    # We need to check ACL_IDP_TYPE, but it might not be set if we just ran Stage 1.
    # We can try to read it from Stage 0 state if missing.
    if [[ -z "$ACL_IDP_TYPE" ]]; then
         STATE_CONTENT=$(gcloud storage cat "gs://${BUCKET_NAME}/terraform/state/stage-0/default.tfstate" 2>/dev/null || echo "{}")
         ACL_IDP_TYPE=$(echo "$STATE_CONTENT" | jq -r '.outputs.acl_idp_type.value // empty')
         ACL_POOL_NAME=$(echo "$STATE_CONTENT" | jq -r '.outputs.acl_workforce_pool_name.value // empty')
    fi

    if [[ "$ACL_IDP_TYPE" == "THIRD_PARTY" ]]; then
        echo ""
        echo -e "${YELLOW}ACTION REQUIRED: Complete the Identity-Aware Proxy (IAP) configuration manually.${NC}"
        echo -e "Because you selected THIRD_PARTY (Workforce Identity Federation), you must configure the OAuth Client and IAP settings manually."
        
        BACKEND_SERVICE_NAME="${PREFIX}-backend-service"

        echo ""
        echo -e "${YELLOW}Step 1: Create an OAuth Client${NC}"
        echo -e "1. Navigate to APIs & Services > Credentials: ${BLUE}https://console.cloud.google.com/apis/credentials?project=${PROJECT_ID}${NC}"
        echo "2. Click 'Create Credentials' > 'OAuth client ID'."
        echo "3. Application type: 'Web application'."
        echo "4. Name: 'Gemini Enterprise IAP Client'."
        echo "5. Click 'Create'. (Do not add redirect URIs yet)."
        echo "6. Copy the 'Client ID' and 'Client Secret'."
        echo -e "${NC}"
        read -p "Press Enter after you have created the client..."

        echo ""
        echo -e "${YELLOW}Step 2: Update Redirect URI${NC}"
        echo "1. Edit the newly created OAuth Client."
        echo -e "2. Add the following Authorized redirect URI (replace [CLIENT_ID] with the actual ID you just copied): ${BLUE}https://iap.googleapis.com/v1/oauth/clientIds/[CLIENT_ID]:handleRedirect${NC}"
        echo "3. Save the changes."
        echo -e "${NC}"
        read -p "Press Enter after you have updated the redirect URI..."

        echo ""
        echo -e "${YELLOW}Step 3: Configure IAP for Workforce Identity${NC}"
        echo -e "1. Navigate to IAP: ${BLUE}https://console.cloud.google.com/security/iap?project=${PROJECT_ID}${NC}"
        echo -e "2. Locate the Backend Service: ${GREEN}${BACKEND_SERVICE_NAME}${NC}"
        echo "3. Select the \"Settings\" in the 3-dots menu next to the backend service resource."
        echo "4. Select \"Custom OAuth (for specific control, branding, or external users)\" and configure the following:"
        echo "   - OAuth client ID: (Paste from Step 1)"
        echo "   - OAuth client secret: (Paste from Step 1)"
        echo "6. Click 'Save'."
        echo -e "${NC}"
        read -p "Press Enter after you have configured IAP..."
        echo ""
        echo -e "${GREEN}OAuth and IAP Manual Configuration marked as complete.${NC}"
    fi
    
    echo ""
    echo -e "Welcome to your ${BLUE}G${RED}o${YELLOW}o${BLUE}g${GREEN}l${RED}e${NC} Cloud Gemini Enterprise App! Access your app at ${BLUE}https://${GEMINI_DOMAIN}${NC}"
    pause
}

# --- Main Menu ---

main_menu() {
    while true; do
        clear
        print_header
        echo -e "Current Project: ${YELLOW}${PROJECT_ID:-None}${NC}"
        echo -e "Deployment Topology: ${YELLOW}${DEPLOYMENT_TYPE_TEXT:-None}${NC}"
        echo "-----------------------------------"
        echo -e "1. ${BLUE}Step 1${NC} - Configure & Deploy Infrastructure (gemini-stage-0)"
        echo -e "2. ${BLUE}Step 2${NC} - Create Gemini Enterprise App (gem4gov-cli)"
        echo -e "3. ${BLUE}Step 3${NC} - Configure & Deploy Load Balancer / Access Policies (gemini-stage-1)"
        echo -e "4. ${YELLOW}Helper Functions${NC}"
        echo -e "5. ${YELLOW}Re-select Deployment Topology / Project${NC}"
        echo -e "6. ${RED}Exit${NC}"
        echo "-----------------------------------"
        read -p "Select an option [1-6]: " OPTION

        case $OPTION in
            1)
                if [[ -z "$PROJECT_ID" ]]; then
                    echo -e "${RED}Please select a project first (Option 5).${NC}"
                    pause
                    continue
                fi
                configure_stage_0 || continue
                deploy_stage_0 || continue
                ;;
            2)
                if [[ -z "$PROJECT_ID" ]]; then
                    echo -e "${RED}Please select a project first (Option 5).${NC}"
                    pause
                    continue
                fi
                configure_gem4gov || continue
                ;;
            3)
                if [[ -z "$PROJECT_ID" ]]; then
                    echo -e "${RED}Please select a project first (Option 5).${NC}"
                    pause
                    continue
                fi
                configure_stage_1 || continue
                deploy_stage_1 || continue
                ;;
            4)
                helper_menu || continue
                ;;
            5)
                auth_and_project_setup || continue
                enable_apis || continue
                select_deployment_type || continue
                discover_infrastructure || continue
                ;;
            6)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option."
                pause
                ;;
        esac
    done
}

# --- Entry Point ---

check_dependencies
auth_and_project_setup
enable_apis
select_deployment_type
discover_infrastructure
main_menu
