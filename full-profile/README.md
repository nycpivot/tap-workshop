# TAP Workshop - Full Profile

A full profile will install all TAP components on a single cluster. Follow these instructions based on your environment.

## Existing Cluster

To install TAP on an existing cluster, begin with 01-tap-install-full-any.sh. This will install Tanzu and TAP on your cluster.

## New Cluster

To start from scratch, run 00-aws-prereqs.sh first to create all the necessary AWS resources, including a VPC, subnets, and an EKS cluster. Then run 01-tap-install-full-eks.sh to install Tanzu and TAP.

## Explanation of Scripts

The following list of scripts briefly summarizes the purpose of each script.

* 00-aws-prereqs.sh, runs the CloudFormation template in the config folder.
* 01-tap-install-full-any.sh, assumes an existing cluster and begins by installing Tanzu and TAP.
* 01-tap-install-full-eks.sh, contains all the steps with the only prerequisite of having an existing EKS cluster. See below for detailed steps.

### Secrets

The first stage collects all the secrets for pulling images from both Tanzu network and registry TAP will use for building code and storing application images. In this workshop, AWS Secrets Manager is used for storage and AWS CLI for retrieval during installation and secrets creation in cluster.

### Kube Config

The CloudFormation script creates the EKS Cluster, but does not set the connection details in kubeconfig. This section updates the config and renames the context.

### Install CSI Plugin (K8s 1.23 and higher)

AWS requires that all K8s clusters using version 1.23 or higher must manually configure storage by applying the plugins. This section in the script automates this whole process.

### RBAC for ECR (Elastic Container Registry)

This section configures the roles and policies that will be attached to the cluster so it will have the necessary permissions to push and pull images to the container registry.

### Tanzu and Cluster Essentials Prerequisites

Installs the Tanzu CLI, its plugins, and Carvel tools.

### Import TAP Packages

The TAP images are exported from Tanzu Network or Pivnet and imported into the container registry of choice. This workshop uses AWS ECR.

### Install Full TAP Profile

The tap-values file is created and applied to the cluster.

### Configure DNS name with ELB IP

This section retrieves the address of the ELB to get the corresponding IP address, which is used to update an A record of the DNS record. In this case, Route 53 using the AWS CLI.

### Developer Namespace

This final section creates the secrets in the cluster namespace that are used to pull images from the registry for running application workloads.

### TAP GUI

A URL will be output to open tap-gui in the browser.
