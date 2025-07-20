#!/bin/bash

# Script to generate GitHub secret set commands for arca-config repo
# based on secrets that exist in both MeetZaya's GitHub and .env file

DEST_REPO="matthewsinclair/arca-config"
ENV_FILE="/Users/matts/Devel/prj/MeetZaya/config/.env"

echo "#!/bin/bash"
echo "# Commands to set GitHub secrets for $DEST_REPO"
echo "# Generated from MeetZaya's .env file"
echo ""

# Define the secrets that exist in GitHub (from the list provided)
declare -A github_secrets=(
    ["ANTHROPIC_API_KEY"]=1
    ["ANTHROPIC_CLAUDE_SONET_MODEL_NAME"]=1
    ["FLY_API_TOKEN"]=1
    ["GH_RO_TO_MULTIPLYER_FOR_MEETZAYA"]=1
    ["HUGGING_FACE_TOKEN"]=1
    ["LINEAR_API_ZAYA_DEV"]=1
    ["MEETZAYA_CONFIG_FILE"]=1
    ["MEETZAYA_CONFIG_PATH"]=1
    ["OPENAI_API_KEY"]=1
    ["OPENAI_KEY"]=1
    ["OPENAI_ORGANIZATION_KEY"]=1
    ["OPENAI_ORG_ID"]=1
    ["TOKEN_SIGNING_SECRET"]=1
    ["VIX_LOG_ERROR"]=1
)

# Read the .env file and generate commands
while IFS='=' read -r key value; do
    # Skip empty lines and comments
    if [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Trim whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    
    # Remove quotes from value if present
    value="${value%\"}"
    value="${value#\"}"
    
    # Check if this key exists in the GitHub secrets list
    if [[ -n "${github_secrets[$key]}" ]]; then
        echo "echo \"Setting $key...\""
        echo "gh secret set $key --repo $DEST_REPO --body \"$value\""
        echo ""
    fi
done < "$ENV_FILE"

# Handle special mappings (OPENAI_KEY -> OPENAI_API_KEY if needed)
echo "# Note: OPENAI_KEY in .env maps to OPENAI_API_KEY in GitHub"
echo "# Note: OPENAI_ORG_ID in .env maps to OPENAI_ORGANIZATION_KEY in GitHub"

echo ""
echo "echo \"All secrets have been set!\""