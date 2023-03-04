#!/bin/bash

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

#AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip




read -p "AWS Region Code: " aws_region_code

aws cloudformation create-stack --region $aws_region_code --stack-name tap-workshop-singlecluster-stack --template-body file:///home/ubuntu/tap-workshop/full-profile/config/tap-singlecluster-stack.yaml
