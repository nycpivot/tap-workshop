#!/bin/bash

read -p "Full Domain Name: " full_domain

export EKS_CLUSTER_NAME=tap-full
export TANZU_CLI_NO_INIT=true
export TANZU_VERSION=v0.25.4
export TAP_VERSION=1.4.2

export TARGET_TBS_REPO=tap-build-service
export CLI_FILENAME=tanzu-framework-linux-amd64-v0.25.4.5.tar
export ESSENTIALS_FILENAME=tanzu-cluster-essentials-linux-amd64-1.4.1.tgz


# 1. CAPTURE PIVNET SECRETS
echo
echo "<<< RETRIEVING SECRETS FOR PIVNET >>>"
echo

pivnet_password=$(aws secretsmanager get-secret-value --secret-id $PIVNET_USERNAME | jq -r .SecretString | jq -r .\"pivnet_password\")
pivnet_token=$(aws secretsmanager get-secret-value --secret-id $PIVNET_USERNAME | jq -r .SecretString | jq -r .\"pivnet_token\")
token=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d '{"refresh_token":"'${pivnet_token}'"}')
access_token=$(echo ${token} | jq -r .access_token)

curl -i -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer ${access_token}" -X GET https://network.pivotal.io/api/v2/authentication


# 2. CLOUD FORMATION (VPC, EKS)
echo
echo "<<< RUNNING CLOUDFORMATION TEMPLATE >>>"
echo

eksctl create cluster --name $EKS_CLUSTER_NAME --managed --region $AWS_REGION --instance-types t3.xlarge --version 1.23 --with-oidc -N 3

rm .kube/config

arn=arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster

aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

kubectl config rename-context ${arn}/${EKS_CLUSTER_NAME} $EKS_CLUSTER_NAME

kubectl config use-context $EKS_CLUSTER_NAME


# 3. INSTALL CSI PLUGIN (REQUIRED FOR K8S 1.23+)
echo
echo "<<< INSTALLING CSI PLUGIN >>>"
echo

rolename=${EKS_CLUSTER_NAME}-csi-driver-role

aws iam detach-role-policy \
    --role-name ${rolename} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --no-cli-pager

aws iam delete-role --role-name ${rolename}

#https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html
aws eks create-addon \
    --cluster-name $EKS_CLUSTER_NAME \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/${rolename}" \
    --no-cli-pager

#https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
oidc_id=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | awk -F '/' '{print $5}')

# Check if a IAM OIDC provider exists for the cluster
# https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
if [[ -z $(aws iam list-open-id-connect-providers | grep $oidc_id) ]]; then
    echo "Creating IAM OIDC provider"
    if ! [ -x "$(command -v eksctl)" ]; then
    echo "Error `eksctl` CLI is required, https://eksctl.io/introduction/#installation" >&2
    exit 1
    fi

    eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve
fi

cat <<EOF | tee aws-ebs-csi-driver-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/oidc.eks.$AWS_REGION.amazonaws.com/id/$oidc_id"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.$AWS_REGION.amazonaws.com/id/$oidc_id:aud": "sts.amazonaws.com",
          "oidc.eks.$AWS_REGION.amazonaws.com/id/$oidc_id:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name $rolename \
  --assume-role-policy-document file://"aws-ebs-csi-driver-trust-policy.json" \
  --no-cli-pager

aws iam attach-role-policy \
  --role-name $rolename \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --no-cli-pager

kubectl annotate serviceaccount ebs-csi-controller-sa \
    -n kube-system --overwrite \
    eks.amazonaws.com/role-arn=arn:aws:iam::$AWS_ACCOUNT_ID:role/$rolename

rm aws-ebs-csi-driver-trust-policy.json


# 5. RBAC FOR ECR FROM EKS CLUSTER
echo
echo "<<< CREATING IAM ROLES FOR ECR >>>"
echo

export OIDCPROVIDER=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --region $AWS_REGION | jq '.cluster.identity.oidc.issuer' | tr -d '"' | sed 's/https:\/\///')

cat <<EOF > build-service-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$OIDCPROVIDER"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "$OIDCPROVIDER:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "$OIDCPROVIDER:sub": [
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
                "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/tap-build-service",
                "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/tap-images"
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
                "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$OIDCPROVIDER"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "$OIDCPROVIDER:sub": "system:serviceaccount:default:default",
                    "$OIDCPROVIDER:aud": "sts.amazonaws.com"
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
                "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/tap-build-service",
                "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/tanzu-application-platform/tanzu-java-web-app",
                "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/tanzu-application-platform/tanzu-java-web-app-bundle",
                "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/tanzu-application-platform",
                "arn:aws:ecr:$AWS_REGION:$AWS_ACCOUNT_ID:repository/tanzu-application-platform/*"
            ],
            "Effect": "Allow",
            "Sid": "TAPEcrWorkloadScoped"
        }
    ]
}
EOF

