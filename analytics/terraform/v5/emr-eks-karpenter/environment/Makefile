init:
	terraform init -upgrade

validate:
	terraform fmt -recursive
	terraform validate

plan:
	terraform fmt -recursive
	terraform validate
	terraform plan -var-file="dev.tfvars"

apply:
	terraform fmt -recursive
	terraform validate
	terraform apply -var-file="dev.tfvars" -auto-approve

destroy:
	terraform destroy -var-file="variables.tfvars" -target="module.eks_blueprints_kubernetes_addons" -auto-approve
	terraform destroy -var-file="variables.tfvars" -target="module.eks_blueprints" -auto-approve
	terraform destroy -var-file="variables.tfvars" -target="module.vpc" -auto-approve
	terraform destroy -var-file="variables.tfvars" -auto-approve

all: init validate plan apply
