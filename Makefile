# .env file se saare variables load karo
include .env
export

# ─── Helpers ───────────────────────────────────────────────────────────────────
comma := ,
# "a,b,c" ko ["a","b","c"] mein convert karta hai (Terraform list format)
json_list = ["$(subst $(comma),"$(comma)",$(1))"]

# ─── Terraform Variables (.env → TF_VAR_*) ────────────────────────────────────
export TF_VAR_environment                      = $(ENVIRONMENT)
export TF_VAR_aws_region                       = $(AWS_REGION)
export TF_VAR_cluster_name                     = $(CLUSTER_NAME)
export TF_VAR_cluster_version                  = $(CLUSTER_VERSION)
export TF_VAR_vpc_cidr                         = $(VPC_CIDR)
export TF_VAR_single_nat_gateway               = $(SINGLE_NAT_GATEWAY)
export TF_VAR_endpoint_public_access           = $(ENDPOINT_PUBLIC_ACCESS)
export TF_VAR_node_instance_type               = $(NODE_INSTANCE_TYPE)
export TF_VAR_node_min_size                    = $(NODE_MIN_SIZE)
export TF_VAR_node_max_size                    = $(NODE_MAX_SIZE)
export TF_VAR_node_desired_size                = $(NODE_DESIRED_SIZE)
export TF_VAR_node_disk_size                   = $(NODE_DISK_SIZE)
export TF_VAR_coredns_version                  = $(COREDNS_VERSION)
export TF_VAR_kube_proxy_version               = $(KUBE_PROXY_VERSION)
export TF_VAR_vpc_cni_version                  = $(VPC_CNI_VERSION)
export TF_VAR_alb_controller_chart_version     = $(ALB_CONTROLLER_CHART_VERSION)
export TF_VAR_cluster_autoscaler_chart_version = $(CLUSTER_AUTOSCALER_CHART_VERSION)

# List variables → JSON array (TF_VAR ke liye zaroori format)
export TF_VAR_azs                  = $(call json_list,$(AZS))
export TF_VAR_public_subnet_cidrs  = $(call json_list,$(PUBLIC_SUBNET_CIDRS))
export TF_VAR_private_subnet_cidrs = $(call json_list,$(PRIVATE_SUBNET_CIDRS))
export TF_VAR_public_access_cidrs  = $(call json_list,$(PUBLIC_ACCESS_CIDRS))

# ─── Backend Config (.env se — TF_VAR nahi, init flags ke zariye jaata hai) ───
BACKEND_KEY = eks/$(ENVIRONMENT)/terraform.tfstate

# ─── Targets ───────────────────────────────────────────────────────────────────
.PHONY: init plan apply destroy validate fmt output phase1 phase2

init:
	terraform init \
	  -backend-config="bucket=$(TF_STATE_BUCKET)" \
	  -backend-config="key=$(BACKEND_KEY)" \
	  -backend-config="region=$(AWS_REGION)" \
	  -backend-config="dynamodb_table=$(TF_STATE_DYNAMODB_TABLE)" \
	  -backend-config="encrypt=true"

plan: init
	terraform plan

apply: init
	terraform apply

destroy: init
	terraform destroy

validate: init
	terraform validate

fmt:
	terraform fmt -recursive

output:
	terraform output

# IRSA circular dependency ke liye — pehle phase1, phir phase2
phase1: init
	terraform apply -target=module.vpc -target=module.eks_cluster

phase2: init
	terraform apply
