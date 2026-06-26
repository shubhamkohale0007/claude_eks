# .env file se saare variables load karo
include .env
export

# ─── Helpers ───────────────────────────────────────────────────────────────────
comma := ,
# "a,b,c" ko ["a","b","c"] mein convert karta hai (Terraform list format)
json_list = ["$(subst $(comma),"$(comma)",$(1))"]

BACKEND_KEY = eks/$(ENVIRONMENT)/terraform.tfstate

# ─── Targets ───────────────────────────────────────────────────────────────────
.PHONY: replace init plan apply destroy validate fmt output phase1 phase2 tag release

# .env se terraform.tfvars generate karta hai — TF_VAR_* ki zaroorat nahi
replace:
	@echo '# Auto-generated from .env — do not edit manually' > terraform.tfvars
	@echo 'environment                      = "$(ENVIRONMENT)"'              >> terraform.tfvars
	@echo 'aws_region                       = "$(AWS_REGION)"'              >> terraform.tfvars
	@echo 'cluster_name                     = "$(CLUSTER_NAME)"'            >> terraform.tfvars
	@echo 'cluster_version                  = "$(CLUSTER_VERSION)"'         >> terraform.tfvars
	@echo 'vpc_cidr                         = "$(VPC_CIDR)"'               >> terraform.tfvars
	@echo 'single_nat_gateway               = $(SINGLE_NAT_GATEWAY)'        >> terraform.tfvars
	@echo 'endpoint_public_access           = $(ENDPOINT_PUBLIC_ACCESS)'    >> terraform.tfvars
	@echo 'node_instance_type               = "$(NODE_INSTANCE_TYPE)"'      >> terraform.tfvars
	@echo 'node_min_size                    = $(NODE_MIN_SIZE)'             >> terraform.tfvars
	@echo 'node_max_size                    = $(NODE_MAX_SIZE)'             >> terraform.tfvars
	@echo 'node_desired_size                = $(NODE_DESIRED_SIZE)'         >> terraform.tfvars
	@echo 'node_disk_size                   = $(NODE_DISK_SIZE)'            >> terraform.tfvars
	@echo 'coredns_version                  = "$(COREDNS_VERSION)"'         >> terraform.tfvars
	@echo 'kube_proxy_version               = "$(KUBE_PROXY_VERSION)"'      >> terraform.tfvars
	@echo 'vpc_cni_version                  = "$(VPC_CNI_VERSION)"'         >> terraform.tfvars
	@echo 'alb_controller_chart_version     = "$(ALB_CONTROLLER_CHART_VERSION)"'     >> terraform.tfvars
	@echo 'cluster_autoscaler_chart_version = "$(CLUSTER_AUTOSCALER_CHART_VERSION)"' >> terraform.tfvars
	@echo 'azs                              = $(call json_list,$(AZS))'              >> terraform.tfvars
	@echo 'public_subnet_cidrs              = $(call json_list,$(PUBLIC_SUBNET_CIDRS))'  >> terraform.tfvars
	@echo 'private_subnet_cidrs             = $(call json_list,$(PRIVATE_SUBNET_CIDRS))' >> terraform.tfvars
	@echo 'public_access_cidrs              = $(call json_list,$(PUBLIC_ACCESS_CIDRS))'  >> terraform.tfvars
	@echo "terraform.tfvars generated from .env"

init: replace
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

# ─── Version Tagging ───────────────────────────────────────────────────────────
# Usage: make tag VERSION=v1.0.0 MSG="Release message"
tag:
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required. Usage: make tag VERSION=v1.0.0"; exit 1)
	@test -n "$(MSG)"     || (echo "ERROR: MSG is required.     Usage: make tag MSG=\"your message\""; exit 1)
	git tag -a $(VERSION) -m "$(MSG)"
	git push origin $(VERSION)
	@echo "Tag $(VERSION) created and pushed."

# Usage: make release VERSION=v1.0.0 MSG="Release notes"
release:
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required. Usage: make release VERSION=v1.0.0"; exit 1)
	@test -n "$(MSG)"     || (echo "ERROR: MSG is required.     Usage: make release MSG=\"your notes\""; exit 1)
	git tag -a $(VERSION) -m "$(MSG)"
	git push origin $(VERSION)
	gh release create $(VERSION) --title "$(VERSION)" --notes "$(MSG)"
	@echo "GitHub Release $(VERSION) created."
