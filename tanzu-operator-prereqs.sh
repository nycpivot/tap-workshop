#!/bin/bash

read -p "AWS Account Id: " aws_account_id
read -p "AWS Access Key Id: " aws_access_key_id
read -p "AWS Secret Access Key: " aws_secret_access_key
read -p "AWS Default Region: " aws_region_code
read -p "Pivnet Username: " pivnet_username
read -p "Pivnet Password: " pivnet_password
read -p "Pivnet API Token: " pivnet_token
read -p "Github CLI Token: " github_token

sudo apt update
yes | sudo apt upgrade

#DOCKER
yes | sudo apt install docker.io
sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker $USER

#MISC TOOLS
sudo snap install jq
sudo snap install tree
sudo snap install helm --classic
sudo apt install unzip

sudo apt install python-is-python3
alias python=python3

yes | sudo apt install python3-pip
pip3 install yq

wget https://releases.hashicorp.com/terraform/0.13.0/terraform_0.13.0_linux_amd64.zip
unzip terraform_0.13.0_linux_amd64.zip
sudo mv terraform /usr/local/bin
rm terraform_0.13.0_linux_amd64.zip

#AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip

#AWS AUTHENTICATOR
curl -Lo aws-iam-authenticator https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v0.5.9/aws-iam-authenticator_0.5.9_linux_amd64
sudo mv aws-iam-authenticator /usr/local/bin
chmod +x /usr/local/bin/aws-iam-authenticator

#AWS EKSCTL
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
chmod +x /usr/local/bin/eksctl

aws configure set aws_access_key_id $aws_access_key_id
aws configure set aws_secret_access_key $aws_secret_access_key
aws configure set default.region $aws_region_code

echo cli_pager= >> $HOME/.aws/config


#KUBECTL
wget https://tanzustorage.blob.core.windows.net/tanzu/kubectl-linux-v1.22.5+vmware.1.gz
gunzip kubectl-linux-v1.22.5+vmware.1.gz

sudo install kubectl-linux-v1.22.5+vmware.1 /usr/local/bin/kubectl
rm kubectl-linux-v1.22.5+vmware.1
kubectl version


#DEMO-MAGIC
wget https://raw.githubusercontent.com/paxtonhare/demo-magic/master/demo-magic.sh
sudo mv demo-magic.sh /usr/local/bin/demo-magic.sh
chmod +x /usr/local/bin/demo-magic.sh

sudo apt install pv #required for demo-magic


echo
echo export AWS_ACCOUNT_ID=$aws_account_id >> .bashrc
echo
echo export AWS_REGION=$aws_region_code >> .bashrc
echo
echo export PIVNET_USERNAME=$pivnet_username >> .bashrc
echo

rm secrets.json
cat <<EOF | tee secrets.json
{
    "pivnet_password": "$pivnet_password",
    "pivnet_token": "$pivnet_token",
    "github_token": "$github_token
}
EOF

aws secretsmanager delete-secret --secret-id $pivnet_username --region $aws_region_code --force-delete-without-recovery
aws secretsmanager create-secret --name $pivnet_username --secret-string file://secrets.json

echo
echo "***REBOOTING***"
echo

sudo reboot
