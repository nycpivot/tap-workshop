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
TYPE_SPEED=20

#
# custom prompt
#
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
#DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "

# hide the evidence
clear

DEMO_PROMPT="${GREEN}➜ TAP ${CYAN}\W "

app_name=tanzu-crossplane-petclinic
#read -p "App Name: " app_name
#echo

kubectl config get-contexts
echo

read -p "Select build context: " kube_context

git_app_url=https://github.com/nycpivot/tanzu-spring-petclinic

kubectl config use-context $kube_context
echo

#pe "tanzu apps workload delete --all --yes"
#echo

pe "tanzu apps workload list"
echo

#pe "tanzu apps workload create ${app_name} --git-repo ${git_app_url} --git-branch main --type web --label app.kubernetes.io/part-of=${app_name} --yes --dry-run"
#echo

pe "tanzu apps workload delete ${app_name} --yes"
echo

pe "service_ref=$(kubectl get resourceclaim rds-claim -o jsonpath='{.apiVersion}')"
echo

pe "claim_name=$(kubectl get resourceclaim rds-claim -o jsonpath='{.metadata.name}')"
echo

pe "tanzu apps workload create ${app_name} --git-repo ${git_app_url} --git-branch main --type web --label app.kubernetes.io/part-of=${app_name} --annotation autoscaling.knative.dev/minScale=1 --env SPRING_PROFILES_ACTIVE=postgres --service-ref db=${service_ref}:ResourceClaim:${claim_name} --yes"
echo

pe "clear"

pe "tanzu apps workload tail ${app_name} --since 1h --timestamp"
echo

pe "tanzu apps workload list"
echo

pe "tanzu apps workload get ${app_name}"
echo

#pe "kubectl api-resources | grep knative"
#echo

#kubectl get ksvc

#kubectl get deliverable

#kubectl get services.serving.knative

pe "kubectl get configmaps"
echo

pe "rm ${app_name}-deliverable.yaml"
pe "kubectl get configmap ${app_name}-deliverable -o go-template='{{.data.deliverable}}' > ${app_name}-deliverable.yaml"
echo

kubectl config get-contexts
read -p "Select run context: " kube_context

kubectl config use-context $kube_context
echo

pe "kubectl delete -f ${app_name}-deliverable.yaml"
echo

pe "kubectl apply -f ${app_name}-deliverable.yaml"
echo

pe "kubectl get deliverables"
echo

#pe "kubectl get httpproxy"
#echo

echo http://${app_name}.default.run.tap.nycpivot.com
