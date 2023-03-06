#!/bin/bash

read -p "DNS Zone Id: " hosted_zone_id
read -p "Full Domain Name: " full_domain

tap_version=1.4.1
tap_full_cluster=tap-full

target_registry=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION_CODE.amazonaws.com
target_repo=tap-images
target_tbs_repo=tap-build-service
git_catalog_repository=tanzu-application-platform

cli_filename=tanzu-framework-linux-amd64-v0.25.4.1.tar
essentials_filename=tanzu-cluster-essentials-linux-amd64-1.4.0.tgz
export TANZU_CLI_NO_INIT=true
export VERSION=v0.25.4


# 1. PIVNET SECRETS
pivnet_password=$(aws secretsmanager get-secret-value --secret-id $PIVNET_USERNAME | jq -r .SecretString | jq -r .\"pivnet_password\")
pivnet_token=$(aws secretsmanager get-secret-value --secret-id $PIVNET_USERNAME | jq -r .SecretString | jq -r .\"pivnet_token\")
token=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d '{"refresh_token":"'${pivnet_token}'"}')
access_token=$(echo ${token} | jq -r .access_token)

curl -i -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer ${access_token}" -X GET https://network.pivotal.io/api/v2/authentication


# 2. CLOUD FORMATION (VPC, EKS)
aws cloudformation create-stack --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE --template-body file:///home/ubuntu/tap-workshop/full-profile/config/tap-singlecluster-stack.yaml
aws cloudformation wait stack-create-complete --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE

#eksctl create cluster --name $tap_full_cluster --managed --region $aws_region_code --instance-types t3.xlarge --version 1.23 --with-oidc -N 5


# 3. UPDATE KUBECONFIG
arn=arn:aws:eks:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:cluster

aws eks update-kubeconfig --name $tap_full_cluster --region $AWS_REGION_CODE

kubectl config rename-context ${arn}/${tap_full_cluster} $tap_full_cluster

kubectl config use-context $tap_full_cluster


#INSTALL CSI PLUGIN
rolename=${tap_full_cluster}-csi-driver-role

aws iam detach-role-policy \
    --role-name ${rolename} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
    
aws iam delete-role --role-name ${rolename}

#https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html
#INSTALL CSI DRIVER PLUGIN (REQUIRED FOR K8S 1.23)
#aws eks delete-addon \
#    --cluster-name $tap_full_cluster \
#    --addon-name aws-ebs-csi-driver

aws eks create-addon \
    --cluster-name $tap_full_cluster \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${rolename}"

#https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
aws eks describe-cluster --name $tap_full_cluster --query "cluster.identity.oidc.issuer" --output text

#https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
oidc_id=$(aws eks describe-cluster --name $tap_full_cluster --query "cluster.identity.oidc.issuer" --output text | awk -F '/' '{print $5}')

# Check if a IAM OIDC provider exists for the cluster
# https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
if [[ -z $(aws iam list-open-id-connect-providers | grep $oidc_id) ]]; then
    echo "Creating IAM OIDC provider"
    if ! [ -x "$(command -v eksctl)" ]; then
    echo "Error `eksctl` CLI is required, https://eksctl.io/introduction/#installation" >&2
    exit 1
    fi

    eksctl utils associate-iam-oidc-provider --cluster $tap_full_cluster --approve
fi

cat <<EOF | tee aws-ebs-csi-driver-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION_CODE}.amazonaws.com/id/${oidc_id}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${AWS_REGION_CODE}.amazonaws.com/id/${oidc_id}:aud": "sts.amazonaws.com",
          "oidc.eks.${AWS_REGION_CODE}.amazonaws.com/id/${oidc_id}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name $rolename \
  --assume-role-policy-document file://"aws-ebs-csi-driver-trust-policy.json"
  
aws iam attach-role-policy \
  --role-name $rolename \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
  
kubectl annotate serviceaccount ebs-csi-controller-sa \
    -n kube-system --overwrite \
    eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${rolename}

rm aws-ebs-csi-driver-trust-policy.json


#CREATE ECRs
#aws ecr create-repository --repository-name tap-images --region $aws_region_code
#aws ecr create-repository --repository-name tap-build-service --region $aws_region_code

#RBAC FOR ECR
oidcProvider=$(aws eks describe-cluster --name $tap_full_cluster --region $AWS_REGION_CODE | jq '.cluster.identity.oidc.issuer' | tr -d '"' | sed 's/https:\/\///')

cat <<EOF > build-service-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${oidcProvider}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${oidcProvider}:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "${oidcProvider}:sub": [
                        "system:serviceaccount:kpack:controller",
                        "system:serviceaccount:build-service:dependency-updater-controller-serviceaccount"
                    ]
                }
            }
        }
    ]
}
EOF

