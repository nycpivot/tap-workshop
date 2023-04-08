#!/bin/bash

FULL_DOMAIN=$(cat /tmp/tap-full-domain)

TAP_VERSION=1.4.2
GIT_CATALOG_REPOSITORY=tanzu-application-platform
INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com

# 1. CAPTURE PIVNET SECRETS
pivnet_password=$(aws secretsmanager get-secret-value --secret-id $PIVNET_USERNAME | jq -r .SecretString | jq -r .\"pivnet_password\")
pivnet_token=$(aws secretsmanager get-secret-value --secret-id $PIVNET_USERNAME | jq -r .SecretString | jq -r .\"pivnet_token\")
token=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d '{"refresh_token":"'$pivnet_token'"}')
access_token=$(echo ${token} | jq -r .access_token)

curl -i -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $access_token" -X GET https://network.pivotal.io/api/v2/authentication


# 8. INSTALL FULL TAP PROFILE
echo
echo "<<< INSTALLING FULL TAP PROFILE >>>"
echo

#DELETE TESTING & SCANNING PACKAGE FIRST (IF IT'S THERE)
tanzu package installed delete ootb-supply-chain-testing --namespace tap-install --yes
tanzu package installed delete ootb-supply-chain-testing-scanning --namespace tap-install --yes

#INSTALL TAP
rm tap-values-full-ootb-basic.yaml
cat <<EOF | tee tap-values-full-ootb-basic.yaml
profile: full
ceip_policy_disclosed: true
shared:
  ingress_domain: "$FULL_DOMAIN"
supply_chain: basic
ootb_supply_chain_basic:
  registry:
    server: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    repository: "tanzu-application-platform"
buildservice:
  kp_default_repository: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$TARGET_TBS_REPO
  kp_default_repository_aws_iam_role_arn: "arn:aws:iam::$AWS_ACCOUNT_ID:role/$TARGET_TBS_REPO"
contour:
  infrastructure_provider: aws
  envoy:
    service:
      aws:
        LBType: nlb
ootb_templates:
  iaas_auth: true
tap_gui:
  service_type: LoadBalancer
  app_config:
    catalog:
      locations:
        - type: url
          target: https://github.com/nycpivot/$GIT_CATALOG_REPOSITORY/catalog-info.yaml
metadata_store:
  ns_for_export_app_cert: "default"
  app_service_type: LoadBalancer
scanning:
  metadataStore:
    url: ""
grype:
  namespace: "default"
  targetImagePullSecret: "registry-credentials"
cnrs:
  domain_name: $FULL_DOMAIN
excluded_packages:
  - policy.apps.tanzu.vmware.com
EOF

tanzu package installed delete tap -n tap-install --yes
tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file tap-values-full-ootb-basic.yaml -n tap-install

sleep 300

# 9. DEVELOPER NAMESPACE
#https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/1.4/tap/scc-ootb-supply-chain-basic.html
echo
echo "<<< CREATING DEVELOPER NAMESPACE >>>"
echo

tanzu secret registry add registry-credentials \
  --server $INSTALL_REGISTRY_HOSTNAME \
  --username "AWS" \
  --password "$INSTALL_REGISTRY_HOSTNAME" \
  --namespace default

cat <<EOF | kubectl -n default apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::$AWS_ACCOUNT_ID:role/tap-workload"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-deliverable
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deliverable
subjects:
  - kind: ServiceAccount
    name: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-workload
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workload
subjects:
  - kind: ServiceAccount
    name: default
EOF


# 10. CONFIGURE DNS NAME WITH ELB IP
echo
echo "<<< CONFIGURING DNS >>>"
echo

ingress=$(kubectl get svc envoy -n tanzu-system-ingress -o json | jq -r .status.loadBalancer.ingress[].hostname)
ip_address=$(nslookup $ingress | awk '/^Address:/ {A=$2}; END {print A}')

rm change-batch.json
cat <<EOF | tee change-batch.json
{
    "Comment": "Update IP address.",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "*.$FULL_DOMAIN",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "$ip_address"
                    }
                ]
            }
        }
    ]
}
EOF
echo

hosted_zone_id=$(aws route53 list-hosted-zones --query HostedZones[0].Id --output text | awk -F '/' '{print $3}')
aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch file:///$HOME/change-batch.json

echo
echo http://tap-gui.$FULL_DOMAIN
echo
echo "HAPPY TAP'ING"
echo
