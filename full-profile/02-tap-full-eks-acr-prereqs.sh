#!/bin/bash

export TAP_VERSION=1.5.0
export TARGET_REGISTRY_USERNAME=tanzuapplicationplatform
export TARGET_REGISTRY_HOSTNAME=tanzuapplicationplatform.azurecr.io

export TARGET_REGISTRY_PASSWORD=$(aws secretsmanager get-secret-value --secret-id tap-workshop | jq -r .SecretString | jq -r .\"acr-secret\")

export PIVNET_USERNAME=$(aws secretsmanager get-secret-value --secret-id tap-workshop | jq -r .SecretString | jq -r .\"pivnet-username\")
export PIVNET_PASSWORD=$(aws secretsmanager get-secret-value --secret-id tap-workshop | jq -r .SecretString | jq -r .\"pivnet-password\")
export PIVNET_TOKEN=$(aws secretsmanager get-secret-value --secret-id tap-workshop | jq -r .SecretString | jq -r .\"pivnet-token\")

token=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d '{"refresh_token":"'$PIVNET_TOKEN'"}')
access_token=$(echo ${token} | jq -r .access_token)

curl -i -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $access_token" -X GET https://network.pivotal.io/api/v2/authentication


# IMPORT TAP IMAGES
echo
echo "<<< IMPORTING TAP IMAGES >>>"
echo

docker login $TARGET_REGISTRY_HOSTNAME -u $TARGET_REGISTRY_USERNAME -p $TARGET_REGISTRY_PASSWORD

imgpkg copy --concurrency 1 -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${TAP_VERSION} --to-repo ${TARGET_REGISTRY_HOSTNAME}/tap-packages

tanzu secret registry add tap-registry \
  --username ${TARGET_REGISTRY_USERNAME} --password ${TARGET_REGISTRY_PASSWORD} \
  --server ${TARGET_REGISTRY_HOSTNAME} \
  --export-to-all-namespaces --yes --namespace tap-install

tanzu package repository add tanzu-tap-repository \
  --url ${INSTALL_REGISTRY_HOSTNAME}/${TARGET_REPOSITORY}/tap-packages:$TAP_VERSION \
  --namespace tap-install



