#!/bin/bash

########################
# include the magic
########################
. demo-magic.sh

########################
# Configure the options
########################

#
# speed at which to simulate typing. bigger num = faster
#
TYPE_SPEED=15

#
# custom prompt
#
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
#DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "

# hide the evidence
clear

DEMO_PROMPT="${GREEN}➜ TAP ${CYAN}\W "

read -p "App Name: " app_name
echo

kubectl config get-contexts
echo

read -p "Select build context: " kube_context

git_app_url=https://github.com/nycpivot/${app_name}

kubectl config use-context $kube_context
echo

pe "tanzu apps workload list"
echo

pe "tanzu apps workload delete $app_name --yes"
echo

pe "aws ecr create-repository --repository-name tanzu-application-platform/$app_name-default --region $AWS_REGION_CODE"
pe "aws ecr create-repository --repository-name tanzu-application-platform/$app_name-default-bundle --region $AWS_REGION_CODE"
echo

pe "clear"

pe "tanzu apps workload create $app_name --git-repo ${git_app_url} --git-branch main --type web --annotation autoscaling.knative.dev/min-scale=2 --label app.kubernetes.io/part-of=$app_name --yes"
echo

pe "clear"

pe "tanzu apps workload tail $app_name --since 10m --timestamp"
echo

pe "tanzu apps workload list"
echo

pe "tanzu apps workload get $app_name"
echo

echo http://${app_name}.default.full.tap.nycpivot.com
