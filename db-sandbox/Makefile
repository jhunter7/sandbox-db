.PHONY: \
	plan \
	apply \
	init \
	destroy


plan:
	terraform plan -out tfplan

apply:
	terraform apply tfplan

init:
	terraform init

destroy:
	terraform plan -out tfplan -destroy