aws iam delete-role-policy --role-name tap-build-service --policy-name tapBuildServicePolicy --no-cli-pager
aws iam delete-role-policy --role-name tap-workload --policy-name tapWorkload --no-cli-pager

aws iam delete-role --role-name tap-build-service --no-cli-pager
aws iam delete-role --role-name tap-workload --no-cli-pager

# Create the Build Service Role
aws iam create-role --role-name tap-build-service --assume-role-policy-document file://build-service-trust-policy.json --no-cli-pager
aws iam put-role-policy --role-name tap-build-service --policy-name tapBuildServicePolicy --policy-document file://build-service-policy.json --no-cli-pager

# Create the Workload Role
aws iam create-role --role-name tap-workload --assume-role-policy-document file://workload-trust-policy.json --no-cli-pager
aws iam put-role-policy --role-name tap-workload --policy-name tapWorkload --policy-document file://workload-policy.json --no-cli-pager

rm build-service-trust-policy.json
rm build-service-policy.json
rm workload-trust-policy.json
rm workload-policy.json


# 6. TANZU PREREQS
echo
echo "<<< INSTALLING TANZU AND CLUSTER ESSENTIALS >>>"
echo

rm -rf $HOME/tanzu
mkdir $HOME/tanzu

wget https://network.pivotal.io/api/v2/products/tanzu-application-platform/releases/1260043/product_files/1433868/download --header="Authorization: Bearer $access_token" -O $HOME/tanzu/$CLI_FILENAME
tar -xvf $HOME/tanzu/$CLI_FILENAME -C $HOME/tanzu

cd tanzu

sudo install cli/core/$TANZU_VERSION/tanzu-core-linux_amd64 /usr/local/bin/tanzu

tanzu plugin install --local cli all

cd $HOME

#cluster essentials
rm -rf $HOME/tanzu-cluster-essentials
mkdir $HOME/tanzu-cluster-essentials

wget https://network.pivotal.io/api/v2/products/tanzu-cluster-essentials/releases/1249982/product_files/1423994/download --header="Authorization: Bearer $access_token" -O $HOME/tanzu-cluster-essentials/$ESSENTIALS_FILENAME
tar -xvf $HOME/tanzu-cluster-essentials/$ESSENTIALS_FILENAME -C $HOME/tanzu-cluster-essentials

export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:2354688e46d4bb4060f74fca069513c9b42ffa17a0a6d5b0dbb81ed52242ea44
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$PIVNET_USERNAME
export INSTALL_REGISTRY_PASSWORD=$pivnet_password

cd $HOME/tanzu-cluster-essentials

./install.sh --yes

sudo cp $HOME/tanzu-cluster-essentials/kapp /usr/local/bin/kapp
sudo cp $HOME/tanzu-cluster-essentials/imgpkg /usr/local/bin/imgpkg

cd $HOME

docker login registry.tanzu.vmware.com -u $PIVNET_USERNAME -p $pivnet_password

rm $HOME/tanzu/$CLI_FILENAME
rm $HOME/tanzu-cluster-essentials/$ESSENTIALS_FILENAME


# 7. IMPORT TAP PACKAGES
echo
echo "<<< IMPORTING TAP PACKAGES >>>"
echo

export INSTALL_REGISTRY_HOSTNAME=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
export INSTALL_REPO=tap-images

tap_images_ecr=$(aws ecr describe-repositories --query "repositories[?repositoryName=='tap-images'].repositoryName" --output text)
tap_build_service_ecr=$(aws ecr describe-repositories --query "repositories[?repositoryName=='tap-build-service'].repositoryName" --output text)

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $INSTALL_REGISTRY_HOSTNAME

if [[ -z $tap_images_ecr ]]
then
  aws ecr create-repository --repository-name $INSTALL_REPO --region $AWS_REGION --no-cli-pager
  imgpkg copy --concurrency 1 -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION --to-repo $INSTALL_REGISTRY_HOSTNAME/$INSTALL_REPO
fi

if [[ -z $tap_build_service_ecr ]]
then
  aws ecr create-repository --repository-name $TARGET_TBS_REPO --region $AWS_REGION --no-cli-pager
fi

kubectl create ns tap-install

tanzu package repository add tanzu-tap-repository \
  --url $INSTALL_REGISTRY_HOSTNAME/$INSTALL_REPO:$TANZU_VERSION \
  --namespace tap-install

#tanzu package repository get tanzu-tap-repository --namespace tap-install
#tanzu package available list --namespace tap-install
#tanzu package available list tap.tanzu.vmware.com --namespace tap-install

#INSTALL OOTB SUPPLY CHAIN - BASIC
bash $HOME/tap-workshop/full-profile/01-tap-full-eks-ootb-basic.sh
