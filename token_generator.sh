#!/bin/bash

set -e

# Step 1: Download and install Aliyun CLI
# echo "Downloading Aliyun CLI..."
# curl -L -o aliyun-cli.tgz https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz

# echo "Extracting Aliyun CLI..."
# tar -zxvf aliyun-cli.tgz

# Step 2: Configure Aliyun CLI using OIDC
OIDC_PROVIDER_ARN=${ALIBABA_CLOUD_OIDC_PROVIDER_ARN} # Injected by Kubernetes
OIDC_TOKEN_FILE=${ALIBABA_CLOUD_OIDC_TOKEN_FILE} # Injected by Kubernetes
RAM_ROLE_ARN=${ALIBABA_CLOUD_ROLE_ARN} # Injected by Kubernetes
REGION=${REGION} # Injected by Kubernetes
INSTANCE_NAME=${ACR_INSTANCE_NAME} # Injected by Kubernetes
MODE=${CLI_MODE:-"OIDC"}
ACCESS_KEY_ID=${ALIBABA_CLOUD_ACCESS_KEY_ID} # Injected by Kubernetes
ACCESS_KEY_SECRET=${ALIBABA_CLOUD_ACCESS_KEY_SECRET} # Injected by Kubernetes

echo "Configuring Aliyun CLI..."
if [ "$MODE" == "OIDC" ]; then
  PROFILE="OIDCProfile"
  aliyun configure set \
    --profile $PROFILE \
    --mode OIDC \
    --oidc-provider-arn "$OIDC_PROVIDER_ARN" \
    --oidc-token-file "$OIDC_TOKEN_FILE" \
    --ram-role-arn "$RAM_ROLE_ARN" \
    --role-session-name acr-token-generator \
    --region "$REGION"
elif [ "$MODE" == "KV" ]; then
  PROFILE="KVProfile"
  # Add configuration for KV mode here
  echo "Configuring Aliyun CLI for KV mode..."
  aliyun configure set \
    --profile $PROFILE \
    --mode AK \
    --access-key-id "$ACCESS_KEY_ID" \
    --access-key-secret "$ACCESS_KEY_SECRET" \
    --region "$REGION"
else
  echo "Mode $MODE is not supported."
  exit 1
fi

# Step 3: Retrieve the authorization token
INSTANCE_ID=${ACR_INSTANCE_ID} # Replace with your actual Instance ID
echo "Retrieving authorization token..."
response=$(aliyun cr GetAuthorizationToken --region "$REGION" --InstanceId "$INSTANCE_ID" --profile $PROFILE)

# Step 4: Parse the response and write the token to Docker config JSON file
AUTH_TOKEN=$(echo "$response" | jq -r '.AuthorizationToken')
AUTH_USER=$(echo "$response" | jq -r '.TempUsername')
DOCKER_CONFIG_JSON=$(cat <<EOF
{
  "auths": {
    "$INSTANCE_NAME-registry-vpc.$REGION.cr.aliyuncs.com": {
      "username": "$AUTH_USER",
      "password": "$AUTH_TOKEN",
      "email": "cr@aliyun.com",
      "provider": null
    },
    "$INSTANCE_NAME-registry.$REGION.cr.aliyuncs.com": {
      "username": "$AUTH_USER",
      "password": "$AUTH_TOKEN",
      "email": "cr@aliyun.com",
      "provider": null
    }
  }
}
EOF
)

# Step 5: Create Kubernetes secret from the Docker config file using curl
SECRET_NAME=${ACR_SECRET_NAME} # Choose a name for the secret
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace) # Get the namespace from the mounted service account
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

SECRET_PAYLOAD=$(cat <<EOF
{
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "$SECRET_NAME",
    "namespace": "$NAMESPACE"
  },
  "type": "kubernetes.io/dockerconfigjson",
  "data": {
    ".dockerconfigjson": "$(echo "$DOCKER_CONFIG_JSON" | base64 | tr -d '\n')",
    "config.json": "$(echo "$DOCKER_CONFIG_JSON" | base64 | tr -d '\n')"
  }
}
EOF
)

# Check if the secret exists
SECRET_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  --insecure \
  "https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/secrets/$SECRET_NAME")

if [ "$SECRET_EXISTS" -eq 200 ]; then
  echo "Secret $SECRET_NAME exists. Updating the secret..."

  # Update the secret
  curl -s -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "$SECRET_PAYLOAD" \
    "https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/secrets/$SECRET_NAME" \
    --insecure # Use --insecure if you do not have CA certificates in the pod
  
  echo "Secret $SECRET_NAME updated successfully."
else
  echo "Secret $SECRET_NAME does not exist. Creating a new secret..."

  KUBE_API="https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/secrets"
  curl -X POST "$KUBE_API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    --data "$SECRET_PAYLOAD" \
    --insecure # Use --insecure if you do not have CA certificates in the pod
  
  echo "Secret $SECRET_NAME created successfully."
fi