cat <<EOF > build-service-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ecr:DescribeRegistry",
                "ecr:GetAuthorizationToken",
                "ecr:GetRegistryPolicy",
                "ecr:PutRegistryPolicy",
                "ecr:PutReplicationConfiguration",
                "ecr:DeleteRegistryPolicy"
            ],
            "Resource": "*",
            "Effect": "Allow",
            "Sid": "TAPEcrBuildServiceGlobal"
        },
        {
            "Action": [
                "ecr:DescribeImages",
                "ecr:ListImages",
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:BatchGetRepositoryScanningConfiguration",
                "ecr:DescribeImageReplicationStatus",
                "ecr:DescribeImageScanFindings",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:GetRegistryScanningConfiguration",
                "ecr:GetRepositoryPolicy",
                "ecr:ListTagsForResource",
                "ecr:TagResource",
                "ecr:UntagResource",
                "ecr:BatchDeleteImage",
                "ecr:BatchImportUpstreamImage",
                "ecr:CompleteLayerUpload",
                "ecr:CreatePullThroughCacheRule",
                "ecr:CreateRepository",
                "ecr:DeleteLifecyclePolicy",
                "ecr:DeletePullThroughCacheRule",
                "ecr:DeleteRepository",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:PutImageScanningConfiguration",
                "ecr:PutImageTagMutability",
                "ecr:PutLifecyclePolicy",
                "ecr:PutRegistryScanningConfiguration",
                "ecr:ReplicateImage",
                "ecr:StartImageScan",
                "ecr:StartLifecyclePolicyPreview",
                "ecr:UploadLayerPart",
                "ecr:DeleteRepositoryPolicy",
                "ecr:SetRepositoryPolicy"
            ],
            "Resource": [
                "arn:aws:ecr:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:repository/tap-build-service",
                "arn:aws:ecr:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:repository/tap-images"
            ],
            "Effect": "Allow",
            "Sid": "TAPEcrBuildServiceScoped"
        }
    ]
}
EOF

cat <<EOF > workload-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${oidcProvider}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${oidcProvider}:sub": "system:serviceaccount:default:default",
                    "${oidcProvider}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

cat <<EOF > workload-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ecr:DescribeRegistry",
                "ecr:GetAuthorizationToken",
                "ecr:GetRegistryPolicy",
                "ecr:PutRegistryPolicy",
                "ecr:PutReplicationConfiguration",
                "ecr:DeleteRegistryPolicy"
            ],
            "Resource": "*",
            "Effect": "Allow",
            "Sid": "TAPEcrWorkloadGlobal"
        },
        {
            "Action": [
                "ecr:DescribeImages",
                "ecr:ListImages",
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:BatchGetRepositoryScanningConfiguration",
                "ecr:DescribeImageReplicationStatus",
                "ecr:DescribeImageScanFindings",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:GetRegistryScanningConfiguration",
                "ecr:GetRepositoryPolicy",
                "ecr:ListTagsForResource",
                "ecr:TagResource",
                "ecr:UntagResource",
                "ecr:BatchDeleteImage",
                "ecr:BatchImportUpstreamImage",
                "ecr:CompleteLayerUpload",
                "ecr:CreatePullThroughCacheRule",
                "ecr:CreateRepository",
                "ecr:DeleteLifecyclePolicy",
                "ecr:DeletePullThroughCacheRule",
                "ecr:DeleteRepository",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:PutImageScanningConfiguration",
                "ecr:PutImageTagMutability",
                "ecr:PutLifecyclePolicy",
                "ecr:PutRegistryScanningConfiguration",
                "ecr:ReplicateImage",
                "ecr:StartImageScan",
                "ecr:StartLifecyclePolicyPreview",
                "ecr:UploadLayerPart",
                "ecr:DeleteRepositoryPolicy",
                "ecr:SetRepositoryPolicy"
            ],
            "Resource": [
                "arn:aws:ecr:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:repository/tap-build-service",
                "arn:aws:ecr:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform/tanzu-java-web-app",
                "arn:aws:ecr:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform/tanzu-java-web-app-bundle",
                "arn:aws:ecr:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform",
                "arn:aws:ecr:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform/*"
            ],
            "Effect": "Allow",
            "Sid": "TAPEcrWorkloadScoped"
        }
    ]
}
EOF

aws iam delete-role-policy --role-name tap-build-service --policy-name tapBuildServicePolicy
aws iam delete-role-policy --role-name tap-workload --policy-name tapWorkload

aws iam delete-role --role-name tap-build-service
aws iam delete-role --role-name tap-workload

# Create the Build Service Role
aws iam create-role --role-name tap-build-service --assume-role-policy-document file://build-service-trust-policy.json
aws iam put-role-policy --role-name tap-build-service --policy-name tapBuildServicePolicy --policy-document file://build-service-policy.json

# Create the Workload Role
aws iam create-role --role-name tap-workload --assume-role-policy-document file://workload-trust-policy.json
aws iam put-role-policy --role-name tap-workload --policy-name tapWorkload --policy-document file://workload-policy.json

rm build-service-trust-policy.json
rm build-service-policy.json
rm workload-trust-policy.json
rm workload-policy.json


#TANZU PREREQS
rm -rf $HOME/tanzu
mkdir $HOME/tanzu

