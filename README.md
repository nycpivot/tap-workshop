# TAP Workshop

This repository offers application developers and operators practical examples for getting started with TAP (Tanzu Application Platform). The following is a common set of use-cases most applications will encounter.

* [TAP Services Toolkit](https://docs.vmware.com/en/Services-Toolkit-for-VMware-Tanzu-Application-Platform/index.html), used for the creation and underlying infrastructure to host backend services, such as, databases, message queues, caches, and making them easily discoverable to developers for integration and consumption.

## Prerequisites

* Kubernetes cluster (minimum version 1.23)
* TAP (version 1.4 or higher)
* Tanzu CLI and plugins
* Domain name, subdomains with wildcard

## Getting Started

TAP is a complete end-to-end supply chain capable of monitoring a source code repository for changes, compiling and building executable binaries packaged into OCI-conformant containers, deployed to any Kubernetes cluster running on-premises or a public cloud provider. This requires several different components with different responsibilities communicating with one another.

Depending on the environment TAP will be deployed to, these different components can all be installed on a single cluster or multiple clusters. This repository contains AWS CloudFormation templates for bootstrapping either a single AWS EKS Cluster or multiple AWS EKS Clusters into their own respective VPCs, depending on the environment. TAP refers to these as Full Profile and Multi Profile, respectively.

* [Single Cluster](full-profile)
* [Multi Cluster](multi-profile)

Navigate to either of these links to begin installation steps.