wget https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1250091/product_files/1423948/download --header="Authorization: Bearer ${access_token}" -O $HOME/tanzu/${cli_filename}
tar -xvf $HOME/tanzu/${cli_filename} -C $HOME/tanzu

cd tanzu

sudo install cli/core/$VERSION/tanzu-core-linux_amd64 /usr/local/bin/tanzu

tanzu plugin install --local cli all
#tanzu plugin list

cd $HOME

#CLUSTER ESSENTIALS
rm -rf $HOME/tanzu-cluster-essentials
mkdir $HOME/tanzu-cluster-essentials

wget https://network.tanzu.vmware.com/api/v2/products/tanzu-cluster-essentials/releases/1249982/product_files/1423994/download --header="Authorization: Bearer ${access_token}" -O $HOME/tanzu-cluster-essentials/${essentials_filename}
tar -xvf $HOME/tanzu-cluster-essentials/${essentials_filename} -C $HOME/tanzu-cluster-essentials

export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:54bf611711923dccd7c7f10603c846782b90644d48f1cb570b43a082d18e23b9
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$PIVNET_USERNAME
export INSTALL_REGISTRY_PASSWORD=$pivnet_password
cd $HOME/tanzu-cluster-essentials

./install.sh --yes

sudo cp $HOME/tanzu-cluster-essentials/kapp /usr/local/bin/kapp
sudo cp $HOME/tanzu-cluster-essentials/imgpkg /usr/local/bin/imgpkg

cd $HOME

docker login registry.tanzu.vmware.com -u $PIVNET_USERNAME -p $pivnet_password

rm $HOME/tanzu/${cli_filename}
rm $HOME/tanzu-cluster-essentials/${essentials_filename}


#IMPORT TAP PACKAGES
aws ecr get-login-password --region $AWS_REGION_CODE | docker login --username AWS --password-stdin $target_registry

imgpkg copy --concurrency 1 -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:${tap_version} --to-repo ${target_registry}/${target_repo}

kubectl create ns tap-install

tanzu package repository add tanzu-tap-repository \
  --url ${target_registry}/${target_repo}:$tap_version \
  --namespace tap-install

#tanzu package repository get tanzu-tap-repository --namespace tap-install
#tanzu package available list --namespace tap-install
#tanzu package available list tap.tanzu.vmware.com --namespace tap-install

#INSTALL FULL TAP PROFILE
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=mjames@pivotal.io
export INSTALL_REGISTRY_PASSWORD=$pivnet_password

#APPEND GUI SETTINGS
rm tap-values-full.yaml
cat <<EOF | tee tap-values-full.yaml
profile: full
ceip_policy_disclosed: true
shared:
  ingress_domain: "${full_domain}"
buildservice:
  kp_default_repository: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION_CODE}.amazonaws.com/${target_tbs_repo}
  # Enable the build service k8s service account to bind to the AWS IAM Role
  kp_default_repository_aws_iam_role_arn: "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${target_tbs_repo}"
supply_chain: basic
ootb_supply_chain_basic:
  registry:
    server: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION_CODE}.amazonaws.com
    repository: "tanzu-application-platform"
  gitops:
    ssh_secret: ""
  cluster_builder: default
  service_account: default
tap_gui:
  service_type: LoadBalancer
  app_config:
    app:
      baseUrl: http://tap-gui.${full_domain}
    catalog:
      locations:
        - type: url
          target: https://github.com/nycpivot/${git_catalog_repository}/catalog-info.yaml
learningcenter:
  ingressDomain: "learningcenter.full.tap.nycpivot.com"
metadata_store:
  app_service_type: LoadBalancer
scanning:
  metadataStore:
    url: ""
grype:
  namespace: "default"
  targetImagePullSecret: "registry-credentials"
contour:
  infrastructure_provider: aws
  envoy:
    service:
      aws:
        LBType: nlb
cnrs:
  domain_name: $full_domain
policy:
  tuf_enabled: false
EOF

tanzu package install tap -p tap.tanzu.vmware.com -v $tap_version --values-file tap-values-full.yaml -n tap-install
#tanzu package installed get tap -n tap-install
#tanzu package installed list -A


#DEVELOPER NAMESPACE
tanzu secret registry add registry-credentials --server ${target_registry} --username "AWS" --password "${target_registry}" --namespace default

cat <<EOF | kubectl -n default apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
secrets:
  - name: registry-credentials
imagePullSecrets:
  - name: registry-credentials
  - name: tap-registry
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


# CONFIGURE DNS NAME WITH ELB IP
kubectl get svc -n tanzu-system-ingress

read -p "Tanzu System Ingress IP: " external_ip

nslookup $external_ip
read -p "IP Address: " ip_address

rm change-batch.json
cat <<EOF | tee change-batch.json
{
    "Comment": "Update IP address.",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "*.${full_domain}",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "${ip_address}"
                    }
                ]
            }
        }
    ]
}
EOF

aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch file:///$HOME/change-batch.json

echo
echo http://tap-gui.${full_domain}
echo
echo "HAPPY TAP'ING"
echo
